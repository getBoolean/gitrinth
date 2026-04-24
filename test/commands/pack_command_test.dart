import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

Map<String, dynamic> _readIndex(File mrpack) {
  final archive = ZipDecoder().decodeBytes(mrpack.readAsBytesSync());
  final index = archive.files.firstWhere(
    (f) => f.name == 'modrinth.index.json',
  );
  return jsonDecode(utf8.decode(index.content as List<int>))
      as Map<String, dynamic>;
}

Set<String> _zipPaths(File mrpack) {
  final archive = ZipDecoder().decodeBytes(mrpack.readAsBytesSync());
  return archive.files.map((f) => f.name).toSet();
}

void main() {
  late Directory tempRoot;
  late Directory packDir;
  late Directory cacheDir;
  late FakeModrinth modrinth;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_pack_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
    cacheDir = Directory(p.join(tempRoot.path, 'cache'))..createSync();
    modrinth = FakeModrinth();
    await modrinth.start();
  });

  tearDown(() async {
    await modrinth.stop();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<void> writeManifest(String body) async {
    File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync(body);
  }

  Map<String, String> defaultEnv() => {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
        'GITRINTH_CACHE': cacheDir.path,
      };

  test(
    'default: writes both client and server .mrpack with valid indexes; mentions mrpack-install',
    () async {
      modrinth.registerVersion(
        slug: 'sodium',
        versionNumber: '0.6.0',
        loader: 'fabric',
      );
      // Inject sha1 (the resolver propagates whatever Modrinth returns).
      final files = (modrinth.versions['sodium']!.first['files'] as List)
          .cast<Map<String, dynamic>>();
      (files.first['hashes'] as Map<String, dynamic>)['sha1'] = 'abc123';

      await writeManifest('''
slug: testpack
name: Test Pack
version: 1.2.3
description: a test pack
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  sodium: ^0.6.0
''');

      final out = await runCli(
        ['-C', packDir.path, 'pack'],
        environment: defaultEnv(),
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final clientPack = File(
        p.join(packDir.path, 'build', 'testpack-1.2.3.mrpack'),
      );
      final serverPack = File(
        p.join(packDir.path, 'build', 'testpack-1.2.3-server.mrpack'),
      );
      expect(clientPack.existsSync(), isTrue);
      expect(serverPack.existsSync(), isTrue);

      // Both packs share top-level metadata; sodium (env: both) appears in
      // both since it's needed everywhere.
      for (final mrpack in [clientPack, serverPack]) {
        final index = _readIndex(mrpack);
        expect(index['game'], 'minecraft');
        expect(index['formatVersion'], 1);
        expect(index['versionId'], '1.2.3');
        expect(index['name'], 'Test Pack');
        expect(index['summary'], 'a test pack');
        expect(index['dependencies'], {
          'minecraft': '1.21.1',
          'fabric-loader': '0.17.3',
        });
        final fileEntries =
            (index['files'] as List).cast<Map<String, dynamic>>();
        expect(fileEntries, hasLength(1));
        final sodium = fileEntries.single;
        expect(sodium['path'], 'mods/sodium-0.6.0.jar');
        expect(sodium['env'], {'client': 'required', 'server': 'required'});
        expect((sodium['hashes'] as Map)['sha1'], 'abc123');
        expect(sodium['fileSize'], isPositive);
        expect(
          _zipPaths(mrpack).where((n) => n.startsWith('overrides')),
          isEmpty,
        );
      }

      // Server install hint surfaces so admins know how to consume the pack.
      expect(
        out.stdout,
        contains('https://github.com/nothub/mrpack-install'),
      );
      expect(out.stdout, isNot(contains('permission from each mod author')));
    },
  );

  test(
    '--combined: writes a single .mrpack and skips the mrpack-install hint',
    () async {
      modrinth.registerVersion(
        slug: 'sodium',
        versionNumber: '0.6.0',
        loader: 'fabric',
      );
      final files = (modrinth.versions['sodium']!.first['files'] as List)
          .cast<Map<String, dynamic>>();
      (files.first['hashes'] as Map<String, dynamic>)['sha1'] = 'abc';

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  sodium: ^0.6.0
''');

      final out = await runCli(
        ['-C', packDir.path, 'pack', '--combined'],
        environment: defaultEnv(),
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final clientPack = File(
        p.join(packDir.path, 'build', 'pack-0.1.0.mrpack'),
      );
      final serverPack = File(
        p.join(packDir.path, 'build', 'pack-0.1.0-server.mrpack'),
      );
      expect(clientPack.existsSync(), isTrue);
      expect(
        serverPack.existsSync(),
        isFalse,
        reason: '--combined produces a single artifact, not a -server twin',
      );
      expect(
        out.stdout,
        isNot(contains('mrpack-install')),
        reason: 'the install hint is only relevant when a server pack exists',
      );
    },
  );

  test('--output overrides the default path', () async {
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '0.6.0',
      loader: 'fabric',
    );
    final files = (modrinth.versions['sodium']!.first['files'] as List)
        .cast<Map<String, dynamic>>();
    (files.first['hashes'] as Map<String, dynamic>)['sha1'] = 'abc';

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  sodium: ^0.6.0
''');

    final customPath = p.join(packDir.path, 'dist', 'custom-name.mrpack');
    final out = await runCli(
      ['-C', packDir.path, 'pack', '--output', customPath],
      environment: defaultEnv(),
    );
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    // Client pack lands at the override path; server twin sits next to it
    // with `-server` inserted before the extension.
    expect(File(customPath).existsSync(), isTrue);
    expect(
      File(p.join(packDir.path, 'dist', 'custom-name-server.mrpack')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(packDir.path, 'build', 'pack-0.1.0.mrpack')).existsSync(),
      isFalse,
      reason: '--output should redirect, not duplicate',
    );
  });

  test('--publishable refuses url-source mods with offending slugs listed',
      () async {
    final localJar = File(p.join(packDir.path, 'mods', 'local.jar'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.fromList(List.generate(8, (i) => i)));

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  local-mod:
    path: ${p.relative(localJar.path, from: packDir.path).replaceAll(r'\', '/')}
''');

    final out = await runCli(
      ['-C', packDir.path, 'pack', '--publishable'],
      environment: defaultEnv(),
    );
    expect(out.exitCode, isNot(0), reason: out.stdout);
    expect(out.stderr, contains('--publishable refused'));
    expect(out.stderr, contains('local-mod (path)'));
  });

  test(
    '--publishable allows a url-source resource pack (not a mod)',
    () async {
      modrinth.registerVersion(
        slug: 'sodium',
        versionNumber: '0.6.0',
        loader: 'fabric',
      );
      final files = (modrinth.versions['sodium']!.first['files'] as List)
          .cast<Map<String, dynamic>>();
      (files.first['hashes'] as Map<String, dynamic>)['sha1'] = 'abc';

      // A custom resource pack hosted somewhere outside Modrinth — bytes
      // served by the fake's /downloads route.
      modrinth.addArtifact(
        'rp',
        'custom-pack.zip',
        Uint8List.fromList(List.generate(16, (i) => i)),
      );

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  sodium: ^0.6.0
resource_packs:
  custom-pack:
    url: ${modrinth.downloadBaseUrl}/rp/custom-pack.zip
''');

      final out = await runCli(
        ['-C', packDir.path, 'pack', '--publishable'],
        environment: defaultEnv(),
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final mrpack = File(
        p.join(packDir.path, 'build', 'pack-0.1.0.mrpack'),
      );
      expect(mrpack.existsSync(), isTrue);

      // RP went to overrides/, not files[].
      final paths = _zipPaths(mrpack);
      expect(
        paths,
        contains('overrides/resourcepacks/custom-pack.zip'),
      );
      final fileEntries = (_readIndex(mrpack)['files'] as List)
          .cast<Map<String, dynamic>>();
      expect(fileEntries, hasLength(1));
      expect(fileEntries.single['path'], 'mods/sodium-0.6.0.jar');
    },
  );

  test(
    'non-publishable run with url-source mods: bundles them and prints sorted permissions warning',
    () async {
      modrinth.addArtifact(
        'remote-a',
        'remote-a.jar',
        Uint8List.fromList(List.generate(8, (i) => i + 10)),
      );
      modrinth.addArtifact(
        'remote-b',
        'remote-b.jar',
        Uint8List.fromList(List.generate(8, (i) => i + 20)),
      );

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  zeta-mod:
    url: ${modrinth.downloadBaseUrl}/remote-b/remote-b.jar
  alpha-mod:
    url: ${modrinth.downloadBaseUrl}/remote-a/remote-a.jar
''');

      final out = await runCli(
        ['-C', packDir.path, 'pack'],
        environment: defaultEnv(),
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final mrpack = File(
        p.join(packDir.path, 'build', 'pack-0.1.0.mrpack'),
      );
      final paths = _zipPaths(mrpack);
      expect(paths, contains('overrides/mods/remote-a.jar'));
      expect(paths, contains('overrides/mods/remote-b.jar'));

      // Permissions warning printed, with both slugs in alphabetical order.
      expect(out.stdout, contains('permission from each mod author'));
      expect(
        out.stdout,
        contains('https://support.modrinth.com/en/articles/8797527'),
      );
      final alphaIdx = out.stdout.indexOf('- alpha-mod (url)');
      final zetaIdx = out.stdout.indexOf('- zeta-mod (url)');
      expect(alphaIdx, greaterThan(0));
      expect(zetaIdx, greaterThan(alphaIdx),
          reason: 'slugs must be listed alphabetically');
    },
  );

  test(
    'split-by-default routes env-aware overrides into the correct pack',
    () async {
      modrinth.addArtifact(
        'srv',
        'srv-mod.jar',
        Uint8List.fromList(List.generate(8, (i) => i + 30)),
      );
      modrinth.addArtifact(
        'cli',
        'cli-mod.jar',
        Uint8List.fromList(List.generate(8, (i) => i + 40)),
      );
      modrinth.addArtifact(
        'shr',
        'cool-shader.zip',
        Uint8List.fromList(List.generate(16, (i) => i + 50)),
      );

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
  shaders: iris
mc-version: 1.21.1
mods:
  both-mod:
    url: ${modrinth.downloadBaseUrl}/srv/srv-mod.jar
  server-mod:
    url: ${modrinth.downloadBaseUrl}/srv/srv-mod.jar
    environment: server
  client-mod:
    url: ${modrinth.downloadBaseUrl}/cli/cli-mod.jar
    environment: client
shaders:
  custom-shader:
    url: ${modrinth.downloadBaseUrl}/shr/cool-shader.zip
''');

      final out = await runCli(
        ['-C', packDir.path, 'pack'],
        environment: defaultEnv(),
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final clientPaths = _zipPaths(
        File(p.join(packDir.path, 'build', 'pack-0.1.0.mrpack')),
      );
      final serverPaths = _zipPaths(
        File(p.join(packDir.path, 'build', 'pack-0.1.0-server.mrpack')),
      );

      // both-mod is needed everywhere → overrides/ in both packs.
      expect(clientPaths, contains('overrides/mods/srv-mod.jar'));
      expect(serverPaths, contains('overrides/mods/srv-mod.jar'));

      // server-only mod is dropped from the client pack and lands in
      // server-overrides/ inside the server pack.
      expect(
        clientPaths.any((p) => p.endsWith('srv-mod.jar') && p != 'overrides/mods/srv-mod.jar'),
        isFalse,
      );
      expect(serverPaths, contains('server-overrides/mods/srv-mod.jar'));

      // client-only mod is dropped from the server pack.
      expect(clientPaths, contains('client-overrides/mods/cli-mod.jar'));
      expect(serverPaths.any((p) => p.contains('cli-mod.jar')), isFalse);

      // Shaders are forced client-only → only in the client pack.
      expect(
        clientPaths,
        contains('client-overrides/shaderpacks/cool-shader.zip'),
      );
      expect(
        serverPaths.any((p) => p.contains('cool-shader.zip')),
        isFalse,
      );

      // Permissions warning still lists every mod-section override across
      // both packs (since the user is publishing both artifacts).
      expect(out.stdout, contains('- both-mod (url)'));
      expect(out.stdout, contains('- client-mod (url)'));
      expect(out.stdout, contains('- server-mod (url)'));
      expect(out.stdout, isNot(contains('- custom-shader')));
    },
  );

  test(
    'non-publishable run with only a url-source RESOURCE PACK: no permissions warning',
    () async {
      modrinth.registerVersion(
        slug: 'sodium',
        versionNumber: '0.6.0',
        loader: 'fabric',
      );
      final files = (modrinth.versions['sodium']!.first['files'] as List)
          .cast<Map<String, dynamic>>();
      (files.first['hashes'] as Map<String, dynamic>)['sha1'] = 'abc';

      modrinth.addArtifact(
        'rp',
        'custom-pack.zip',
        Uint8List.fromList(List.generate(16, (i) => i)),
      );

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  sodium: ^0.6.0
resource_packs:
  custom-pack:
    url: ${modrinth.downloadBaseUrl}/rp/custom-pack.zip
''');

      final out = await runCli(
        ['-C', packDir.path, 'pack'],
        environment: defaultEnv(),
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(
        out.stdout,
        isNot(contains('permission from each mod author')),
        reason: 'RP overrides do not require Modrinth-style mod permissions',
      );
    },
  );
}
