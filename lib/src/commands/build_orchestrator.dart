import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import '../app/providers.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/cache.dart';
import '../service/console.dart';
import '../service/loader_binary_fetcher.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/server_installer.dart';
import '../service/solve_report.dart';
import 'build_assembler.dart';

/// Inputs for [runBuild]. Mirrors `gitrinth build`'s flags so [LaunchCommand]
/// can drive the same pipeline programmatically.
class BuildOptions {
  const BuildOptions({
    this.envFlag,
    this.outputPath,
    this.clean = false,
    this.skipDownload = false,
    this.offline = false,
    this.verbose = false,
  });

  final String? envFlag;
  final String? outputPath;
  final bool clean;
  final bool skipDownload;
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
    final count = _assembleEnv(
      env: env,
      lock: lock,
      cache: cache,
      outputDir: outputDir,
      projectDir: projectDir,
      skipDownload: options.skipDownload,
    );
    final envDir = Directory(p.join(outputDir.path, envDirName(env)));
    console.info('Wrote $count file(s) to ${envDir.path}.');
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

int _assembleEnv({
  required BuildEnv env,
  required ModsLock lock,
  required GitrinthCache cache,
  required Directory outputDir,
  required String projectDir,
  required bool skipDownload,
}) {
  final envRoot = Directory(p.join(outputDir.path, envDirName(env)));
  envRoot.createSync(recursive: true);

  final usedDestPaths = <String>{};
  var count = 0;

  for (final section in Section.values) {
    final sectionMap = lock.sectionFor(section);
    if (sectionMap.isEmpty) continue;
    final subdir = outputSubdirFor(section);
    Directory? sectionDir;

    for (final entry in sectionMap.values) {
      if (!shouldIncludeEntry(section, entry, env)) continue;

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

      sectionDir ??= Directory(p.join(envRoot.path, subdir))
        ..createSync(recursive: true);

      final destName = destFilenameFor(entry);
      final destPath = p.join(sectionDir.path, destName);
      if (!usedDestPaths.add(destPath)) {
        throw ValidationError(
          'two entries resolve to the same output file: $destPath '
          '(last offender: ${entry.slug})',
        );
      }

      sourceFile.copySync(destPath);
      count++;
    }
  }

  return count;
}
