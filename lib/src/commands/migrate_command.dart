import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../model/resolver/pubgrub.dart';
import '../service/manifest_io.dart';
import '../service/modrinth_api.dart';
import '../service/resolve_and_sync.dart';
import 'caret_rewriter.dart';
import 'migrate_editor.dart';

class MigrateCommand extends GitrinthCommand {
  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Re-target the modpack to a new Minecraft version or loader.';

  @override
  String get invocation => 'gitrinth migrate <subcommand>';

  MigrateCommand() {
    addSubcommand(MigrateMcCommand());
    addSubcommand(MigrateLoaderCommand());
  }

  @override
  Future<int> run() async {
    printUsage();
    return exitOk;
  }
}

class MigrateMcCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'mc';

  @override
  String get description =>
      "Bump `mc-version` and re-resolve.";

  @override
  String get invocation => 'gitrinth migrate mc <version> [arguments]';

  MigrateMcCommand() {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: "Resolve and report the diff without writing files.",
    );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final rest = results.rest;
    if (rest.isEmpty) {
      throw const UsageError('migrate mc: missing target Minecraft version.');
    }
    if (rest.length > 1) {
      throw UsageError(
        'migrate mc: expected exactly one positional argument, got '
        '${rest.length}.',
      );
    }
    final newMcVersion = rest.single.trim();
    if (newMcVersion.isEmpty) {
      throw const UsageError('migrate mc: target version is empty.');
    }

    return _runMigrate(
      newMcVersion: newMcVersion,
      newLoader: null,
      newLoaderTag: null,
      dryRun: results['dry-run'] as bool,
      offline: readOfflineFlag(),
      command: this,
    );
  }
}

class MigrateLoaderCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'loader';

  @override
  String get description => 'Switch the mod loader and re-resolve.';

  @override
  String get invocation =>
      'gitrinth migrate loader <loader>[:<tag>] [arguments]';

  MigrateLoaderCommand() {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: "Resolve and report the diff without writing files.",
    );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final rest = results.rest;
    if (rest.isEmpty) {
      throw const UsageError(
        'migrate loader: missing target loader (e.g. `fabric`, '
        '`neoforge:stable`).',
      );
    }
    if (rest.length > 1) {
      throw UsageError(
        'migrate loader: expected exactly one positional argument, got '
        '${rest.length}.',
      );
    }
    final (loader, tag) = _parseLoaderArg(rest.single);

    return _runMigrate(
      newMcVersion: null,
      newLoader: loader,
      newLoaderTag: tag,
      dryRun: results['dry-run'] as bool,
      offline: readOfflineFlag(),
      command: this,
    );
  }
}

(Loader, String) _parseLoaderArg(String raw) {
  final colon = raw.indexOf(':');
  final namePart = (colon < 0 ? raw : raw.substring(0, colon)).toLowerCase();
  final tagPart = colon < 0 ? 'stable' : raw.substring(colon + 1);
  if (tagPart.isEmpty) {
    throw UsageError(
      'migrate loader: "$raw" has an empty tag '
      '(use `<loader>` or `<loader>:<version|stable|latest>`).',
    );
  }
  if (tagPart.contains(':')) {
    throw UsageError(
      'migrate loader: "$raw" has more than one `:` '
      '(expected `<loader>` or `<loader>:<version|stable|latest>`).',
    );
  }
  switch (namePart) {
    case 'forge':
      return (Loader.forge, tagPart);
    case 'fabric':
      return (Loader.fabric, tagPart);
    case 'neoforge':
      return (Loader.neoforge, tagPart);
    default:
      throw UsageError(
        'migrate loader: "$namePart" is not a supported loader '
        '(allowed: forge, fabric, neoforge).',
      );
  }
}

Future<int> _runMigrate({
  required String? newMcVersion,
  required Loader? newLoader,
  required String? newLoaderTag,
  required bool dryRun,
  required bool offline,
  required GitrinthCommand command,
}) async {
  final console = command.console;
  final io = ManifestIo();
  final manifest = io.readModsYaml();

  final mutated = _applyTarget(
    manifest,
    newMcVersion: newMcVersion,
    newLoader: newLoader,
    newLoaderTag: newLoaderTag,
  );
  final targetMc = mutated.mcVersion;
  final targetLoader = mutated.loader.mods;

  final api = command.read(modrinthApiProvider);

  final available = <(Section, String)>{};
  final recovered = <(Section, String)>{};
  final lost = <(Section, String)>{};
  final persistentNotFound = <(Section, String)>{};

  if (offline) {
    for (final section in Section.values) {
      manifest.sectionEntries(section).forEach((slug, entry) {
        if (entry.source is! ModrinthEntrySource) return;
        if (isAnyGitrinthMarker(entry.constraintRaw)) {
          persistentNotFound.add((section, slug));
        } else {
          available.add((section, slug));
        }
      });
    }
    console.warn(
      'migrate --offline: skipping availability check.',
    );
  } else {
    for (final section in Section.values) {
      final entries = manifest.sectionEntries(section);
      for (final pair in entries.entries) {
        final slug = pair.key;
        final entry = pair.value;
        if (entry.source is! ModrinthEntrySource) continue;
        // Both `gitrinth:not-found` and `gitrinth:disabled-by-conflict`
        // are recoverable — give them a fresh resolution attempt with
        // their constraint relaxed to `any`, and either rewrite to
        // `^x.y.z` on success or re-mark on the next conflict catch.
        final isMarker = isAnyGitrinthMarker(entry.constraintRaw);
        final gameVersions = <String>{targetMc, ...entry.acceptsMc}.toList();
        List<modrinth.Version> versions;
        try {
          versions = await api.listVersions(
            slug,
            loadersJson: encodeFilterArray([targetLoader.name]),
            gameVersionsJson: encodeFilterArray(gameVersions),
          );
        } on DioException catch (e) {
          // 404 (unknown slug) → treated as not-found.
          if (e.response?.statusCode == 404) {
            versions = const [];
          } else {
            final err = e.error;
            if (err is GitrinthException) rethrow;
            throw UserError(
              'migrate: failed to list versions for "$slug" on '
              '${targetLoader.name} $targetMc: $e',
            );
          }
        }
        final filtered = versions.where((v) {
          final loaderOk = v.loaders.contains(targetLoader.name);
          final mcOk = v.gameVersions.any(gameVersions.contains);
          return loaderOk && mcOk;
        }).toList();
        if (filtered.isEmpty) {
          if (isMarker) {
            persistentNotFound.add((section, slug));
          } else {
            lost.add((section, slug));
          }
        } else {
          if (isMarker) {
            recovered.add((section, slug));
          } else {
            available.add((section, slug));
          }
        }
      }
    }
  }

  final stripSlugs = <String>{
    for (final s in lost) s.$2,
    for (final s in persistentNotFound) s.$2,
  };
  final resolutionManifest = stripSlugs.isEmpty
      ? mutated
      : _stripSlugs(mutated, stripSlugs);

  final targets = <String>{
    for (final s in available) s.$2,
    for (final s in recovered) s.$2,
  };
  final relaxSet = <String>{
    for (final s in recovered) s.$2,
    for (final s in available)
      if ((manifest.sectionEntries(s.$1)[s.$2]?.constraintRaw ?? '')
          .trimLeft()
          .startsWith('^'))
        s.$2,
  };

  final cache = command.read(cacheProvider);
  final downloader = command.read(downloaderProvider);
  final loaderResolver = command.read(loaderVersionResolverProvider);

  ResolveSyncResult result;
  final disabledByConflict = <(Section, String)>{};
  try {
    result = await resolveAndSync(
      io: io,
      console: console,
      api: api,
      cache: cache,
      downloader: downloader,
      loaderResolver: loaderResolver,
      verbose: command.gitrinthRunner.verbose,
      offline: offline,
      dryRun: dryRun,
      freshSlugs: targets,
      relaxConstraints: relaxSet,
      manifestOverride: resolutionManifest,
    );
  } on UnsatisfiableGraphError catch (e) {
    // Compute the disable set: user-declared roots in `mods.yaml`
    // that the solver flagged as conflict participants.
    for (final slug in e.conflictingUserSlugs) {
      for (final section in Section.values) {
        if (manifest.sectionEntries(section).containsKey(slug)) {
          disabledByConflict.add((section, slug));
          break;
        }
      }
    }
    if (disabledByConflict.isEmpty) rethrow;

    // Apply the markers in-memory and re-resolve. The retry must NOT
    // relax the disabled slugs — their `disabledByConflictMarker` has
    // to reach the resolver-skip in `resolver.dart`, otherwise
    // `_relaxManifestConstraints` would rewrite it back to `null`
    // (= any) and PubGrub would re-encounter the same conflict.
    final candidateManifest = _applyDisableMarkers(
      resolutionManifest,
      disabledByConflict,
    );
    final retryRelax = relaxSet.difference({
      for (final s in disabledByConflict) s.$2,
    });
    try {
      result = await resolveAndSync(
        io: io,
        console: console,
        api: api,
        cache: cache,
        downloader: downloader,
        loaderResolver: loaderResolver,
        verbose: command.gitrinthRunner.verbose,
        offline: offline,
        dryRun: dryRun,
        freshSlugs: targets,
        relaxConstraints: retryRelax,
        manifestOverride: candidateManifest,
      );
    } on UnsatisfiableGraphError catch (cascade) {
      // Disabling all conflict roots still left an unsatisfiable graph.
      // Roll back: nothing was written. Surface both failures.
      throw ValidationError(
        'Disabling ${disabledByConflict.map((s) => s.$2).join(", ")} did '
        'not resolve the conflict — re-resolution still failed:\n'
        '${cascade.message}\n\n'
        'Original failure:\n${e.message}',
      );
    }
    final names = disabledByConflict.map((s) => s.$2).toList()..sort();
    console.info(
      'disabled ${names.length} mod(s) due to dependency conflict: '
      '${names.join(", ")}. Edit mods.yaml to re-enable any you want '
      'back, then re-run.',
    );
  }

  if (result.exitCode != exitOk) {
    return result.exitCode;
  }

  if (dryRun) {
    _printSummary(
      console: console,
      target: _summaryTarget(newMcVersion, newLoader, newLoaderTag),
      recovered: recovered,
      lost: lost,
      dryRun: true,
    );
    return exitOk;
  }

  var yamlText = File(io.modsYamlPath).readAsStringSync();

  if (newMcVersion != null) {
    yamlText = updateTopLevelScalar(
      yamlText,
      path: const ['mc-version'],
      newValue: newMcVersion,
    );
  } else {
    final tag = newLoaderTag ?? 'stable';
    final loaderValue = tag == 'stable'
        ? newLoader!.name
        : '${newLoader!.name}:$tag';
    yamlText = updateTopLevelScalar(
      yamlText,
      path: const ['loader', 'mods'],
      newValue: loaderValue,
    );
  }

  for (final (section, slug) in lost) {
    yamlText = setEntryVersion(
      yamlText,
      section: section,
      slug: slug,
      newVersion: notFoundMarker,
    );
  }

  if (result.newLock != null) {
    final newLock = result.newLock!;
    for (final (section, slug) in recovered) {
      final locked = newLock.sectionFor(section)[slug];
      final resolvedRaw = locked?.version;
      if (resolvedRaw == null) continue;
      final String bareResolved;
      try {
        bareResolved = bareVersionForPin(resolvedRaw);
      } on FormatException {
        console.info(
          "skipped '$slug' recovery rewrite — resolved version "
          "'$resolvedRaw' is not semver-shaped.",
        );
        continue;
      }
      yamlText = setEntryVersion(
        yamlText,
        section: section,
        slug: slug,
        newVersion: '^$bareResolved',
      );
    }
  }

  // Auto-disable: write the marker for every conflict-root the catch
  // identified. Goes after the recovered-rewrite loop so a slug that's
  // both `recovered` (had a marker, versions exist on the new target)
  // and `disabledByConflict` (the second resolve still failed for it)
  // ends up with the disabled-by-conflict marker, not a stale caret.
  for (final (section, slug) in disabledByConflict) {
    yamlText = setEntryVersion(
      yamlText,
      section: section,
      slug: slug,
      newVersion: disabledByConflictMarker,
    );
  }

  io.writeModsYaml(yamlText);

  if (result.newLock != null && available.isNotEmpty) {
    final modrinthByEntry = <(Section, String), ModEntry>{
      for (final (section, slug) in available)
        (section, slug): manifest.sectionEntries(section)[slug]!,
    };
    rewriteCaretConstraints(
      io: io,
      console: console,
      modrinthByEntry: modrinthByEntry,
      targets: {for (final (_, slug) in available) slug},
      relaxSet: relaxSet,
      majorVersions: true,
      tighten: false,
      newLock: result.newLock!,
    );
  }

  _printSummary(
    console: console,
    target: _summaryTarget(newMcVersion, newLoader, newLoaderTag),
    recovered: recovered,
    lost: lost,
    dryRun: false,
  );

  return exitOk;
}

ModsYaml _applyTarget(
  ModsYaml manifest, {
  required String? newMcVersion,
  required Loader? newLoader,
  required String? newLoaderTag,
}) {
  if (newMcVersion != null) {
    return manifest.copyWith(mcVersion: newMcVersion);
  }
  return manifest.copyWith(
    loader: LoaderConfig(
      mods: newLoader!,
      modsVersion: newLoaderTag ?? 'stable',
      shaders: manifest.loader.shaders,
      plugins: manifest.loader.plugins,
    ),
  );
}

/// Returns [manifest] with every entry in [disabled] rewritten to carry
/// `constraintRaw: disabledByConflictMarker`. Used by the auto-disable
/// retry: applying the marker in-memory makes the resolver-skip filter
/// pull these entries out of the second resolution pass.
ModsYaml _applyDisableMarkers(
  ModsYaml manifest,
  Set<(Section, String)> disabled,
) {
  if (disabled.isEmpty) return manifest;
  Map<String, ModEntry> mark(Section section, Map<String, ModEntry> m) => {
    for (final e in m.entries)
      e.key: disabled.contains((section, e.key))
          ? e.value.copyWith(constraintRaw: disabledByConflictMarker)
          : e.value,
  };
  return manifest.copyWith(
    mods: mark(Section.mods, manifest.mods),
    resourcePacks: mark(Section.resourcePacks, manifest.resourcePacks),
    dataPacks: mark(Section.dataPacks, manifest.dataPacks),
    shaders: mark(Section.shaders, manifest.shaders),
  );
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

String _summaryTarget(
  String? newMcVersion,
  Loader? newLoader,
  String? newLoaderTag,
) {
  if (newMcVersion != null) return 'mc-version $newMcVersion';
  final tag = newLoaderTag ?? 'stable';
  return 'loader ${newLoader!.name}:$tag';
}

void _printSummary({
  required dynamic console,
  required String target,
  required Set<(Section, String)> recovered,
  required Set<(Section, String)> lost,
  required bool dryRun,
}) {
  final prefix = dryRun ? '[dry-run] ' : '';
  console.info('${prefix}Migrated to $target.');
  if (recovered.isNotEmpty) {
    console.info('${prefix}Recovered:');
    for (final (_, slug) in recovered) {
      console.info('  - $slug');
    }
  }
  if (lost.isNotEmpty) {
    console.info('${prefix}Marked not-found:');
    for (final (_, slug) in lost) {
      console.info('  - $slug');
    }
  }
}
