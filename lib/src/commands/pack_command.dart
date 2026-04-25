import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/mrpack_index.dart';
import '../service/cache.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/solve_report.dart';
import 'pack_assembler.dart';

const String _permissionsArticle =
    'https://support.modrinth.com/en/articles/8797527-obtaining-modpack-permissions';

const String _serverInstallerHint =
    'Install the server pack with mrpack-install: '
    'https://github.com/nothub/mrpack-install';

class PackCommand extends GitrinthCommand {
  @override
  String get name => 'pack';

  @override
  String get description => 'Produce Modrinth .mrpack artifacts.';

  @override
  String get invocation => 'gitrinth pack [arguments]';

  PackCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        valueHelp: 'path',
        help:
            'Override the output path. Defaults to '
            './build/<slug>-<version>.mrpack.',
      )
      ..addFlag(
        'combined',
        negatable: false,
        help:
            'Produce a single .mrpack containing both client and server '
            'files.',
      )
      ..addFlag(
        'publishable',
        negatable: false,
        help: 'Refuse to pack if any mod uses a url: or path: source.',
      );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }

    final outputOpt = argResults!['output'] as String?;
    final combined = argResults!['combined'] as bool;
    final publishable = argResults!['publishable'] as bool;

    final io = ManifestIo();
    final api = read(modrinthApiProvider);
    final cache = read(cacheProvider);
    final downloader = read(downloaderProvider);
    final loaderResolver = read(loaderVersionResolverProvider);

    // Refresh the lock + cache so url/path artifact bytes are present
    // and the loader/mc-version are up to date — same entry point build
    // uses.
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
    SolveReporter(
      console,
    ).printSummary(changeCount: result.changeCount, outdated: result.outdated);

    final yaml = io.readModsYaml();
    final lock = result.newLock ?? io.readModsLock();
    if (lock == null) {
      throw const UserError(
        'mods.lock was not written; resolver produced no lockfile.',
      );
    }

    // The permissions warning fires on the union of all mod overrides
    // across every produced pack — collect them once up-front so it
    // doesn't double-fire when we emit two packs.
    final allOverridesForWarning = collectOverrides(
      lock: lock,
      cache: cache,
      projectDir: io.directory.path,
      target: PackTarget.combined,
    );

    final basePath = _resolveBasePath(yaml: yaml, outputOpt: outputOpt);

    if (combined) {
      _writePack(
        target: PackTarget.combined,
        outputPath: basePath,
        yaml: yaml,
        lock: lock,
        cache: cache,
        projectDir: io.directory.path,
        publishable: publishable,
      );
    } else {
      _writePack(
        target: PackTarget.client,
        outputPath: basePath,
        yaml: yaml,
        lock: lock,
        cache: cache,
        projectDir: io.directory.path,
        publishable: publishable,
      );
      _writePack(
        target: PackTarget.server,
        outputPath: _serverPathFor(basePath),
        yaml: yaml,
        lock: lock,
        cache: cache,
        projectDir: io.directory.path,
        publishable: publishable,
      );
      console.info(_serverInstallerHint);
    }

    if (!publishable && allOverridesForWarning.hasModOverrides) {
      _printPermissionsWarning(allOverridesForWarning.entries);
    }

    return exitOk;
  }

  /// Resolves the base path for the client (or combined) pack from the
  /// optional `--output` value, defaulting to
  /// `./build/<slug>-<version>.mrpack`.
  String _resolveBasePath({
    required ModsYaml yaml,
    required String? outputOpt,
  }) {
    final raw =
        outputOpt ?? p.join('build', '${yaml.slug}-${yaml.version}.mrpack');
    return p.normalize(p.absolute(raw));
  }

  /// Derives the server pack path from the client/combined base path by
  /// inserting `-server` before the extension.
  String _serverPathFor(String basePath) {
    final dir = p.dirname(basePath);
    final ext = p.extension(basePath);
    final stem = p.basenameWithoutExtension(basePath);
    return p.join(dir, '$stem-server$ext');
  }

  void _writePack({
    required PackTarget target,
    required String outputPath,
    required ModsYaml yaml,
    required ModsLock lock,
    required GitrinthCache cache,
    required String projectDir,
    required bool publishable,
  }) {
    final index = buildIndex(
      yaml: yaml,
      lock: lock,
      target: target,
      publishable: publishable,
    );
    final overrides = collectOverrides(
      lock: lock,
      cache: cache,
      projectDir: projectDir,
      target: target,
    );

    for (final o in overrides.entries) {
      console.info(
        '~ ${o.slug}: ${o.sourceKind} source — packed into ${o.zipPath}',
      );
    }

    final outputFile = File(outputPath);
    final parent = outputFile.parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);

    _writeArchive(outputFile, index: index, overrides: overrides.entries);

    final modCount = index.files
        .where((f) => f.path.startsWith('mods/'))
        .length;
    final overrideCount = overrides.entries.length;
    final label = switch (target) {
      PackTarget.client => 'client',
      PackTarget.server => 'server',
      PackTarget.combined => 'combined',
    };
    console.info(
      'Wrote $label pack: $outputPath '
      '(${index.files.length} files, $modCount mods, '
      '$overrideCount override${overrideCount == 1 ? '' : 's'}).',
    );
  }

  void _writeArchive(
    File outputFile, {
    required MrpackIndex index,
    required List<OverridePlan> overrides,
  }) {
    final archive = Archive();

    final indexJson = const JsonEncoder.withIndent('  ').convert(index.toMap());
    final indexBytes = utf8.encode(indexJson);
    archive.addFile(
      ArchiveFile('modrinth.index.json', indexBytes.length, indexBytes),
    );

    for (final o in overrides) {
      final src = File(o.sourcePath);
      if (!src.existsSync()) {
        throw UserError(
          'override source for "${o.slug}" missing on disk: ${o.sourcePath}. '
          'Re-run `gitrinth get` to repopulate the cache.',
        );
      }
      final bytes = src.readAsBytesSync();
      archive.addFile(ArchiveFile(o.zipPath, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive);
    outputFile.writeAsBytesSync(encoded);
  }

  void _printPermissionsWarning(List<OverridePlan> overrides) {
    // Mod overrides may live under any of the three loose-files roots
    // (overrides/, client-overrides/, server-overrides/) depending on
    // env, so filter by section rather than by zipPath prefix.
    final modOverrides =
        overrides.where((o) => o.section == Section.mods).toList()
          ..sort((a, b) => a.slug.compareTo(b.slug));
    final buf = StringBuffer()
      ..writeln(
        'Note: this pack bundles non-Modrinth mod artifacts. You may need',
      )
      ..writeln('permission from each mod author to distribute them:');
    for (final o in modOverrides) {
      buf.writeln('  - ${o.slug} (${o.sourceKind})');
    }
    buf.write('See: $_permissionsArticle');
    console.info(buf.toString());
  }
}
