import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/constraint.dart';
import '../service/conflict_disable.dart';
import '../service/lock_graph.dart';
import '../service/manifest_io.dart';
import '../service/modrinth_api.dart';
import '../service/resolve_and_sync.dart';
import '../service/solve_report.dart';
import 'caret_rewriter.dart';
import 'migrate_editor.dart';

class UpgradeCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'upgrade';

  @override
  String get description =>
      "Upgrade the current modpack's entries to the newest versions.";

  @override
  String get invocation => 'gitrinth upgrade [<slug>...] [arguments]';

  UpgradeCommand() {
    argParser
      ..addFlag(
        'major-versions',
        negatable: false,
        help:
            'Upgrades entries to their latest resolvable versions, and '
            'updates mods.yaml.',
      )
      ..addFlag(
        'tighten',
        negatable: false,
        help:
            'Updates lower bounds in mods.yaml to match the resolved version.',
      )
      ..addFlag(
        'unlock-transitive',
        negatable: false,
        help:
            'Also upgrades the transitive dependencies of the listed '
            'entries.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: "Report what entries would change but don't change any.",
      );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final majorVersions = results['major-versions'] as bool;
    final tighten = results['tighten'] as bool;
    final unlockTransitive = results['unlock-transitive'] as bool;
    final dryRun = results['dry-run'] as bool;
    final offline = readOfflineFlag();
    final requestedSlugs = results.rest;

    final io = ManifestIo();
    final manifest = io.readModsYaml();

    final modrinthByEntry = <(Section, String), ModEntry>{};
    final markerByEntry = <(Section, String), ModEntry>{};
    final nonModrinthSlugs = <String>{};
    for (final section in Section.values) {
      manifest.sectionEntries(section).forEach((slug, entry) {
        if (entry.source is ModrinthEntrySource) {
          // Both `gitrinth:not-found` and `gitrinth:disabled-by-conflict`
          // are recoverable — `--major-versions` will try to bring them
          // back to a fresh `^x.y.z` and either succeed or re-mark them
          // via the conflict-catch below.
          if (isAnyGitrinthMarker(entry.constraintRaw)) {
            markerByEntry[(section, slug)] = entry;
          } else {
            modrinthByEntry[(section, slug)] = entry;
          }
        } else {
          nonModrinthSlugs.add(slug);
        }
      });
    }
    final modrinthSlugs = {for (final k in modrinthByEntry.keys) k.$2};
    final markerSlugs = {for (final k in markerByEntry.keys) k.$2};
    final allSlugs = {...modrinthSlugs, ...markerSlugs, ...nonModrinthSlugs};

    final api = read(modrinthApiProvider);

    // Recovery rewrites a constraint, so it's gated on --major-versions.
    final recovered = <(Section, String)>{};
    if (majorVersions && !offline && markerByEntry.isNotEmpty) {
      for (final pair in markerByEntry.entries) {
        final (_, slug) = pair.key;
        final entry = pair.value;
        final gameVersions = <String>{
          manifest.mcVersion,
          ...entry.acceptsMc,
        }.toList();
        List versions;
        try {
          versions = await api.listVersions(
            slug,
            loadersJson: encodeFilterArray([manifest.loader.mods.name]),
            gameVersionsJson: encodeFilterArray(gameVersions),
          );
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) {
            versions = const [];
          } else {
            rethrow;
          }
        }
        final loaderName = manifest.loader.mods.name;
        final hasMatch = versions.any((v) {
          final loaderOk = (v.loaders as List).contains(loaderName);
          final mcOk = (v.gameVersions as List).any(gameVersions.contains);
          return loaderOk && mcOk;
        });
        if (hasMatch) recovered.add(pair.key);
      }
    }
    final recoveredSlugs = {for (final k in recovered) k.$2};

    Set<String> targets;
    if (requestedSlugs.isEmpty) {
      targets = {...modrinthSlugs, ...recoveredSlugs};
    } else {
      final unknown = requestedSlugs
          .where((s) => !allSlugs.contains(s))
          .toList();
      if (unknown.isNotEmpty) {
        throw UsageError(
          'unknown entry/entries in mods.yaml: ${unknown.join(', ')}',
        );
      }
      targets = <String>{};
      for (final slug in requestedSlugs) {
        if (modrinthSlugs.contains(slug) || recoveredSlugs.contains(slug)) {
          targets.add(slug);
        } else if (markerSlugs.contains(slug)) {
          final raw = markerByEntry.entries
              .firstWhere((e) => e.key.$2 == slug)
              .value
              .constraintRaw;
          console.message(
            "skipping '$slug' — still marked ${raw?.trim()} on the "
            'current target.',
          );
        } else {
          console.io(
            "skipping '$slug' — non-Modrinth source has no version to upgrade.",
          );
        }
      }
    }

    if (unlockTransitive && targets.isNotEmpty) {
      targets = walkTransitiveClosure(
        targets,
        io.readModsLock(),
        read(cacheProvider),
        console: console,
        verboseLabel: 'upgrade --unlock-transitive',
      );
    }

    final relaxSet = <String>{
      // Recovered entries have no real constraint; pick newest.
      for (final slug in recoveredSlugs)
        if (targets.contains(slug)) slug,
      if (majorVersions)
        for (final entry in modrinthByEntry.entries)
          if (targets.contains(entry.key.$2) &&
              (entry.value.constraintRaw?.trimLeft().startsWith('^') ?? false))
            entry.key.$2,
    };

    final unrecoverableMarkers = <String>{
      for (final (_, slug) in markerByEntry.keys)
        if (!recoveredSlugs.contains(slug)) slug,
    };
    final manifestForResolve = unrecoverableMarkers.isEmpty
        ? null
        : _stripSlugs(manifest, unrecoverableMarkers);

    final reporter = SolveReporter(console);

    Future<ResolveSyncResult> doResolve({
      required ModsYaml? manifestForResolve,
      required Set<String> freshSlugs,
      required Set<String> relaxConstraints,
    }) => runResolveAndSync(
      io: io,
      offline: offline,
      dryRun: dryRun,
      freshSlugs: freshSlugs,
      relaxConstraints: relaxConstraints,
      manifestOverride: manifestForResolve,
    );

    final ResolveSyncResult result;
    final Set<(Section, String)> disabledByConflict;
    if (majorVersions) {
      // --major-versions gains the same auto-disable retry path migrate
      // uses. Plain `upgrade` keeps current single-pass behavior — an
      // UnsatisfiableGraphError propagates verbatim to the runner.
      final outcome = await resolveWithConflictAutoDisable(
        manifest: manifest,
        resolutionManifest: manifestForResolve ?? manifest,
        targets: targets,
        relaxSet: relaxSet,
        console: console,
        resolve:
            ({
              required manifestForResolve,
              required freshSlugs,
              required relaxConstraints,
            }) => doResolve(
              manifestForResolve: manifestForResolve,
              freshSlugs: freshSlugs,
              relaxConstraints: relaxConstraints,
            ),
      );
      result = outcome.result;
      disabledByConflict = outcome.disabledByConflict;
    } else {
      result = await doResolve(
        manifestForResolve: manifestForResolve,
        freshSlugs: targets,
        relaxConstraints: relaxSet,
      );
      disabledByConflict = const {};
    }

    if (result.exitCode != exitOk) {
      return result.exitCode;
    }
    if (dryRun) {
      if (disabledByConflict.isNotEmpty) {
        final names = disabledByConflict.map((s) => s.$2).toList()..sort();
        console.message(
          '[dry-run] would disable ${names.length} mod(s) due to '
          'dependency conflict: ${names.join(", ")}',
        );
      }
      return exitOk;
    }

    if (recovered.isNotEmpty && result.newLock != null) {
      var yamlText = File(io.modsYamlPath).readAsStringSync();
      final newLock = result.newLock!;
      var rewrites = 0;
      for (final (section, slug) in recovered) {
        if (!targets.contains(slug)) continue;
        final resolvedRaw = newLock.sectionFor(section)[slug]?.version;
        if (resolvedRaw == null) continue;
        final String bareResolved;
        try {
          bareResolved = bareVersionForPin(resolvedRaw);
        } on FormatException {
          continue;
        }
        // Look up the prior marker so the message names whichever one
        // was actually being recovered.
        final priorMarker =
            markerByEntry[(section, slug)]?.constraintRaw?.trim() ??
            notFoundMarker;
        yamlText = setEntryVersion(
          yamlText,
          section: section,
          slug: slug,
          newVersion: '^$bareResolved',
        );
        rewrites++;
        console.message('$slug: $priorMarker → ^$bareResolved in mods.yaml');
      }
      if (rewrites > 0) io.writeModsYaml(yamlText);
    }

    // Persist the auto-disable markers from the conflict-retry path
    // (only reachable under --major-versions). Mirrors migrate's
    // marker-rewrite loop.
    if (disabledByConflict.isNotEmpty) {
      var yamlText = File(io.modsYamlPath).readAsStringSync();
      for (final (section, slug) in disabledByConflict) {
        yamlText = setEntryVersion(
          yamlText,
          section: section,
          slug: slug,
          newVersion: disabledByConflictMarker,
        );
      }
      io.writeModsYaml(yamlText);
    }

    if ((majorVersions || tighten) && result.newLock != null) {
      rewriteCaretConstraints(
        io: io,
        console: console,
        modrinthByEntry: modrinthByEntry,
        targets: targets,
        relaxSet: relaxSet,
        majorVersions: majorVersions,
        tighten: tighten,
        newLock: result.newLock!,
      );
    }

    reporter.printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    if (offline) {
      console.warn(
        'Upgrading when offline may not update you to the latest '
        'versions of your dependencies.',
      );
    }
    return exitOk;
  }
}

ModsYaml _stripSlugs(ModsYaml manifest, Set<String> slugs) {
  Map<String, ModEntry> strip(Map<String, ModEntry> m) => {
    for (final e in m.entries)
      if (!slugs.contains(e.key)) e.key: e.value,
  };
  return manifest.copyWith(
    mods: strip(manifest.mods),
    resourcePacks: strip(manifest.resourcePacks),
    dataPacks: strip(manifest.dataPacks),
    shaders: strip(manifest.shaders),
  );
}
