import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gitrinth/src/service/cache.dart';
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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

      final hostSeg = GitrinthCache.hostCacheSegment(modrinth.baseUrl);
      final cachedJar = File(
        p.join(
          cacheDir.path,
          'modrinth',
          hostSeg,
          'JEI_ID',
          'JEI_V1',
          'jei-1.0.0.jar',
        ),
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
  mods: "neoforge:21.1.50"
  shaders: iris
mc_version: 1.21.1
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

  test('resource-pack slug resolves with loaders=["minecraft"]', () async {
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
      rpQuery!['loaders'],
      '["minecraft"]',
      reason:
          'resource_packs requests must filter loaders to "minecraft" so '
          'mod+resource-pack projects do not resolve to a mod jar.',
    );
  });

  test('data-pack slug resolves with loaders=["datapack"]', () async {
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
      dpQuery!['loaders'],
      '["datapack"]',
      reason:
          'data_packs requests must filter loaders to "datapack" so '
          'mod+datapack projects do not resolve to a mod jar.',
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
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
      final pathHostSeg = GitrinthCache.hostCacheSegment(modrinth.baseUrl);
      expect(
        File(
          p.join(
            cacheDir.path,
            'modrinth',
            pathHostSeg,
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

  group('one-shot mc-version validation', () {
    test(
      'first lock validates mc-version against /v2/tag/game_version',
      () async {
        modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
        expect(modrinth.requestCounts['/v2/tag/game_version'], 1);
      },
    );

    test(
      'unknown mc-version fails with exit 2 and a helpful message',
      () async {
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.99.99
mods: {}
''');

        final out = await runCli(
          ['-C', packDir.path, 'get'],
          environment: {
            'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
            'GITRINTH_CACHE': cacheDir.path,
          },
        );
        expect(out.exitCode, 2, reason: out.stdout);
        expect(out.stderr, contains('1.99.99'));
        expect(out.stderr, contains('not a known Minecraft release'));
      },
    );

    test(
      'second get with unchanged mc-version skips the validation call',
      () async {
        modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  jei: ^1.0.0
''');

        final env = {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_CACHE': cacheDir.path,
        };
        final first = await runCli([
          '-C',
          packDir.path,
          'get',
        ], environment: env);
        expect(first.exitCode, 0, reason: first.stderr);
        expect(modrinth.requestCounts['/v2/tag/game_version'], 1);

        final second = await runCli([
          '-C',
          packDir.path,
          'get',
        ], environment: env);
        expect(second.exitCode, 0, reason: second.stderr);
        // Second run must NOT have called the game-version endpoint —
        // mc-version was already validated when it was first locked.
        expect(modrinth.requestCounts['/v2/tag/game_version'], 1);
      },
    );

    test('changing mc-version in mods.yaml triggers re-validation', () async {
      modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  jei: ^1.0.0
''');

      final env = {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_CACHE': cacheDir.path,
      };
      await runCli(['-C', packDir.path, 'get'], environment: env);
      expect(modrinth.requestCounts['/v2/tag/game_version'], 1);

      // User edits mc-version. Resolver must re-validate.
      modrinth.registerVersion(
        slug: 'jei',
        versionNumber: '2.0.0',
        gameVersion: '1.20.1',
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.20.1
mods:
  jei: ^2.0.0
''');
      await runCli(['-C', packDir.path, 'get'], environment: env);
      expect(modrinth.requestCounts['/v2/tag/game_version'], 2);
    });
  });

  group('loader-version resolution', () {
    test(
      'concrete tag validates against fabric-meta on first get and lock records it',
      () async {
        modrinth.registerVersion(
          slug: 'sodium',
          versionNumber: '0.6.0',
          loader: 'fabric',
        );
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc_version: 1.21.1
mods:
  sodium: ^0.6.0
''');

        final out = await runCli(
          ['-C', packDir.path, 'get'],
          environment: {
            'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
            'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
            'GITRINTH_CACHE': cacheDir.path,
          },
        );
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final lockText = File(
          p.join(packDir.path, 'mods.lock'),
        ).readAsStringSync();
        expect(lockText, contains('mods: "fabric:0.17.3"'));
        expect(modrinth.requestCounts['/fabric/v2/versions/loader'], 1);
      },
    );

    test(
      'fabric:stable resolves to the newest stable upstream entry',
      () async {
        modrinth.registerVersion(
          slug: 'sodium',
          versionNumber: '0.6.0',
          loader: 'fabric',
        );
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:stable"
mc_version: 1.21.1
mods:
  sodium: ^0.6.0
''');

        final out = await runCli(
          ['-C', packDir.path, 'get'],
          environment: {
            'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
            'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
            'GITRINTH_CACHE': cacheDir.path,
          },
        );
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final lockText = File(
          p.join(packDir.path, 'mods.lock'),
        ).readAsStringSync();
        // First fake fabric-meta entry that has stable: true is 0.17.3.
        expect(lockText, contains('mods: "fabric:0.17.3"'));
        expect(modrinth.requestCounts['/fabric/v2/versions/loader'], 1);
      },
    );

    test(
      'fabric:latest picks the newest entry regardless of stability',
      () async {
        modrinth.fabricLoaderVersions = [
          {'version': '0.18.0-beta.1', 'stable': false},
          {'version': '0.17.3', 'stable': true},
        ];
        modrinth.registerVersion(
          slug: 'sodium',
          versionNumber: '0.6.0',
          loader: 'fabric',
        );
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:latest"
mc_version: 1.21.1
mods:
  sodium: ^0.6.0
''');

        final out = await runCli(
          ['-C', packDir.path, 'get'],
          environment: {
            'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
            'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
            'GITRINTH_CACHE': cacheDir.path,
          },
        );
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final lockText = File(
          p.join(packDir.path, 'mods.lock'),
        ).readAsStringSync();
        expect(lockText, contains('mods: "fabric:0.18.0-beta.1"'));
      },
    );

    test(
      'second get with a concrete tag matching the lock skips fabric-meta',
      () async {
        modrinth.registerVersion(
          slug: 'sodium',
          versionNumber: '0.6.0',
          loader: 'fabric',
        );
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc_version: 1.21.1
mods:
  sodium: ^0.6.0
''');

        final env = {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
          'GITRINTH_CACHE': cacheDir.path,
        };
        await runCli(['-C', packDir.path, 'get'], environment: env);
        await runCli(['-C', packDir.path, 'get'], environment: env);
        // First get validates against upstream (no lock yet); second get
        // hits the lock fast-path and skips fabric-meta entirely.
        expect(modrinth.requestCounts['/fabric/v2/versions/loader'], 1);
      },
    );

    test('fabric:stable always re-resolves on each get', () async {
      modrinth.registerVersion(
        slug: 'sodium',
        versionNumber: '0.6.0',
        loader: 'fabric',
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:stable"
mc_version: 1.21.1
mods:
  sodium: ^0.6.0
''');

      final env = {
        'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
        'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
        'GITRINTH_CACHE': cacheDir.path,
      };
      await runCli(['-C', packDir.path, 'get'], environment: env);
      await runCli(['-C', packDir.path, 'get'], environment: env);
      // `:stable` is by design a drift target — both runs hit the meta
      // endpoint.
      expect(modrinth.requestCounts['/fabric/v2/versions/loader'], 2);
    });

    test(
      'neoforge:stable resolves against the neoforged maven JSON API',
      () async {
        modrinth.neoforgeVersionsBody = {
          'isSnapshot': false,
          'versions': ['21.1.50', '21.1.228'],
        };
        modrinth.registerVersion(
          slug: 'jei',
          versionNumber: '1.0.0',
          loader: 'neoforge',
        );
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:stable"
mc_version: 1.21.1
mods:
  jei: ^1.0.0
''');

        final out = await runCli(
          ['-C', packDir.path, 'get'],
          environment: {
            'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
            'GITRINTH_NEOFORGE_VERSIONS_URL': modrinth.neoforgeVersionsUrl,
            'GITRINTH_CACHE': cacheDir.path,
          },
        );
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final lockText = File(
          p.join(packDir.path, 'mods.lock'),
        ).readAsStringSync();
        expect(lockText, contains('mods: "neoforge:21.1.228"'));
      },
    );

    test(
      'concrete forge tag changed in mods.yaml re-validates against upstream',
      () async {
        modrinth.forgeVersions = {
          '1.20.1': ['1.20.1-47.2.0', '1.20.1-47.4.10'],
        };
        modrinth.registerVersion(
          slug: 'jei',
          versionNumber: '1.0.0',
          loader: 'forge',
          gameVersion: '1.20.1',
        );

        final env = {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_FORGE_VERSIONS_URL': modrinth.forgeVersionsUrl,
          'GITRINTH_FORGE_PROMOTIONS_URL': modrinth.forgePromotionsUrl,
          'GITRINTH_CACHE': cacheDir.path,
        };

        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "forge:47.2.0"
mc_version: 1.20.1
mods:
  jei: ^1.0.0
''');
        final first = await runCli([
          '-C',
          packDir.path,
          'get',
        ], environment: env);
        expect(first.exitCode, 0, reason: '${first.stderr}\n${first.stdout}');

        // User now changes the pin; we should re-validate and lock the new build.
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "forge:47.4.10"
mc_version: 1.20.1
mods:
  jei: ^1.0.0
''');
        final second = await runCli([
          '-C',
          packDir.path,
          'get',
        ], environment: env);
        expect(
          second.exitCode,
          0,
          reason: '${second.stderr}\n${second.stdout}',
        );
        final lockText = File(
          p.join(packDir.path, 'mods.lock'),
        ).readAsStringSync();
        expect(lockText, contains('mods: "forge:47.4.10"'));
      },
    );

    test(
      'concrete tag with --offline skips validation, warns when pin diverges',
      () async {
        modrinth.registerVersion(
          slug: 'sodium',
          versionNumber: '0.6.0',
          loader: 'fabric',
        );

        final env = {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
          'GITRINTH_CACHE': cacheDir.path,
        };

        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.17.3"
mc_version: 1.21.1
mods:
  sodium: ^0.6.0
''');
        // Warm up cache + lock with the original pin.
        final warm = await runCli([
          '-C',
          packDir.path,
          'get',
        ], environment: env);
        expect(warm.exitCode, 0, reason: '${warm.stderr}\n${warm.stdout}');

        // Change pin, run offline. We should not hit fabric-meta, the new pin
        // should be accepted as-is, and stderr should warn about the divergence.
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "fabric:0.99.99-unvalidated"
mc_version: 1.21.1
mods:
  sodium: ^0.6.0
''');
        final hits = modrinth.requestCounts['/fabric/v2/versions/loader'] ?? 0;
        final out = await runCli([
          '-C',
          packDir.path,
          'get',
          '--offline',
        ], environment: env);
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        expect(modrinth.requestCounts['/fabric/v2/versions/loader'], hits);
        expect(out.stderr, contains('unvalidated loader pin'));
        final lockText = File(
          p.join(packDir.path, 'mods.lock'),
        ).readAsStringSync();
        expect(lockText, contains('mods: "fabric:0.99.99-unvalidated"'));
      },
    );
  });

  test('lock includes sha1 alongside sha512 from Modrinth', () async {
    modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');
    // Inject an explicit sha1 into the canned response for jei-1.0.0.
    final entry = modrinth.versions['jei']!.first;
    final files = (entry['files'] as List).cast<Map<String, dynamic>>();
    final hashes = (files.first['hashes'] as Map<String, dynamic>);
    hashes['sha1'] = 'cafef00d';

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
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
    final lockText = File(p.join(packDir.path, 'mods.lock')).readAsStringSync();
    expect(lockText, contains('sha1: cafef00d'));
  });

  test(
    'entry accepts-mc widens game_versions query and lock records tagged mc',
    () async {
      modrinth.registerVersion(
        slug: 'appleskin',
        versionNumber: '3.0.9',
        gameVersion: '1.21',
      );

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts_mc: [1.21]
''');

      final out = await runCli(
        ['-C', packDir.path, 'get'],
        environment: {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_CACHE': cacheDir.path,
        },
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final q = modrinth.lastVersionQuery['appleskin'];
      expect(q, isNotNull);
      expect(q!['game_versions'], '["1.21.1","1.21"]');

      final lockText = File(
        p.join(packDir.path, 'mods.lock'),
      ).readAsStringSync();
      expect(lockText, contains('appleskin:'));
      expect(lockText, contains('game_versions: ["1.21"]'));
      expect(lockText, contains('accepts_mc: ["1.21"]'));
    },
  );

  test(
    'lock mirrors accepts-mc as a separate field when the user sets it',
    () async {
      modrinth.registerVersion(
        slug: 'appleskin',
        versionNumber: '3.0.9',
        gameVersion: '1.21.1',
      );
      // Modrinth tagged this file for both 1.21.1 and 1.21; game-versions
      // should record the full API tag list, while accepts-mc is mirrored
      // verbatim from mods.yaml as a separate field.
      (modrinth.versions['appleskin']!.first['game_versions'] as List)
        ..clear()
        ..addAll(<String>['1.21', '1.21.1']);

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts_mc: [1.21]
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
      expect(lockText, contains('game_versions: ["1.21", 1.21.1]'));
      expect(lockText, contains('accepts_mc: ["1.21"]'));
    },
  );

  test('lock omits accepts-mc when the user did not set it', () async {
    modrinth.registerVersion(
      slug: 'appleskin',
      versionNumber: '3.0.9',
      gameVersion: '1.21.1',
    );
    (modrinth.versions['appleskin']!.first['game_versions'] as List)
      ..clear()
      ..addAll(<String>['1.21', '1.21.1', '1.21.2']);

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  appleskin: ^3.0.9
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
    expect(lockText, isNot(contains('accepts_mc:')));
  });

  // Regression: a long-form entry with `version:` set to a channel
  // token (`release` / `beta` / `alpha`) used to be parsed as an exact
  // version constraint string. parseConstraint then routed it through
  // the best-effort fallback to a sentinel `Version("0.0.0-beta")`,
  // and the resolver reported `no version satisfies 0.0.0-beta on
  // channel alpha (saw N candidates)` against every real version.
  // The schema and short-form path treat the token as a channel
  // declaration; the long-form parser should match.
  test(
    'long-form `version: beta` resolves like the short form (channel beta)',
    () async {
      modrinth.registerVersion(
        slug: 'distanthorizons',
        versionNumber: '2.3.0',
        versionType: 'release',
      );
      final betaId = modrinth.registerVersion(
        slug: 'distanthorizons',
        versionNumber: '3.0.1-b',
        versionType: 'beta',
      );

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  distanthorizons:
    version: beta
    client: optional
    server: optional
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
      expect(lockText, contains('distanthorizons:'));
      // Channel `beta` admits both `release` and `beta` versions; the
      // higher version (3.0.1-b, the beta) wins under semver ordering.
      expect(lockText, contains('version: 3.0.1-b'));
      expect(lockText, contains('version_id: $betaId'));
      expect(lockText, contains('client: optional'));
      expect(lockText, contains('server: optional'));
    },
  );

  test(
    'persists per-version dependencies to the cache as version.json',
    () async {
      // Mirrors dart pub's "graph in cache, not lock" architecture:
      // mods.lock no longer carries forward edges — they live next to
      // each cached jar. `gitrinth upgrade --unlock-transitive` reads
      // these files to walk the dep graph.
      modrinth.registerVersion(slug: 'flywheel', versionNumber: '1.0.0');
      modrinth.registerVersion(
        slug: 'create',
        versionNumber: '6.0.10',
        requiredDeps: ['flywheel'],
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  create: ^6.0.10
''');

      final out = await runCli(
        ['-C', packDir.path, 'get'],
        environment: {
          'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
          'GITRINTH_CACHE': cacheDir.path,
        },
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final hostSeg = GitrinthCache.hostCacheSegment(modrinth.baseUrl);
      final metadataPath = p.join(
        cacheDir.path,
        'modrinth',
        hostSeg,
        'create_ID',
        'create_6_0_10',
        'version.json',
      );
      expect(File(metadataPath).existsSync(), isTrue);
      final body =
          jsonDecode(File(metadataPath).readAsStringSync())
              as Map<String, dynamic>;
      final deps = body['dependencies'] as List;
      expect(deps, hasLength(1));
      final dep = deps.first as Map<String, dynamic>;
      expect(dep['project_id'], 'flywheel_ID');
      expect(dep['dependency_type'], 'required');

      // mods.lock no longer carries forward edges.
      final lockText = File(
        p.join(packDir.path, 'mods.lock'),
      ).readAsStringSync();
      expect(lockText, isNot(contains('dependencies:')));
    },
  );
}
