import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  late Directory tempRoot;
  late Directory packDir;
  late Directory cacheDir;
  late FakeModrinth modrinth;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_get_');
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

  test('resolves a simple manifest, writes mods.lock, downloads artifact', () async {
    final jarBytes = Uint8List.fromList(List.generate(64, (i) => i & 0xff));
    final sha = modrinth.addArtifact('jei', 'jei-1.0.0.jar', jarBytes);
    modrinth.projects['jei'] = {
      'id': 'JEI_ID',
      'slug': 'jei',
      'title': 'JEI',
      'project_type': 'mod',
    };
    modrinth.versions['jei'] = [
      {
        'id': 'JEI_V1',
        'project_id': 'JEI_ID',
        'version_number': '1.0.0',
        'files': [
          {
            'url': '${modrinth.downloadBaseUrl}/jei/jei-1.0.0.jar',
            'filename': 'jei-1.0.0.jar',
            'hashes': {'sha512': sha},
            'size': jarBytes.length,
            'primary': true,
          }
        ],
        'dependencies': [],
        'loaders': ['neoforge'],
        'game_versions': ['1.21.1'],
      }
    ];

    await writeManifest('''
slug: testpack
name: TestPack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  jei: ^1.0.0
''');

    final out = await runCli(
      ['-C', packDir.path, 'get'],
      environment: {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      },
    );
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

    final lockFile = File(p.join(packDir.path, 'mods.lock'));
    expect(lockFile.existsSync(), isTrue);
    final lockText = lockFile.readAsStringSync();
    expect(lockText, contains('jei:'));
    expect(lockText, contains('version: 1.0.0'));

    final cachedJar = File(
      p.join(cacheDir.path, 'modrinth', 'JEI_ID', 'JEI_V1', 'jei-1.0.0.jar'),
    );
    expect(cachedJar.existsSync(), isTrue);
    expect(cachedJar.readAsBytesSync(), jarBytes);
  });

  test('--dry-run on first run does not write and exits 2', () async {
    final jarBytes = Uint8List.fromList([1, 2, 3]);
    final sha = modrinth.addArtifact('a', 'a-1.0.0.jar', jarBytes);
    modrinth.versions['a'] = [
      {
        'id': 'A_V1',
        'project_id': 'A_ID',
        'version_number': '1.0.0',
        'files': [
          {
            'url': '${modrinth.downloadBaseUrl}/a/a-1.0.0.jar',
            'filename': 'a-1.0.0.jar',
            'hashes': {'sha512': sha},
            'size': jarBytes.length,
            'primary': true,
          }
        ],
        'dependencies': [],
        'loaders': ['neoforge'],
        'game_versions': ['1.21.1'],
      }
    ];

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  a:
''');

    final out = await runCli(
      ['-C', packDir.path, 'get', '--dry-run'],
      environment: {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      },
    );
    expect(out.exitCode, 2, reason: out.stderr);
    expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isFalse);
    expect(
      File(p.join(cacheDir.path, 'modrinth', 'A_ID', 'A_V1', 'a-1.0.0.jar'))
          .existsSync(),
      isFalse,
    );
  });

  test('--enforce-lockfile fails when mods.lock is missing', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  a: ^1.0.0
''');
    final out = await runCli(
      ['-C', packDir.path, 'get', '--enforce-lockfile'],
      environment: {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      },
    );
    expect(out.exitCode, 2, reason: out.stderr);
  });

  test('entry with no channel declared admits every version_type', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '1.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '1.0.1-beta',
      versionType: 'beta',
    );

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  jei:
''');

    final out = await runCli(
      ['-C', packDir.path, 'get'],
      environment: {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      },
    );
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lockText = File(p.join(packDir.path, 'mods.lock')).readAsStringSync();
    // Permissive default → beta wins because it's the highest semver.
    expect(lockText, contains('version: 1.0.1-beta'));
  });

  test('shorthand channel token pins an entry to that stability floor', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0', versionType: 'release');
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.1-beta', versionType: 'beta');
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.2-alpha', versionType: 'alpha');

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  a: beta
''');

    final out = await runCli(
      ['-C', packDir.path, 'get'],
      environment: {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      },
    );
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lockText = File(p.join(packDir.path, 'mods.lock')).readAsStringSync();
    // beta floor excludes alpha; 1.0.1-beta is the highest admitted.
    expect(lockText, contains('version: 1.0.1-beta'));
    expect(lockText, isNot(contains('1.0.2-alpha')));
  });

  test('long-form channel: release excludes betas for that entry', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0', versionType: 'release');
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.1-beta', versionType: 'beta');
    modrinth.registerVersion(slug: 'b', versionNumber: '2.0.0', versionType: 'release');
    modrinth.registerVersion(slug: 'b', versionNumber: '2.0.1-beta', versionType: 'beta');

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  a:
    channel: release
  b:
''');

    final out = await runCli(
      ['-C', packDir.path, 'get'],
      environment: {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      },
    );
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lockText = File(p.join(packDir.path, 'mods.lock')).readAsStringSync();
    expect(lockText, contains('version: 1.0.0'));
    expect(lockText, isNot(contains('1.0.1-beta')));
    // b has no channel → permissive default admits beta.
    expect(lockText, contains('version: 2.0.1-beta'));
  });

  test('unknown slug emits a friendly error naming the slug', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  does-not-exist: ^1.0.0
''');

    final out = await runCli(
      ['-C', packDir.path, 'get'],
      environment: {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      },
    );
    expect(out.exitCode, isNot(0), reason: out.stderr);
    expect(out.stderr, contains("'does-not-exist'"));
    expect(out.stderr, contains('not found'));
    expect(out.stderr, isNot(contains('DioException')));
    expect(out.stderr, isNot(contains('HTTP 404')));
    expect(out.stderr, isNot(contains('failed to list versions')));
  });

  test('re-run is a no-op (cache hit)', () async {
    final jarBytes = Uint8List.fromList(List.generate(32, (i) => i));
    final sha = modrinth.addArtifact('b', 'b-1.0.0.jar', jarBytes);
    modrinth.versions['b'] = [
      {
        'id': 'B_V1',
        'project_id': 'B_ID',
        'version_number': '1.0.0',
        'files': [
          {
            'url': '${modrinth.downloadBaseUrl}/b/b-1.0.0.jar',
            'filename': 'b-1.0.0.jar',
            'hashes': {'sha512': sha},
            'size': jarBytes.length,
            'primary': true,
          }
        ],
        'dependencies': [],
        'loaders': ['neoforge'],
        'game_versions': ['1.21.1'],
      }
    ];

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
mods:
  b: ^1.0.0
''');

    final env = {
      'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
      'GITRINTH_CACHE': cacheDir.path,
    };
    final first = await runCli(['-C', packDir.path, 'get'], environment: env);
    expect(first.exitCode, 0, reason: first.stderr);
    final second = await runCli(['-C', packDir.path, 'get'], environment: env);
    expect(second.exitCode, 0, reason: second.stderr);
    expect(second.stdout, contains('cache hit'));
  });
}
