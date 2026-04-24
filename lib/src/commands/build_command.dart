import 'dart:io';

import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/cache.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/solve_report.dart';
import 'build_assembler.dart';

class BuildCommand extends GitrinthCommand {
  @override
  String get name => 'build';

  @override
  String get description =>
      'Assemble client and/or server distributions into build/.';

  @override
  String get invocation => 'gitrinth build [arguments]';

  BuildCommand() {
    argParser
      ..addOption(
        'env',
        allowed: ['client', 'server', 'both'],
        valueHelp: 'client|server|both',
        help: 'Build only the named environment.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        valueHelp: 'path',
        help: 'Override the output directory. Defaults to ./build.',
      )
      ..addFlag(
        'clean',
        negatable: false,
        help: 'Remove the output directory before building.',
      )
      ..addFlag(
        'skip-download',
        negatable: false,
        help: 'Fail rather than fetch missing artifacts.',
      );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError(
        'Unexpected arguments: ${argResults!.rest.join(' ')}',
      );
    }

    final envFlag = argResults!['env'] as String?;
    final outputOpt = argResults!['output'] as String?;
    final clean = argResults!['clean'] as bool;
    final skipDownload = argResults!['skip-download'] as bool;

    final envs = targetEnvironments(envFlag);

    final io = ManifestIo();
    final cache = read(cacheProvider);

    ModsLock? lock;
    if (skipDownload) {
      lock = io.readModsLock();
      if (lock == null) {
        throw const UserError(
          'mods.lock not found; run `gitrinth get` first or drop --skip-download.',
        );
      }
    } else {
      final api = read(modrinthApiProvider);
      final downloader = read(downloaderProvider);
      final loaderResolver = read(loaderVersionResolverProvider);
      final result = await resolveAndSync(
        io: io,
        console: console,
        api: api,
        cache: cache,
        downloader: downloader,
        loaderResolver: loaderResolver,
        verbose: gitrinthRunner.verbose,
      );
      if (result.exitCode != exitOk) return result.exitCode;
      SolveReporter(console).printSummary(
        changeCount: result.changeCount,
        outdated: result.outdated,
      );
      lock = result.newLock ?? io.readModsLock();
      if (lock == null) {
        throw const UserError(
          'mods.lock was not written; resolver produced no lockfile.',
        );
      }
    }

    final outputDir = Directory(
      p.normalize(p.absolute(outputOpt ?? 'build')),
    );
    if (clean && outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true);
    }

    final projectDir = io.directory.path;
    for (final env in envs) {
      final count = _assembleEnv(
        env: env,
        lock: lock,
        cache: cache,
        outputDir: outputDir,
        projectDir: projectDir,
        skipDownload: skipDownload,
      );
      final envDir = Directory(p.join(outputDir.path, envDirName(env)));
      console.info('Wrote $count file(s) to ${envDir.path}.');
    }

    if (envs.contains(BuildEnv.server)) {
      console.info(
        'Note: server binary is not bundled; download the matching '
        '${lock.loader.mods.name} installer for Minecraft ${lock.mcVersion} '
        'manually.',
      );
    }

    return exitOk;
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
}
