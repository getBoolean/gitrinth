import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import '../app/providers.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/state/build_state.dart';
import '../service/cache.dart';
import '../service/console.dart';
import '../service/loader_binary_fetcher.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/server_installer.dart';
import '../service/solve_report.dart';
import '../version.dart';
import 'build_assembler.dart';
import 'build_pruner.dart';

/// Inputs for [runBuild]. Mirrors `gitrinth build`'s flags so [LaunchCommand]
/// can drive the same pipeline programmatically.
class BuildOptions {
  const BuildOptions({
    this.envFlag,
    this.outputPath,
    this.clean = false,
    this.skipDownload = false,
    this.noPrune = false,
    this.offline = false,
    this.verbose = false,
  });

  final String? envFlag;
  final String? outputPath;
  final bool clean;
  final bool skipDownload;

  /// When true, the obsolete-file deletion pass is skipped — the new
  /// state ledger is still written, but files left over from a prior
  /// build remain on disk. Debug escape hatch; default is false (prune).
  final bool noPrune;

  final bool offline;
  final bool verbose;
}

/// Resolves dependencies, populates `mods.lock`, and writes a runnable build
/// tree under [BuildOptions.outputPath] (defaults to `./build`). For `server`
/// environments, also fetches and installs the matching loader server binary
/// (Forge/NeoForge installer or fabric-server-launch JAR).
Future<int> runBuild({
  required BuildOptions options,
  required ProviderContainer container,
  required Console console,
  ManifestIo? io,
}) async {
  final manifestIo = io ?? ManifestIo();
  final cache = container.read(cacheProvider);

  final envs = targetEnvironments(options.envFlag);

  ModsLock? lock;
  if (options.skipDownload) {
    lock = manifestIo.readModsLock();
    if (lock == null) {
      throw const UserError(
        'mods.lock not found; run `gitrinth get` first or drop --skip-download.',
      );
    }
  } else {
    final api = container.read(modrinthApiProvider);
    final downloader = container.read(downloaderProvider);
    final loaderResolver = container.read(loaderVersionResolverProvider);
    final result = await resolveAndSync(
      io: manifestIo,
      console: console,
      api: api,
      cache: cache,
      downloader: downloader,
      loaderResolver: loaderResolver,
      verbose: options.verbose,
      offline: options.offline,
    );
    if (result.exitCode != exitOk) return result.exitCode;
    SolveReporter(console).printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    lock = result.newLock ?? manifestIo.readModsLock();
    if (lock == null) {
      throw const UserError(
        'mods.lock was not written; resolver produced no lockfile.',
      );
    }
  }

  final outputDir = Directory(
    p.normalize(
      p.absolute(
        options.outputPath ?? p.join(manifestIo.directory.path, 'build'),
      ),
    ),
  );
  if (options.clean && outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }

  final projectDir = manifestIo.directory.path;
  for (final env in envs) {
    final result = _assembleEnv(
      env: env,
      lock: lock,
      cache: cache,
      outputDir: outputDir,
      projectDir: projectDir,
      skipDownload: options.skipDownload,
      noPrune: options.noPrune,
      verbose: options.verbose,
      console: console,
    );
    final envDir = Directory(p.join(outputDir.path, envDirName(env)));
    console.info('Wrote ${result.count} file(s) to ${envDir.path}.');
    if (result.pruned > 0) {
      console.info('Pruned ${result.pruned} obsolete file(s).');
    }
  }

  if (envs.contains(BuildEnv.server)) {
    final serverDir = Directory(
      p.join(outputDir.path, envDirName(BuildEnv.server)),
    );
    await _installServerBinary(
      lock: lock,
      cache: cache,
      serverDir: serverDir,
      fetcher: container.read(loaderBinaryFetcherProvider),
      installer: container.read(serverInstallerProvider),
      skipDownload: options.skipDownload,
      offline: options.offline,
      console: console,
    );
  }

  return exitOk;
}

Future<void> _installServerBinary({
  required ModsLock lock,
  required GitrinthCache cache,
  required Directory serverDir,
  required LoaderBinaryFetcher fetcher,
  required ServerInstaller installer,
  required bool skipDownload,
  required bool offline,
  required Console console,
}) async {
  final loader = lock.loader.mods;
  final mcVersion = lock.mcVersion;
  final loaderVersion = lock.loader.modsVersion;

  if (skipDownload) {
    final cachedPath = _expectedCachedInstallerPath(
      cache: cache,
      loader: loader,
      mcVersion: mcVersion,
      loaderVersion: loaderVersion,
    );
    if (!File(cachedPath).existsSync()) {
      throw UserError(
        'missing cached ${loader.name} server binary at $cachedPath. '
        'Re-run without --skip-download to fetch it.',
      );
    }
  }

  final installerJar = await fetcher.fetchServerArtifact(
    loader: loader,
    mcVersion: mcVersion,
    loaderVersion: loaderVersion,
  );

  await installer.installServer(
    loader: loader,
    mcVersion: mcVersion,
    loaderVersion: loaderVersion,
    outputDir: serverDir,
    installerOrServerJar: installerJar,
    offline: offline,
  );
  console.info(
    'Installed ${loader.name} $loaderVersion server binary into '
    '${serverDir.path}.',
  );
}

String _expectedCachedInstallerPath({
  required GitrinthCache cache,
  required Loader loader,
  required String mcVersion,
  required String loaderVersion,
}) {
  switch (loader) {
    case Loader.forge:
      return cache.loaderArtifactPath(
        loader: loader,
        mcVersion: mcVersion,
        loaderVersion: loaderVersion,
        filename: 'forge-$mcVersion-$loaderVersion-installer.jar',
      );
    case Loader.neoforge:
      final filename = mcVersion == '1.20.1'
          ? 'forge-$mcVersion-$loaderVersion-installer.jar'
          : 'neoforge-$loaderVersion-installer.jar';
      return cache.loaderArtifactPath(
        loader: loader,
        mcVersion: mcVersion,
        loaderVersion: loaderVersion,
        filename: filename,
      );
    case Loader.fabric:
      return cache.loaderArtifactPath(
        loader: loader,
        mcVersion: mcVersion,
        loaderVersion: loaderVersion,
        filename: 'fabric-server-launch.jar',
      );
  }
}

/// Result of [_assembleEnv]: count of newly-written/copied files plus
/// the count of obsolete files pruned from the prior ledger.
class _AssembleResult {
  final int count;
  final int pruned;
  const _AssembleResult({required this.count, required this.pruned});
}

_AssembleResult _assembleEnv({
  required BuildEnv env,
  required ModsLock lock,
  required GitrinthCache cache,
  required Directory outputDir,
  required String projectDir,
  required bool skipDownload,
  required bool noPrune,
  required bool verbose,
  required Console console,
}) {
  final envRoot = Directory(p.join(outputDir.path, envDirName(env)));
  envRoot.createSync(recursive: true);

  // Read the prior ledger once up front so the prune pass and the
  // unmanaged-collision detector both see the same snapshot.
  final priorLedger = readLedgerOrEmpty(ledgerPathFor(envRoot), env);

  // Pre-compute the set of destination paths the assemble step is
  // about to write. Keys are posix-separator relative paths under
  // envRoot. This lets the prune pass run before any new file is
  // written — obsolete files from the prior run are gone before
  // the new ones land, which keeps disk-usage spikes small.
  final desiredKeys = <String>{};
  for (final section in Section.values) {
    for (final entry in lock.sectionFor(section).values) {
      final subdir = buildSubdirFor(section, env, entry);
      if (subdir == null) continue;
      desiredKeys.add(p.posix.join(subdir, destFilenameFor(entry)));
    }
  }
  for (final entry in lock.files.values) {
    final include = env == BuildEnv.client
        ? entry.client.includes
        : entry.server.includes;
    if (!include) continue;
    desiredKeys.add(entry.destination);
  }

  // Prune. Files in priorLedger but not in desiredKeys are obsolete;
  // delete them and remove any newly-empty parent directories. Loose
  // user-dropped files are NEVER touched here because they are not
  // in the prior ledger by construction. Loader-installer outputs
  // (libraries/, server.jar, etc.) are similarly invisible to the
  // ledger and survive — see [build_pruner.isProtectedPath] for the
  // belt-and-suspenders allow-list.
  var pruned = 0;
  if (!noPrune) {
    for (final relPath in obsoletePaths(
      prior: priorLedger,
      desired: desiredKeys,
    )) {
      pruneFile(envRoot: envRoot, relPath: relPath);
      pruned++;
      if (verbose) console.detail('pruned $relPath');
    }
  }

  // Lazy-create one Directory per unique relative subdir under envRoot.
  // Data/resource packs split between required_*/ and optional_*/, so
  // the older "one dir per section" cache no longer fits.
  final dirCache = <String, Directory>{};
  final usedDestPaths = <String>{};
  // Ledger entries accumulated as files are written (or preserve-skipped).
  // Keyed by destination path relative to `envRoot`, normalized to posix
  // separators so the ledger is identical across platforms.
  final ledgerFiles = <String, LedgerSource>{};
  var count = 0;

  for (final section in Section.values) {
    final sectionMap = lock.sectionFor(section);
    if (sectionMap.isEmpty) continue;

    for (final entry in sectionMap.values) {
      final subdir = buildSubdirFor(section, env, entry);
      if (subdir == null) continue;

      final sourcePath = resolveSourcePath(
        cache,
        entry,
        projectDir: projectDir,
      );
      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) {
        if (skipDownload) {
          throw UserError(
            'missing cached artifact for "${entry.slug}": $sourcePath. '
            'Re-run without --skip-download to fetch it.',
          );
        }
        throw UserError(
          'expected artifact for "${entry.slug}" at $sourcePath but it is '
          'missing; the cache may have been emptied mid-build.',
        );
      }

      final destDir = dirCache.putIfAbsent(
        subdir,
        () => Directory(p.join(envRoot.path, subdir))
          ..createSync(recursive: true),
      );

      final destName = destFilenameFor(entry);
      final destPath = p.join(destDir.path, destName);
      if (!usedDestPaths.add(destPath)) {
        throw ValidationError(
          'two entries resolve to the same output file: $destPath '
          '(last offender: ${entry.slug})',
        );
      }

      // Unmanaged-collision warning: if a file already exists at the
      // dest and was NOT in the prior ledger, it's likely a user-
      // dropped file with the same filename as a managed mod. We
      // overwrite (matching packwiz-installer's silent-overwrite
      // default) but surface a warning so the user notices.
      final relKey = p.posix.join(subdir, destName);
      if (File(destPath).existsSync() &&
          !priorLedger.files.containsKey(relKey)) {
        console.warn(
          'overwriting unmanaged file at $relKey '
          '(was not in prior ledger)',
        );
      }
      sourceFile.copySync(destPath);
      ledgerFiles[relKey] = LedgerModSource(
        section: section.name,
        slug: entry.slug,
        sha512: entry.file?.sha512,
      );
      count++;
    }
  }

  // Loose files declared in `files:` section. Their destination is the
  // full relative path under the env root (no Section subdir routing),
  // and per-side state filters which env they apply to.
  for (final entry in lock.files.values) {
    final include = env == BuildEnv.client
        ? entry.client.includes
        : entry.server.includes;
    if (!include) continue;

    final destPath = p.normalize(p.join(envRoot.path, entry.destination));
    if (!usedDestPaths.add(destPath)) {
      throw ValidationError(
        'files: entry "${entry.destination}" collides with another '
        'output file in ${envRoot.path}.',
      );
    }
    // First-install-only: when `preserve: true`, do not overwrite an
    // existing file. User edits to configs/scripts survive rebuilds.
    // Removing the entry from `files:` still prunes it via the prune
    // pass — preserve is not sticky.
    final preserveSkipped =
        entry.preserve && File(destPath).existsSync();
    if (!preserveSkipped) {
      // Unmanaged-collision warning, same reasoning as the mod loop:
      // overwrite to match packwiz-installer behavior, but surface a
      // warning so the user notices when their loose file collides
      // with a managed `files:` declaration.
      if (File(destPath).existsSync() &&
          !priorLedger.files.containsKey(entry.destination)) {
        console.warn(
          'overwriting unmanaged file at ${entry.destination} '
          '(was not in prior ledger)',
        );
      }
      final sourceFile = File(
        p.isAbsolute(entry.sourcePath)
            ? entry.sourcePath
            : p.normalize(p.join(projectDir, entry.sourcePath)),
      );
      if (!sourceFile.existsSync()) {
        throw UserError(
          'files: entry "${entry.destination}" points to a missing '
          'source: ${sourceFile.path}',
        );
      }
      Directory(p.dirname(destPath)).createSync(recursive: true);
      sourceFile.copySync(destPath);
      count++;
    }
    // Even when preserve skips the copy, the entry stays in the ledger
    // so the next run can identify it as managed (and so removing it
    // from `files:` later prunes the file).
    ledgerFiles[entry.destination] = LedgerFileSource(
      key: entry.destination,
      preserve: entry.preserve,
      sourcePath: entry.sourcePath,
      sha512: entry.sha512,
    );
  }

  writeLedger(
    ledgerPathFor(envRoot),
    BuildLedger(
      gitrinthVersion: packageVersion,
      env: ledgerEnvFor(env),
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      files: ledgerFiles,
    ),
  );

  return _AssembleResult(count: count, pruned: pruned);
}
