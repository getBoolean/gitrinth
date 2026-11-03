import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../app/loader_registry_provider.dart';
import '../app/env.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/mrpack_index.dart';
import '../service/cache.dart';
import '../service/pack_archive_writer.dart';
import '../service/modrinth/modrinth_url.dart';
import '../service/manifest_io.dart';
import '../service/resolve/solve_report.dart';
import 'pack_assembler.dart';
import 'curseforge_pack_assembler.dart';

const String _permissionsArticle =
    'https://support.modrinth.com/en/articles/8797527-obtaining-modpack-permissions';

const String _serverInstallerHint =
    'Install the server pack with mrpack-install: '
    'https://github.com/nothub/mrpack-install';

class PackCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'pack';

  @override
  String get description =>
      'Produce Modrinth .mrpack or CurseForge .zip artifacts.';

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
        help: 'Reject target-missing sources and allow_hash_mismatch entries.',
      );
    argParser.addFlag(
      'curseforge',
      negatable: false,
      help: 'Produce CurseForge .zip archives.',
    );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }

    final outputOpt = argResults!['output'] as String?;
    final combined = argResults!['combined'] as bool;
    final publishable = argResults!['publishable'] as bool;
    final offline = readOfflineFlag();

    final io = ManifestIo();
    final cache = read(cacheProvider);

    // Refresh the lock + cache so url/path artifact bytes are present
    // and the loader/mc-version are up to date — same entry point build
    // uses.
    final result = await runResolveAndSync(io: io, offline: offline);
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
      platform: argResults!['curseforge'] as bool
          ? SourceKind.curseforge
          : SourceKind.modrinth,
      modrinthHost: resolveModrinthBaseUrl(read(environmentProvider)),
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
      if (!(argResults!['curseforge'] as bool)) {
        console.message(_serverInstallerHint);
      }
    }

    if (!publishable &&
        allOverridesForWarning.entries.any((e) => e.section != null)) {
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
    final extension = argResults!['curseforge'] as bool ? 'zip' : 'mrpack';
    final raw =
        outputOpt ?? p.join('build', '${yaml.slug}-${yaml.version}.$extension');
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
    if (argResults!['curseforge'] as bool) {
      final manifest = buildCurseForgeManifest(
        registry: read(loaderRegistryProvider),
        yaml: yaml,
        lock: lock,
        target: target,
        publishable: publishable,
      );
      final overrides = curseForgeOverrides(
        lock: lock,
        cache: cache,
        projectDir: projectDir,
        target: target,
        modrinthHost: resolveModrinthBaseUrl(read(environmentProvider)),
      );
      writePackArchive(
        File(outputPath),
        manifestName: 'manifest.json',
        manifest: manifest,
        overrides: overrides.entries,
      );
      console.message('Wrote ${target.name} CurseForge pack: $outputPath');
      return;
    }
    final index = buildIndex(
      registry: read(loaderRegistryProvider),
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
      modrinthHost: resolveModrinthBaseUrl(read(environmentProvider)),
    );

    for (final o in overrides.entries) {
      console.message(
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
    console.message(
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
    final indexJson = const JsonEncoder.withIndent('  ').convert(index.toMap());
    final indexBytes = utf8.encode(indexJson);

    for (final o in overrides) {
      final src = File(o.sourcePath);
      if (!src.existsSync()) {
        throw UserError(
          'override source for "${o.slug}" missing on disk: ${o.sourcePath}. '
          'Re-run `gitrinth get` to repopulate the cache.',
        );
      }
    }

    writeArchive(
      outputFile,
      manifestName: 'modrinth.index.json',
      manifest: indexBytes,
      entries: overrides.map(
        (entry) => (path: entry.zipPath, source: File(entry.sourcePath)),
      ),
    );
  }

  void _printPermissionsWarning(List<OverridePlan> overrides) {
    final artifactOverrides = overrides.where((o) => o.section != null).toList()
      ..sort((a, b) => a.slug.compareTo(b.slug));
    final buf = StringBuffer()
      ..writeln('Note: this pack bundles loose artifacts. You may need')
      ..writeln('permission from each mod author to distribute them:');
    for (final o in artifactOverrides) {
      buf.writeln('  - ${o.slug} (${o.sourceKind})');
    }
    buf.write('See: $_permissionsArticle');
    console.message(buf.toString());
  }
}
