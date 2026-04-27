import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/loader_ref.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../service/conflict_disable.dart';
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
  String get description => "Bump `mc-version` and re-resolve.";

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

(ModLoader, String?) _parseLoaderArg(String raw) {
  final (loader, tag) = parseLoaderRef(
    raw,
    (msg) => throw UsageError('migrate loader: $msg'),
  );
  // Default tag to `stable` when the user didn't supply one (vanilla
  // has no tag). Matches the yaml parser.
  return (loader, loader == ModLoader.vanilla ? null : (tag ?? 'stable'));
}

Future<int> _runMigrate({
  required String? newMcVersion,
  required ModLoader? newLoader,
  required String? newLoaderTag,
  required bool dryRun,
  required bool offline,
  required GitrinthCommand command,
}) async {
  final console = command.console;
  final io = ManifestIo();
  final manifest = io.readModsYaml();

  if (newLoader == ModLoader.vanilla && manifest.mods.isNotEmpty) {
    throw UserError(
      'migrate loader: cannot switch to `vanilla` while the `mods:` '
      'section has ${manifest.mods.length} '
      "${manifest.mods.length == 1 ? 'entry' : 'entries'}. Remove "
      'them or migrate to a real mod loader (forge / fabric / neoforge).',
    );
  }

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

  if (targetLoader == ModLoader.vanilla) {
    // No mod runtime — `mods:` is empty (checked above), so there is
    // nothing to re-resolve under the new loader.
  } else if (offline) {
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
    console.warn('migrate --offline: skipping availability check.');
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

  final outcome = await resolveWithConflictAutoDisable(
    manifest: manifest,
    resolutionManifest: resolutionManifest,
    targets: targets,
    relaxSet: relaxSet,
    console: console,
    resolve:
        ({
          required manifestForResolve,
          required freshSlugs,
          required relaxConstraints,
        }) => resolveAndSync(
          io: io,
          console: console,
          api: api,
          cache: cache,
          downloader: downloader,
          loaderResolver: loaderResolver,
          offline: offline,
          dryRun: dryRun,
          freshSlugs: freshSlugs,
          relaxConstraints: relaxConstraints,
          manifestOverride: manifestForResolve,
        ),
  );
  final result = outcome.result;
  final disabledByConflict = outcome.disabledByConflict;
  final newLock = result.newLock;

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
  } else if (newLoader == ModLoader.vanilla) {
    // Canonical vanilla form: `loader.mods` is removed (absence is the
    // sentinel). Preserves any `plugins:` / `shaders:` siblings.
    yamlText = setLoaderMods(yamlText, value: null);
  } else {
    final loader = newLoader;
    if (loader == null) {
      throw StateError(
        'migrate: caller contract requires either newMcVersion '
        'or newLoader to be set',
      );
    }
    final tag = newLoaderTag ?? 'stable';
    final loaderValue = tag == 'stable' ? loader.name : '${loader.name}:$tag';
    yamlText = setLoaderMods(yamlText, value: loaderValue);
  }

  for (final (section, slug) in lost) {
    yamlText = setEntryVersion(
      yamlText,
      section: section,
      slug: slug,
      newVersion: notFoundMarker,
    );
  }

  if (newLock != null) {
    for (final (section, slug) in recovered) {
      final locked = newLock.sectionFor(section)[slug];
      final resolvedRaw = locked?.version;
      if (resolvedRaw == null) continue;
      final String bareResolved;
      try {
        bareResolved = bareVersionForPin(resolvedRaw);
      } on FormatException {
        console.message(
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

  if (newLock != null && available.isNotEmpty) {
    final modrinthByEntry = <(Section, String), ModEntry>{};
    for (final (section, slug) in available) {
      final entry = manifest.sectionEntries(section)[slug];
      if (entry == null) {
        console.warn('migrate: dropping orphaned entry $slug from $section');
        continue;
      }
      modrinthByEntry[(section, slug)] = entry;
    }
    rewriteCaretConstraints(
      io: io,
      console: console,
      modrinthByEntry: modrinthByEntry,
      targets: {for (final (_, slug) in available) slug},
      relaxSet: relaxSet,
      majorVersions: true,
      tighten: false,
      newLock: newLock,
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
  required ModLoader? newLoader,
  required String? newLoaderTag,
}) {
  if (newMcVersion != null) {
    return manifest.copyWith(mcVersion: newMcVersion);
  }
  final loader = newLoader;
  if (loader == null) {
    // Caller contract: exactly one of newMcVersion / newLoader is set.
    return manifest;
  }
  // Re-resolve the plugin loader under the new mod loader: a sponge
  // pack switching from forge to fabric becomes spongevanilla. The
  // declared yaml value (`plugins: sponge`) doesn't change on disk;
  // only the in-memory resolution does.
  final resolvedPlugins = manifest.loader.plugins?.toDeclared().resolveWith(
    loader,
  );

  return manifest.copyWith(
    loader: LoaderConfig(
      mods: loader,
      modsVersion: loader == ModLoader.vanilla
          ? null
          : (newLoaderTag ?? 'stable'),
      shaders: manifest.loader.shaders,
      plugins: resolvedPlugins,
    ),
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
  ModLoader? newLoader,
  String? newLoaderTag,
) {
  if (newMcVersion != null) return 'mc-version $newMcVersion';
  if (newLoader == ModLoader.vanilla) return 'loader vanilla';
  final loader = newLoader;
  if (loader == null) return 'loader (none)';
  final tag = newLoaderTag ?? 'stable';
  return 'loader ${loader.name}:$tag';
}

void _printSummary({
  required dynamic console,
  required String target,
  required Set<(Section, String)> recovered,
  required Set<(Section, String)> lost,
  required bool dryRun,
}) {
  final prefix = dryRun ? '[dry-run] ' : '';
  console.message('${prefix}Migrated to $target.');
  if (recovered.isNotEmpty) {
    console.message('${prefix}Recovered:');
    for (final (_, slug) in recovered) {
      console.message('  - $slug');
    }
  }
  if (lost.isNotEmpty) {
    console.message('${prefix}Marked not-found:');
    for (final (_, slug) in lost) {
      console.message('  - $slug');
    }
  }
}
