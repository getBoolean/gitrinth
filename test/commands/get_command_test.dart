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

  test(
    'resolves a simple manifest, writes mods.lock, downloads artifact',
    () async {
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
            },
          ],
          'dependencies': [],
          'loaders': ['neoforge'],
          'game_versions': ['1.21.1'],
        },
      ];

      await writeManifest('''
slug: testpack
name: TestPack
version: 0.1.0
description: x
loader:
  mods: neoforge
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
    },
  );

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
          },
        ],
        'dependencies': [],
        'loaders': ['neoforge'],
        'game_versions': ['1.21.1'],
      },
    ];

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
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
      File(
        p.join(cacheDir.path, 'modrinth', 'A_ID', 'A_V1', 'a-1.0.0.jar'),
      ).existsSync(),
      isFalse,
    );
  });

  test('--enforce-lockfile fails when mods.lock is missing', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
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
loader:
  mods: neoforge
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

  test(
    'shorthand channel token pins an entry to that stability floor',
    () async {
      modrinth.registerVersion(
        slug: 'a',
        versionNumber: '1.0.0',
        versionType: 'release',
      );
      modrinth.registerVersion(
        slug: 'a',
        versionNumber: '1.0.1-beta',
        versionType: 'beta',
      );
      modrinth.registerVersion(
        slug: 'a',
        versionNumber: '1.0.2-alpha',
        versionType: 'alpha',
      );

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
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
      final lockText = File(
        p.join(packDir.path, 'mods.lock'),
      ).readAsStringSync();
      // beta floor excludes alpha; 1.0.1-beta is the highest admitted.
      expect(lockText, contains('version: 1.0.1-beta'));
      expect(lockText, isNot(contains('1.0.2-alpha')));
    },
  );

  test('long-form channel: release excludes betas for that entry', () async {
    modrinth.registerVersion(
      slug: 'a',
      versionNumber: '1.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'a',
      versionNumber: '1.0.1-beta',
      versionType: 'beta',
    );
    modrinth.registerVersion(
      slug: 'b',
      versionNumber: '2.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'b',
      versionNumber: '2.0.1-beta',
      versionType: 'beta',
    );

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
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
loader:
  mods: neoforge
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
          },
        ],
        'dependencies': [],
        'loaders': ['neoforge'],
        'game_versions': ['1.21.1'],
      },
    ];

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
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
    // A clean rerun where nothing changed and nothing is outdated should
    // skip the per-package listing entirely and end on `Got dependencies!`.
    expect(second.stdout, contains('Got dependencies!'));
    expect(second.stdout, isNot(contains('Downloading packages...')));
    expect(second.stdout, isNot(contains('Changed')));
  });

  test(
    'shader slug resolves with loader.shaders and iris-tagged version',
    () async {
      final jarBytes = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final sha = modrinth.addArtifact(
        'complementary-reimagined',
        'complementary-reimagined-r5.7.1.zip',
        jarBytes,
      );
      modrinth.versions['complementary-reimagined'] = [
        {
          'id': 'COMP_V1',
          'project_id': 'COMP_ID',
          'version_number': 'r5.7.1',
          'files': [
            {
              'url':
                  '${modrinth.downloadBaseUrl}/complementary-reimagined/complementary-reimagined-r5.7.1.zip',
              'filename': 'complementary-reimagined-r5.7.1.zip',
              'hashes': {'sha512': sha},
              'size': jarBytes.length,
              'primary': true,
            },
          ],
          'dependencies': [],
          'loaders': ['iris', 'optifine'],
          'game_versions': ['1.21.1'],
        },
      ];

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
  shaders: iris
mc-version: 1.21.1
shaders:
  complementary-reimagined: ^r5.7.1
''');

      final out = await runCli(
        ['-C', packDir.path, 'get'],
        environment: {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_CACHE': cacheDir.path,
        },
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final lockText = File(
        p.join(packDir.path, 'mods.lock'),
      ).readAsStringSync();
      expect(lockText, contains('shaders:'));
      expect(lockText, contains('complementary-reimagined:'));
      expect(lockText, contains('version: r5.7.1'));

      // The CLI must have sent loaders=["iris"] on the shader request,
      // not the mod loader.
      final shaderQuery = modrinth.lastVersionQuery['complementary-reimagined'];
      expect(shaderQuery, isNotNull);
      expect(shaderQuery!['loaders'], '["iris"]');
    },
  );

  test('resource-pack slug resolves without a loaders filter', () async {
    final zipBytes = Uint8List.fromList(List.generate(16, (i) => i + 2));
    final sha = modrinth.addArtifact(
      'faithful-32x',
      'faithful-32x-1.21.zip',
      zipBytes,
    );
    modrinth.versions['faithful-32x'] = [
      {
        'id': 'FAITH_V1',
        'project_id': 'FAITH_ID',
        'version_number': '1.21.1-december-2025',
        'files': [
          {
            'url':
                '${modrinth.downloadBaseUrl}/faithful-32x/faithful-32x-1.21.zip',
            'filename': 'faithful-32x-1.21.zip',
            'hashes': {'sha512': sha},
            'size': zipBytes.length,
            'primary': true,
          },
        ],
        'dependencies': [],
        'loaders': ['minecraft'],
        'game_versions': ['1.21.1'],
      },
    ];

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
resource_packs:
  faithful-32x: ^1.21.1-december-2025
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
    expect(lockText, contains('resource_packs:'));
    expect(lockText, contains('faithful-32x:'));

    final rpQuery = modrinth.lastVersionQuery['faithful-32x'];
    expect(rpQuery, isNotNull);
    expect(
      rpQuery!.containsKey('loaders'),
      isFalse,
      reason: 'resource_packs requests must omit the loaders filter',
    );
  });

  test('data-pack slug resolves without a loaders filter', () async {
    final zipBytes = Uint8List.fromList(List.generate(16, (i) => i + 3));
    final sha = modrinth.addArtifact(
      'terralith',
      'terralith-2.5.8.zip',
      zipBytes,
    );
    modrinth.versions['terralith'] = [
      {
        'id': 'TERRA_V1',
        'project_id': 'TERRA_ID',
        'version_number': '2.5.8',
        'files': [
          {
            'url': '${modrinth.downloadBaseUrl}/terralith/terralith-2.5.8.zip',
            'filename': 'terralith-2.5.8.zip',
            'hashes': {'sha512': sha},
            'size': zipBytes.length,
            'primary': true,
          },
        ],
        'dependencies': [],
        'loaders': ['datapack'],
        'game_versions': ['1.21.1'],
      },
    ];

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
data_packs:
  terralith: ^2.5.8
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
    expect(lockText, contains('data_packs:'));
    expect(lockText, contains('terralith:'));

    final dpQuery = modrinth.lastVersionQuery['terralith'];
    expect(dpQuery, isNotNull);
    expect(
      dpQuery!.containsKey('loaders'),
      isFalse,
      reason: 'data_packs requests must omit the loaders filter',
    );
  });

  test(
    'missing path sources: all errors reported together, no early exit',
    () async {
      // Two path sources to different missing files, plus a real modrinth mod.
      // If the fetch loop throws on the first missing path, the second one
      // won't be reported — the user has to run twice to discover every bad
      // path. The contract is: finish the loop, collect every error, then
      // surface them all in one exit.
      final jarBytes = Uint8List.fromList([1, 2, 3, 4]);
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
            },
          ],
          'dependencies': [],
          'loaders': ['neoforge'],
          'game_versions': ['1.21.1'],
        },
      ];

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  jei: ^1.0.0
  local-a:
    path: ./mods/local-a.jar
  local-b:
    path: ./mods/local-b.jar
''');

      final out = await runCli(
        ['-C', packDir.path, 'get'],
        environment: {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_CACHE': cacheDir.path,
        },
      );
      expect(out.exitCode, isNot(0), reason: out.stdout);
      expect(out.stderr, contains('local-a'));
      expect(
        out.stderr,
        contains('local-b'),
        reason:
            'second failing path must still surface; the loop should not '
            'bail on the first error',
      );
      // The modrinth download still has to have happened — proving the error
      // surfaced AFTER the loop completed rather than short-circuiting it.
      expect(
        File(
          p.join(
            cacheDir.path,
            'modrinth',
            'JEI_ID',
            'JEI_V1',
            'jei-1.0.0.jar',
          ),
        ).existsSync(),
        isTrue,
        reason: 'jei should have downloaded before errors were reported',
      );
    },
  );
}
