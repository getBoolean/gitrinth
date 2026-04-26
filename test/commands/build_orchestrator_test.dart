import 'dart:io';

import 'package:gitrinth/src/app/env.dart';
import 'package:gitrinth/src/commands/build_assembler.dart';
import 'package:gitrinth/src/commands/build_orchestrator.dart';
import 'package:gitrinth/src/commands/build_pruner.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/manifest_io.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

/// Writes the test fixture's `mods.yaml` and `mods.lock`. The mods.lock
/// uses only `path:` source entries plus `files:` declarations so the
/// build pipeline never touches the network or Modrinth cache.
void _writeFixture(
  Directory packDir, {
  required Iterable<String> modPaths,
  required Map<String, _FileFixture> files,
}) {
  File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync(
    'slug: test_pack\n'
    'name: Test Pack\n'
    'version: 0.1.0\n'
    'description: integration test fixture\n'
    'mc-version: 1.21.1\n'
    'loader:\n'
    '  mods: fabric:0.17.3\n',
  );

  final modBlocks = StringBuffer();
  if (modPaths.isEmpty) {
    modBlocks.writeln('mods: {}');
  } else {
    modBlocks.writeln('mods:');
    for (final pth in modPaths) {
      final slug = p.basenameWithoutExtension(pth);
      modBlocks.writeln('  $slug:');
      modBlocks.writeln('    source: path');
      modBlocks.writeln('    path: $pth');
      modBlocks.writeln('    client: required');
      modBlocks.writeln('    server: required');
    }
  }

  final filesBlock = StringBuffer();
  if (files.isEmpty) {
    filesBlock.writeln('files: {}');
  } else {
    filesBlock.writeln('files:');
    for (final entry in files.entries) {
      filesBlock.writeln('  ${entry.key}:');
      filesBlock.writeln('    path: ${entry.value.sourcePath}');
      filesBlock.writeln('    client: ${entry.value.client}');
      filesBlock.writeln('    server: ${entry.value.server}');
      if (entry.value.preserve) {
        filesBlock.writeln('    preserve: true');
      }
    }
  }

  File(p.join(packDir.path, 'mods.lock')).writeAsStringSync(
    'gitrinth-version: 0.1.0\n'
    'loader:\n'
    '  mods: fabric:0.17.3\n'
    'mc-version: 1.21.1\n'
    '$modBlocks'
    'resource_packs: {}\n'
    'data_packs: {}\n'
    'shaders: {}\n'
    '$filesBlock',
  );
}

class _FileFixture {
  final String sourcePath;
  final String client;
  final String server;
  final bool preserve;
  const _FileFixture({
    required this.sourcePath,
    this.client = 'required',
    this.server = 'required',
    this.preserve = false,
  });
}

void main() {
  group('runBuild prune + files: integration', () {
    late Directory tempRoot;
    late Directory packDir;
    late Directory cacheRoot;
    late ManifestIo io;
    late ProviderContainer container;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_build_int_');
      packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
      cacheRoot = Directory(p.join(tempRoot.path, 'cache'))..createSync();
      io = ManifestIo(directory: packDir);
      container = ProviderContainer(
        overrides: [
          environmentProvider.overrideWithValue({
            'GITRINTH_CACHE': cacheRoot.path,
          }),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    String clientPath(String relPath) =>
        p.join(packDir.path, 'build', 'client', relPath);

    test('first build writes ledger and copies files: entries', () async {
      File(p.join(packDir.path, 'sodium.jar')).writeAsStringSync('SODIUM');
      File(
        p.join(packDir.path, 'sodium-options.json'),
      ).writeAsStringSync('{"version":1}');
      _writeFixture(
        packDir,
        modPaths: ['./sodium.jar'],
        files: {
          'config/sodium-options.json': _FileFixture(
            sourcePath: './sodium-options.json',
          ),
        },
      );

      final code = await runBuild(
        options: const BuildOptions(envFlag: 'client', skipDownload: true),
        container: container,
        console: const Console(),
        io: io,
      );

      expect(code, 0);
      expect(File(clientPath('mods/sodium.jar')).existsSync(), isTrue);
      expect(
        File(clientPath('config/sodium-options.json')).readAsStringSync(),
        '{"version":1}',
      );
      expect(File(clientPath('.gitrinth-state.yaml')).existsSync(), isTrue);
    });

    test('mod removed from manifest is pruned on rebuild', () async {
      File(p.join(packDir.path, 'sodium.jar')).writeAsStringSync('SODIUM');
      File(p.join(packDir.path, 'old.jar')).writeAsStringSync('OLD');
      _writeFixture(
        packDir,
        modPaths: ['./sodium.jar', './old.jar'],
        files: const {},
      );
      await runBuild(
        options: const BuildOptions(envFlag: 'client', skipDownload: true),
        container: container,
        console: const Console(),
        io: io,
      );
      expect(File(clientPath('mods/old.jar')).existsSync(), isTrue);

      // Drop "old" from the manifest, rebuild.
      _writeFixture(packDir, modPaths: ['./sodium.jar'], files: const {});
      await runBuild(
        options: const BuildOptions(envFlag: 'client', skipDownload: true),
        container: container,
        console: const Console(),
        io: io,
      );
      expect(File(clientPath('mods/old.jar')).existsSync(), isFalse);
      expect(File(clientPath('mods/sodium.jar')).existsSync(), isTrue);
    });

    test('preserve: true file edited by hand survives rebuild', () async {
      File(p.join(packDir.path, 'opts.json')).writeAsStringSync('{"v":1}');
      _writeFixture(
        packDir,
        modPaths: const [],
        files: {
          'config/opts.json': _FileFixture(
            sourcePath: './opts.json',
            preserve: true,
          ),
        },
      );
      await runBuild(
        options: const BuildOptions(envFlag: 'client', skipDownload: true),
        container: container,
        console: const Console(),
        io: io,
      );
      // User edits the deployed config.
      File(clientPath('config/opts.json')).writeAsStringSync('{"user":true}');
      // Source bytes change too — mimicking the upstream config bumping.
      File(p.join(packDir.path, 'opts.json')).writeAsStringSync('{"v":2}');

      await runBuild(
        options: const BuildOptions(envFlag: 'client', skipDownload: true),
        container: container,
        console: const Console(),
        io: io,
      );
      expect(
        File(clientPath('config/opts.json')).readAsStringSync(),
        '{"user":true}',
        reason: 'preserve must skip overwriting user-edited file',
      );
    });

    test(
      'preserve: removed from manifest prunes the file (not sticky)',
      () async {
        File(p.join(packDir.path, 'opts.json')).writeAsStringSync('{"v":1}');
        _writeFixture(
          packDir,
          modPaths: const [],
          files: {
            'config/opts.json': _FileFixture(
              sourcePath: './opts.json',
              preserve: true,
            ),
          },
        );
        await runBuild(
          options: const BuildOptions(envFlag: 'client', skipDownload: true),
          container: container,
          console: const Console(),
          io: io,
        );
        expect(File(clientPath('config/opts.json')).existsSync(), isTrue);

        _writeFixture(packDir, modPaths: const [], files: const {});
        await runBuild(
          options: const BuildOptions(envFlag: 'client', skipDownload: true),
          container: container,
          console: const Console(),
          io: io,
        );
        expect(File(clientPath('config/opts.json')).existsSync(), isFalse);
      },
    );

    test(
      'user-dropped jar in mods/ survives prune (loose-file protection)',
      () async {
        File(p.join(packDir.path, 'sodium.jar')).writeAsStringSync('S');
        _writeFixture(packDir, modPaths: ['./sodium.jar'], files: const {});
        await runBuild(
          options: const BuildOptions(envFlag: 'client', skipDownload: true),
          container: container,
          console: const Console(),
          io: io,
        );
        // User drops a custom jar after the build.
        File(clientPath('mods/coolmod.jar')).writeAsStringSync('CUSTOM');

        // Rebuild with the same manifest.
        await runBuild(
          options: const BuildOptions(envFlag: 'client', skipDownload: true),
          container: container,
          console: const Console(),
          io: io,
        );
        expect(File(clientPath('mods/coolmod.jar')).existsSync(), isTrue);
        expect(File(clientPath('mods/sodium.jar')).existsSync(), isTrue);
      },
    );

    test('--no-prune leaves obsolete files but still updates ledger', () async {
      File(p.join(packDir.path, 'a.jar')).writeAsStringSync('A');
      File(p.join(packDir.path, 'b.jar')).writeAsStringSync('B');
      _writeFixture(packDir, modPaths: ['./a.jar', './b.jar'], files: const {});
      await runBuild(
        options: const BuildOptions(envFlag: 'client', skipDownload: true),
        container: container,
        console: const Console(),
        io: io,
      );

      _writeFixture(packDir, modPaths: ['./a.jar'], files: const {});
      await runBuild(
        options: const BuildOptions(
          envFlag: 'client',
          skipDownload: true,
          noPrune: true,
        ),
        container: container,
        console: const Console(),
        io: io,
      );
      expect(
        File(clientPath('mods/b.jar')).existsSync(),
        isTrue,
        reason: '--no-prune must keep obsolete files',
      );
      // Ledger reflects the new desired state, so a follow-up build
      // without --no-prune will prune.
      final ledger = readLedgerOrEmpty(
        p.join(clientPath(''), '.gitrinth-state.yaml'),
        BuildEnv.client,
      );
      expect(ledger.files.keys, contains('mods/a.jar'));
      expect(ledger.files.keys, isNot(contains('mods/b.jar')));
    });

    test('side-filtering skips client-unsupported files: entries', () async {
      File(p.join(packDir.path, 'server-only.txt')).writeAsStringSync('S');
      _writeFixture(
        packDir,
        modPaths: const [],
        files: {
          'config/server-only.txt': _FileFixture(
            sourcePath: './server-only.txt',
            client: 'unsupported',
            server: 'required',
          ),
        },
      );
      await runBuild(
        options: const BuildOptions(envFlag: 'client', skipDownload: true),
        container: container,
        console: const Console(),
        io: io,
      );
      expect(File(clientPath('config/server-only.txt')).existsSync(), isFalse);
    });
  });
}
