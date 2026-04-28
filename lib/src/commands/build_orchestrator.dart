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
import '../service/plugin_server_source.dart';
import '../service/resolve_and_sync.dart';
import '../service/server_installer.dart';
import '../service/solve_report.dart';
import '../service/vanilla_server_source.dart';
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
    this.javaPath,
    this.allowManagedJava = true,
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

  /// Forwarded to [ServerInstaller] when running the Forge/NeoForge
  /// `--installServer` step. Same semantics as the launch flags.
  final String? javaPath;
  final bool allowManagedJava;
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
    final modLoaderResolver = container.read(modLoaderVersionResolverProvider);
    final result = await resolveAndSync(
      io: manifestIo,
      console: console,
      api: api,
      cache: cache,
      downloader: downloader,
      modLoaderResolver: modLoaderResolver,
      pluginLoaderResolver: container.read(pluginLoaderVersionResolverProvider),
      offline: options.offline,
    );
    if (result.exitCode != exitOk) return result.exitCode;
    SolveReporter(
      console,
    ).printSummary(changeCount: result.changeCount, outdated: result.outdated);
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
      console: console,
    );
    final envDir = Directory(p.join(outputDir.path, envDirName(env)));
    console.message('Wrote ${result.count} file(s) to ${envDir.path}.');
    if (result.pruned > 0) {
      console.message('Pruned ${result.pruned} obsolete file(s).');
    }
  }

  if (envs.contains(BuildEnv.server)) {
    final serverDir = Directory(
      p.join(outputDir.path, envDirName(BuildEnv.server)),
    );
    final pluginLoader = lock.loader.plugins;
    if (pluginLoader != null) {
      final pluginLoaderVersion = lock.loader.pluginLoaderVersion;
      if (pluginLoaderVersion == null) {
        throw UserError(
          'mods.lock has loader.plugins=${pluginLoader.name} but no concrete '
          'plugin loader version.',
        );
      }
      await _installPluginServerBinary(
        lock: lock,
        pluginLoader: pluginLoader,
        pluginLoaderVersion: pluginLoaderVersion,
        cache: cache,
        serverDir: serverDir,
        installer: container.read(serverInstallerProvider),
        source: PluginServerSource.forLoader(
          pluginLoader,
          paperApi: container.read(paperApiClientProvider),
          spongeApi: container.read(spongeApiClientProvider),
          buildTools: container.read(buildToolsRunnerProvider),
          cache: cache,
          downloader: container.read(downloaderProvider),
        ),
        offline: options.offline,
        skipDownload: options.skipDownload,
        javaPath: options.javaPath,
        allowManagedJava: options.allowManagedJava,
        console: console,
      );
    } else if (lock.loader.hasModRuntime) {
      await _installModdedServerBinary(
        lock: lock,
        cache: cache,
        serverDir: serverDir,
        fetcher: container.read(loaderBinaryFetcherProvider),
        installer: container.read(serverInstallerProvider),
        skipDownload: options.skipDownload,
        offline: options.offline,
        javaPath: options.javaPath,
        allowManagedJava: options.allowManagedJava,
        verbose: options.verbose,
        console: console,
      );
    } else {
      await _installVanillaServerBinary(
        lock: lock,
        serverDir: serverDir,
        installer: container.read(serverInstallerProvider),
        source: container.read(vanillaServerSourceProvider),
        offline: options.offline,
        skipDownload: options.skipDownload,
        javaPath: options.javaPath,
        allowManagedJava: options.allowManagedJava,
        console: console,
      );
    }
  }

  return exitOk;
}

Future<void> _installPluginServerBinary({
  required ModsLock lock,
  required PluginLoader pluginLoader,
  required String pluginLoaderVersion,
  required GitrinthCache cache,
  required Directory serverDir,
  required ServerInstaller installer,
  required PluginServerSource source,
  required bool offline,
  required bool skipDownload,
  required String? javaPath,
  required bool allowManagedJava,
  required Console console,
}) async {
  final mcVersion = lock.mcVersion;

  final jar = await source.fetchServerJar(
    mcVersion: mcVersion,
    pluginLoaderVersion: pluginLoaderVersion,
    offline: offline || skipDownload,
    console: console,
    javaPath: javaPath,
    allowManagedJava: allowManagedJava,
  );

  await installer.installServer(
    loader: lock.loader.mods,
    mcVersion: mcVersion,
    modLoaderVersion: lock.loader.modLoaderVersion,
    outputDir: serverDir,
    installerOrServerJar: jar,
    offline: offline,
    javaPath: javaPath,
    allowManagedJava: allowManagedJava,
    pluginServerJar: jar,
    pluginInstallMarker: '${source.installMarker}-$pluginLoaderVersion',
  );
  // The plugin-loader path runs even when loader.mods is vanilla
  // (e.g. paper, or sponge resolved to spongevanilla), so the server
  // installer must accept a null modLoaderVersion. See server_installer.dart.
  console.message(
    'Installed ${pluginLoader.name} $pluginLoaderVersion server binary into '
    '${serverDir.path}.',
  );
}

Future<void> _installVanillaServerBinary({
  required ModsLock lock,
  required Directory serverDir,
  required ServerInstaller installer,
  required VanillaServerSource source,
  required bool offline,
  required bool skipDownload,
  required String? javaPath,
  required bool allowManagedJava,
  required Console console,
}) async {
  final mcVersion = lock.mcVersion;
  final jar = await source.fetchServerJar(
    mcVersion: mcVersion,
    offline: offline || skipDownload,
  );
  await installer.installServer(
    loader: lock.loader.mods,
    mcVersion: mcVersion,
    modLoaderVersion: null,
    outputDir: serverDir,
    installerOrServerJar: jar,
    offline: offline,
    javaPath: javaPath,
    allowManagedJava: allowManagedJava,
    pluginServerJar: jar,
    pluginInstallMarker: VanillaServerSource.installMarker,
  );
  console.message(
    'Installed vanilla Minecraft $mcVersion server binary into '
    '${serverDir.path}.',
  );
}

Future<void> _installModdedServerBinary({
  required ModsLock lock,
  required GitrinthCache cache,
  required Directory serverDir,
  required LoaderBinaryFetcher fetcher,
  required ServerInstaller installer,
  required bool skipDownload,
  required bool offline,
  required String? javaPath,
  required bool allowManagedJava,
  required bool verbose,
  required Console console,
}) async {
  final loader = lock.loader.mods;
  final mcVersion = lock.mcVersion;
  // Caller already gated on `hasModRuntime`, so the lock has a
  // resolved concrete loader version. If somehow null (e.g. vanilla
  // path), there's nothing to install — bail.
  final modLoaderVersion = lock.loader.modLoaderVersion;
  if (modLoaderVersion == null) {
    return;
  }

  if (skipDownload) {
    final cachedPath = _expectedCachedInstallerPath(
      cache: cache,
      loader: loader,
      mcVersion: mcVersion,
      modLoaderVersion: modLoaderVersion,
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
    modLoaderVersion: modLoaderVersion,
  );

  await installer.installServer(
    loader: loader,
    mcVersion: mcVersion,
    modLoaderVersion: modLoaderVersion,
    outputDir: serverDir,
    installerOrServerJar: installerJar,
    offline: offline,
    javaPath: javaPath,
    allowManagedJava: allowManagedJava,
    verbose: verbose,
  );
  console.message(
    'Installed ${loader.name} $modLoaderVersion server binary into '
    '${serverDir.path}.',
  );
}

String _expectedCachedInstallerPath({
  required GitrinthCache cache,
  required ModLoader loader,
  required String mcVersion,
  required String modLoaderVersion,
}) {
  switch (loader) {
    case ModLoader.vanilla:
      throw StateError(
        '_expectedCachedInstallerPath called for vanilla; gate on '
        'LoaderConfig.hasModRuntime.',
      );
    case ModLoader.forge:
      return cache.loaderArtifactPath(
        loader: loader,
        mcVersion: mcVersion,
        modLoaderVersion: modLoaderVersion,
        filename: 'forge-$mcVersion-$modLoaderVersion-installer.jar',
      );
    case ModLoader.neoforge:
      final filename = mcVersion == '1.20.1'
          ? 'forge-$mcVersion-$modLoaderVersion-installer.jar'
          : 'neoforge-$modLoaderVersion-installer.jar';
      return cache.loaderArtifactPath(
        loader: loader,
        mcVersion: mcVersion,
        modLoaderVersion: modLoaderVersion,
        filename: filename,
      );
    case ModLoader.fabric:
      return cache.loaderArtifactPath(
        loader: loader,
        mcVersion: mcVersion,
        modLoaderVersion: modLoaderVersion,
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
      console.io('pruned $relPath');
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
        () =>
            Directory(p.join(envRoot.path, subdir))
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
    final preserveSkipped = entry.preserve && File(destPath).existsSync();
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
