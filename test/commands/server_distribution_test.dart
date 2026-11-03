import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/model/curseforge/cf_file_hash.dart';
import 'package:gitrinth/src/model/curseforge/cf_mod_file.dart';
import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_metadata_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';

void main() {
  late Directory root;
  late Map<String, String> environment;
  setUp(() {
    root = Directory.systemTemp.createTempSync('server_distribution_');
    environment = {
      'GITRINTH_CACHE': p.join(root.path, 'cache'),
      'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
    };
    for (final entry in {
      'server.jar': 'server-side mod',
      'client.jar': 'client-side mod',
      'settings.json': '{"setting":true}',
      'secret.txt': 'private fixture',
      'eula.txt': 'eula=true',
      '.env': 'private environment fixture',
    }.entries) {
      File(p.join(root.path, entry.key)).writeAsStringSync(entry.value);
    }
    File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'fabric:0.17.3'}
mods:
  server-mod: {path: server.jar, client: unsupported}
  client-mod: {path: client.jar, server: unsupported}
files:
  config/settings.json: {path: settings.json}
  config/client.json: {path: settings.json, server: unsupported}
  .env: {path: secret.txt}
  cache/token.json: {path: secret.txt}
  eula.txt: {path: eula.txt}
  config/renamed-auth.json: {path: .env}
''');
  });
  tearDown(() => root.deleteSync(recursive: true));
  Future<CapturedOutput> pack(List<String> flags) => runCli([
    '-C',
    root.path,
    'pack',
    '--offline',
    ...flags,
  ], environment: environment);
  Archive archive(String name) => ZipDecoder().decodeBytes(
    File(p.join(root.path, 'build', name)).readAsBytesSync(),
  );

  for (final target in ['.env', '.gitrinth/private.json']) {
    test('private source alias $target is excluded', () async {
      final private = File(p.join(root.path, target));
      private.parent.createSync(recursive: true);
      private.writeAsStringSync('private source bytes');
      File(p.join(root.path, 'settings.json')).deleteSync();
      Link(p.join(root.path, 'settings.json')).createSync(private.path);
      final result = await pack(['--curseforge', '--server-distribution']);
      expect(result.exitCode, 0, reason: result.stderr);
      final zip = archive('pack-1.0.0-server-distribution.zip');
      expect(zip.findFile('config/settings.json'), isNull);
    });
  }

  test('nonprivate source aliases preserve selected config bytes', () async {
    File(
      p.join(root.path, 'settings.json'),
    ).renameSync(p.join(root.path, 'settings-original.json'));
    Link(
      p.join(root.path, 'settings.json'),
    ).createSync(p.join(root.path, 'settings-original.json'));
    final result = await pack(['--curseforge', '--server-distribution']);
    expect(result.exitCode, 0, reason: result.stderr);
    expect(
      utf8.decode(
        archive(
          'pack-1.0.0-server-distribution.zip',
        ).findFile('config/settings.json')!.content,
      ),
      '{"setting":true}',
    );
  });
  test('legacy server ZIP remains a side-filtered manifest archive', () async {
    final result = await pack(['--curseforge']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final zip = archive('pack-1.0.0-server.zip');
    expect(zip.findFile('manifest.json'), isNotNull);
    expect(zip.findFile('overrides/mods/server.jar'), isNotNull);
    expect(zip.findFile('overrides/mods/client.jar'), isNull);
    expect(zip.findFile('gitrinth-server-distribution.json'), isNull);
  });

  test(
    'server distribution contains physical server bytes and no private state',
    () async {
      final result = await pack(['--curseforge', '--server-distribution']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final zip = archive('pack-1.0.0-server-distribution.zip');
      expect(
        utf8.decode(zip.findFile('mods/server.jar')!.content),
        'server-side mod',
      );
      expect(
        utf8.decode(zip.findFile('config/settings.json')!.content),
        '{"setting":true}',
      );
      for (final excluded in [
        'mods/client.jar',
        'config/client.json',
        '.env',
        'cache/token.json',
        'eula.txt',
        'config/renamed-auth.json',
        'manifest.json',
        'overrides/mods/server.jar',
      ]) {
        expect(zip.findFile(excluded), isNull, reason: excluded);
      }
      final marker = jsonDecode(
        utf8.decode(zip.findFile('gitrinth-server-distribution.json')!.content),
      );
      expect(marker['artifactType'], 'gitrinth-server-distribution');
      expect(marker['formatVersion'], 1);
      expect(marker['slug'], 'pack');
      expect(marker['version'], '1.0.0');
      expect(marker['minecraft'], '1.21.1');
      expect(marker['runtimeBundled'], isFalse);
      expect(
        marker['files'],
        contains(
          equals({
            'path': 'mods/server.jar',
            'sha256': sha256.convert(utf8.encode('server-side mod')).toString(),
          }),
        ),
      );
      expect(result.stdout, contains('runtime is not bundled'));
      expect(
        File(p.join(root.path, 'build', 'pack-1.0.0.zip')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'distribution flag requires CurseForge and a single server artifact',
    () async {
      for (final flags in [
        ['--server-distribution'],
        ['--curseforge', '--server-distribution', '--combined'],
      ]) {
        final result = await pack(flags);
        expect(result.exitCode, 64, reason: result.stderr);
        expect(
          result.stderr,
          contains(
            flags.length == 1
                ? '--server-distribution requires --curseforge'
                : '--server-distribution cannot be combined with --combined',
          ),
        );
        expect(Directory(p.join(root.path, 'build')).existsSync(), isFalse);
      }
    },
  );

  test(
    'metadata-only loader can distribute bytes without an archive token or runtime',
    () async {
      final manifest = File(p.join(root.path, 'mods.yaml'));
      manifest.writeAsStringSync(
        manifest
            .readAsStringSync()
            .replaceFirst('fabric:0.17.3', 'future-runtime:1.2.3')
            .replaceFirst(
              'mc_version: 1.21.1',
              'mc_version: 1.21.1\ngitrinth: {modrinth: disabled, curseforge: disabled}',
            ),
      );
      final descriptors = File(p.join(root.path, 'loaders.yaml'))
        ..writeAsStringSync(
          'version: 1\nloaders:\n  future-runtime:\n    role: mod\n',
        );
      final result = await pack([
        '--curseforge',
        '--server-distribution',
        '--loader-descriptors',
        descriptors.path,
        '--output',
        p.join('dist', 'server.zip'),
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final zip = ZipDecoder().decodeBytes(
        File(p.join(root.path, 'dist', 'server.zip')).readAsBytesSync(),
      );
      final marker = jsonDecode(
        utf8.decode(zip.findFile('gitrinth-server-distribution.json')!.content),
      );
      expect(marker['loader'], {'id': 'future-runtime', 'version': '1.2.3'});
      expect(marker['runtimeBundled'], isFalse);
      expect(zip.findFile('mods/server.jar'), isNotNull);
      expect(result.stdout, contains('runtime is not bundled'));
    },
  );

  test(
    'explicit CurseForge redistribution denial blocks physical bytes',
    () async {
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'fabric:0.17.3'}
gitrinth: {modrinth: disabled, curseforge: enabled}
mods: {restricted: {curseforge: '42'}}
''');
      final bytes = utf8.encode('restricted mod');
      final hash = sha1.convert(bytes).toString();
      final cache = GitrinthCache(root: environment['GITRINTH_CACHE']!);
      final cached = File(
        cache.curseforgePath(
          projectId: 42,
          fileId: 420,
          filename: 'restricted.jar',
        ),
      );
      cached.parent.createSync(recursive: true);
      cached.writeAsBytesSync(bytes);
      CurseForgeMetadataStore(cache).write(
        ModFile(
          id: 420,
          modId: 42,
          displayName: '1.0.0',
          fileName: 'restricted.jar',
          releaseType: 1,
          fileDate: '',
          gameVersions: ['1.21.1'],
          hashes: [FileHash(value: hash, algoCode: 1)],
          dependencies: [],
        ),
      );
      File(p.join(root.path, 'mods.lock')).writeAsStringSync(
        emitModsLock(
          ModsLock(
            gitrinthVersion: '0.1.0',
            mcVersion: '1.21.1',
            loader: const LoaderConfig(
              mods: ModLoader.fabric,
              modLoaderVersion: '0.17.3',
            ),
            mods: {
              'restricted': LockedEntry(
                slug: 'restricted',
                kind: LockedEntryKind.resolved,
                version: '1.0.0',
                curseforge: LockedCurseforgeSource(
                  projectId: 42,
                  fileId: 420,
                  allowModDistribution: false,
                  file: LockedFile(name: 'restricted.jar', sha1: hash),
                  gameVersions: ['1.21.1'],
                ),
              ),
            },
          ),
        ),
      );
      final result = await pack(['--curseforge', '--server-distribution']);
      expect(result.exitCode, 2, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, allOf(contains('42'), contains('redistribution')));
      expect(
        File(
          p.join(root.path, 'build', 'pack-1.0.0-server-distribution.zip'),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('plugin-server distribution retains its runtime identity', () async {
    final manifest = File(p.join(root.path, 'mods.yaml'));
    manifest.writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {plugins: 'paper:100'}
plugins:
  server-plugin: {path: server.jar}
files:
  config/settings.json: {path: settings.json}
''');
    final result = await pack(['--curseforge', '--server-distribution']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final zip = archive('pack-1.0.0-server-distribution.zip');
    final marker = jsonDecode(
      utf8.decode(zip.findFile('gitrinth-server-distribution.json')!.content),
    );
    expect(marker['loader'], {
      'id': 'vanilla',
      'version': null,
      'plugins': {'id': 'paper', 'version': '100'},
    });
    expect(zip.findFile('plugins/server.jar'), isNotNull);
  });
}
