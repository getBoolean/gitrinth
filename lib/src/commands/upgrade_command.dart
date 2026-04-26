import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/constraint.dart';
import '../service/cache.dart';
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
        help: 'Also upgrades the transitive dependencies of the listed '
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
          console.info(
            "skipping '$slug' — still marked ${raw?.trim()} on the "
            'current target.',
          );
        } else {
          console.detail(
            "skipping '$slug' — non-Modrinth source has no version to upgrade.",
          );
        }
      }
    }

    if (unlockTransitive && targets.isNotEmpty) {
      targets = _expandTransitiveClosure(
        targets,
        io.readModsLock(),
        read(cacheProvider),
      );
    }

    final relaxSet = <String>{
      // Recovered entries have no real constraint; pick newest.
      for (final slug in recoveredSlugs)
        if (targets.contains(slug)) slug,
      if (majorVersions)
        for (final entry in modrinthByEntry.entries)
          if (targets.contains(entry.key.$2) &&
              (entry.value.constraintRaw?.trimLeft().startsWith('^') ??
                  false))
            entry.key.$2,
    };

    final unrecoverableMarkers = <String>{
      for (final (_, slug) in markerByEntry.keys)
        if (!recoveredSlugs.contains(slug)) slug,
    };
    final manifestForResolve = unrecoverableMarkers.isEmpty
        ? null
        : _stripSlugs(manifest, unrecoverableMarkers);

    final cache = read(cacheProvider);
    final downloader = read(downloaderProvider);
    final loaderResolver = read(loaderVersionResolverProvider);
    final reporter = SolveReporter(console);

    final result = await resolveAndSync(
      io: io,
      console: console,
      api: api,
      cache: cache,
      downloader: downloader,
      loaderResolver: loaderResolver,
      verbose: gitrinthRunner.verbose,
      offline: offline,
      dryRun: dryRun,
      freshSlugs: targets,
      relaxConstraints: relaxSet,
      manifestOverride: manifestForResolve,
    );

    if (result.exitCode != exitOk) {
      return result.exitCode;
    }
    if (dryRun) {
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
        final priorMarker = markerByEntry[(section, slug)]?.constraintRaw
                ?.trim() ??
            notFoundMarker;
        yamlText = setEntryVersion(
          yamlText,
          section: section,
          slug: slug,
          newVersion: '^$bareResolved',
        );
        rewrites++;
        console.info('$slug: $priorMarker → ^$bareResolved in mods.yaml');
      }
      if (rewrites > 0) io.writeModsYaml(yamlText);
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

  /// BFS over the dep graph to compute the transitive closure of
  /// [seeds]. Powers `--unlock-transitive`: every slug in the returned
  /// set is fed to [resolveAndSync] as a `freshSlug`, so the resolver
  /// picks newest-within-constraint instead of preserving the existing
  /// pin.
  ///
  /// Edges are read from the artifact cache's per-version `version.json`
  /// (mirrors dart pub's "graph in cache" architecture — see
  /// [GitrinthCache.modrinthVersionMetadataPath]). Cold-cache entries
  /// (a slug whose `version.json` hasn't been written yet) are reported
  /// via `console.detail` and their children are skipped; subsequent
  /// runs populate the cache.
  Set<String> _expandTransitiveClosure(
    Set<String> seeds,
    ModsLock? lock,
    GitrinthCache cache,
  ) {
    if (lock == null) {
      console.info(
        'upgrade --unlock-transitive: no mods.lock found yet — '
        'falling back to unlocking only the named entries.',
      );
      return seeds;
    }

    final lookup = <String, LockedEntry>{};
    final projectIdToSlug = <String, String>{};
    for (final entry in lock.allEntries) {
      lookup[entry.key] = entry.value;
      final pid = entry.value.projectId;
      if (pid != null) projectIdToSlug[pid] = entry.key;
    }

    final closure = <String>{...seeds};
    final queue = <String>[...seeds];
    while (queue.isNotEmpty) {
      final slug = queue.removeLast();
      final entry = lookup[slug];
      if (entry == null) {
        console.detail(
          "upgrade --unlock-transitive: '$slug' not in mods.lock; skipping.",
        );
        continue;
      }
      if (entry.sourceKind != LockedSourceKind.modrinth) continue;
      final pid = entry.projectId;
      final vid = entry.versionId;
      if (pid == null || vid == null) continue;

      final children = _readCachedRequiredChildren(cache, pid, vid);
      if (children == null) {
        console.detail(
          "upgrade --unlock-transitive: no cached version.json for "
          "'$slug' ($pid/$vid); skipping its transitive children. "
          'Run `gitrinth get` to populate the cache.',
        );
        continue;
      }
      for (final childPid in children) {
        final childSlug = projectIdToSlug[childPid];
        if (childSlug == null) continue;
        if (closure.add(childSlug)) queue.add(childSlug);
      }
    }
    return closure;
  }

  /// Reads the `dependencies` array out of the cached `version.json`
  /// and returns the list of `project_id`s for entries whose
  /// `dependency_type == "required"`. Returns null when the cache file
  /// is missing or unparseable (cold cache); returns an empty list when
  /// the version legitimately has no required deps.
  List<String>? _readCachedRequiredChildren(
    GitrinthCache cache,
    String projectId,
    String versionId,
  ) {
    final path = cache.modrinthVersionMetadataPath(
      projectId: projectId,
      versionId: versionId,
    );
    final file = File(path);
    if (!file.existsSync()) return null;
    final dynamic raw;
    try {
      raw = jsonDecode(file.readAsStringSync());
    } on Object {
      return null;
    }
    if (raw is! Map) return null;
    final deps = raw['dependencies'];
    if (deps is! List) return const [];
    final out = <String>[];
    for (final d in deps) {
      if (d is! Map) continue;
      if (d['dependency_type'] != 'required') continue;
      final pid = d['project_id'];
      if (pid is String && pid.isNotEmpty) out.add(pid);
    }
    return out;
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
