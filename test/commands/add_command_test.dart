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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_add_');
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

  Map<String, String> env() => {
    'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
    'GITRINTH_CACHE': cacheDir.path,
  };

  String readYaml() =>
      File(p.join(packDir.path, 'mods.yaml')).readAsStringSync();

  test('slug@release → shorthand `slug: release` under mods', () async {
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '1.0.0',
      versionType: 'release',
    );
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: ^1.0.0
''');
    modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'sodium@release',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

    final yaml = readYaml();
    expect(yaml, contains('sodium: release'));
    expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isTrue);
  });

  test('slug (no constraint) caret-pins the newest release version', () async {
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '0.6.1',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '0.6.2',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '0.7.0-beta',
      versionType: 'beta',
    );

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'sodium',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), contains('sodium: ^0.6.2'));
  });

  test('slug (no constraint) strips build metadata from the caret', () async {
    modrinth.registerVersion(
      slug: 'create',
      versionNumber: '6.0.10+mc1.21.1',
      versionType: 'release',
    );

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'create',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), contains('create: ^6.0.10'));
    expect(readYaml(), isNot(contains('^6.0.10+')));
  });

  test('slug --exact retains build metadata inside the caret', () async {
    modrinth.registerVersion(
      slug: 'create',
      versionNumber: '6.0.10+mc1.21.1',
      versionType: 'release',
    );

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'create',
      '--exact',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), contains('create: ^6.0.10+mc1.21.1'));
  });

  test('--exact with explicit @constraint is a UsageError', () async {
    modrinth.registerVersion(slug: 'create', versionNumber: '6.0.10');

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'create@^6.0.10',
      '--exact',
    ], environment: env());
    expect(out.exitCode, 64);
    expect(out.stderr, contains('--exact has no effect'));
  });

  test('slug@^x.y.z writes the explicit caret constraint', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.27.0.340',
      versionType: 'release',
    );

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'jei@^19.27.0.340',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), contains('jei: ^19.27.0.340'));
  });

  test(
    'URL form resolves to the same slug + infers section from project_type',
    () async {
      modrinth.registerVersion(
        slug: 'terralith',
        versionNumber: '2.5.8',
        versionType: 'release',
        loader: 'datapack',
      );
      // Override project_type to 'mod' (Terralith-shape) but loaders=[datapack].
      modrinth.projects['terralith']!['project_type'] = 'mod';

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'https://modrinth.com/datapack/terralith@^2.5.8',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final yaml = readYaml();
      expect(yaml, contains('data_packs:'));
      expect(yaml, contains('terralith: ^2.5.8'));
      expect(yaml, isNot(contains('mods:\n  terralith')));
    },
  );

  test(
    'resourcepack project lands under resource_packs with minecraft loader filter',
    () async {
      modrinth.registerVersion(
        slug: 'faithful-32x',
        versionNumber: '1.21.0',
        versionType: 'release',
        loader: 'minecraft',
      );
      modrinth.projects['faithful-32x']!['project_type'] = 'resourcepack';

      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'faithful-32x',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final yaml = readYaml();
      expect(yaml, contains('resource_packs:'));
      expect(yaml, contains('faithful-32x: ^1.21.0'));
    },
  );

  test('datapack-loader mod routes to data_packs (terralith case)', () async {
    modrinth.registerVersion(
      slug: 'terralith',
      versionNumber: '2.5.8',
      versionType: 'release',
      loader: 'datapack',
    );
    // Project type 'mod' + loaders [datapack] → data_packs section.
    modrinth.projects['terralith']!['project_type'] = 'mod';

    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'terralith',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, contains('data_packs:'));
    expect(yaml, contains('terralith: ^2.5.8'));
  });

  test(
    'duplicate slug anywhere in mods.yaml exits 1 with a helpful message',
    () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  sodium: release
''');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'sodium@release',
      ], environment: env());
      expect(out.exitCode, 1, reason: out.stderr);
      expect(out.stderr, contains("'sodium'"));
      expect(out.stderr, contains('already in mods.yaml'));
    },
  );

  test('--dry-run does not write mods.yaml or mods.lock', () async {
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '1.0.0',
      versionType: 'release',
    );

    final before = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''';
    await writeManifest(before);

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      '--dry-run',
      'sodium@release',
    ], environment: env());
    expect(out.exitCode, 0, reason: out.stderr);
    // File must be unchanged.
    expect(readYaml(), before);
    expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isFalse);
  });

  test(
    '--url emits long-form with `url:` under mods (jar extension)',
    () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

      // Serve a single jar so the download succeeds.
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      modrinth.addArtifact('custom', 'custom.jar', bytes);
      final jarUrl = '${modrinth.downloadBaseUrl}/custom/custom.jar';

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'custom',
        '--url',
        jarUrl,
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final yaml = readYaml();
      expect(yaml, contains('custom:'));
      expect(yaml, contains('url: $jarUrl'));
    },
  );

  test('--path emits long-form with `path:`, infers mods for .jar', () async {
    // Create a local .jar so the downloader's path existence check passes.
    final jar = File(p.join(packDir.path, 'mods', 'custom.jar'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'custom',
      '--path',
      p.relative(jar.path, from: packDir.path).replaceAll(r'\', '/'),
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, contains('custom:'));
    expect(yaml, contains('path:'));
    expect(yaml, contains('custom.jar'));
  });

  test(
    '--path with ambiguous .zip filename fails with ValidationError',
    () async {
      final zip = File(p.join(packDir.path, 'packs', 'mystery.zip'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'mystery',
        '--path',
        p.relative(zip.path, from: packDir.path).replaceAll(r'\', '/'),
      ], environment: env());
      expect(out.exitCode, 2, reason: out.stderr);
      expect(out.stderr, contains('cannot infer section'));
    },
  );

  test('caret constraint on an unparseable base fails with ValidationError '
      '(exit 2)', () async {
    // Exact pins accept arbitrary strings (some Modrinth versions
    // aren't semver-shaped) so a `sodium@not-a-version` pin is a valid
    // — if ultimately unmatchable — constraint. Carets, on the other
    // hand, require a semver-shaped base, so `^not-a-version` is a
    // true syntax error.
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '1.0.0',
      versionType: 'release',
    );
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'sodium@^not-a-version',
    ], environment: env());
    expect(out.exitCode, 2, reason: out.stderr);
    expect(out.stderr, contains('Invalid version constraint'));
  });

  test(
    'unknown slug yields the ModrinthErrorInterceptor not-found message',
    () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'does-not-exist',
      ], environment: env());
      expect(out.exitCode, 1, reason: out.stderr);
      expect(out.stderr, contains('not found'));
      expect(out.stderr, contains('does-not-exist'));
    },
  );

  test('preserves comments on surrounding lines', () async {
    modrinth.registerVersion(
      slug: 'sodium',
      versionNumber: '1.0.0',
      versionType: 'release',
    );
    final before = '''
# top-of-file comment
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  # comment above jei
  jei: ^1.0.0 # inline comment on jei
''';
    await writeManifest(before);
    modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');

    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'sodium@release',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, contains('# top-of-file comment'));
    expect(yaml, contains('# comment above jei'));
    expect(yaml, contains('# inline comment on jei'));
    expect(yaml, contains('sodium: release'));
  });

  test(
    'add pins the raw version when Modrinth returns a non-semver string',
    () async {
      // Some Modrinth mods publish versions like "release-2025-winter"
      // that don't parse as semver. `add` (no flags) would normally
      // write `^major.minor.patch`, but carets require a semver-shaped
      // base. Fall back to pinning the raw string verbatim.
      modrinth.registerVersion(
        slug: 'weirdmod',
        versionNumber: 'release-snapshot-xyz',
        versionType: 'release',
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'weirdmod',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final yaml = readYaml();
      expect(yaml, contains('weirdmod: release-snapshot-xyz'));
      expect(yaml, isNot(contains('^release-snapshot-xyz')));
    },
  );

  test('--env=client forces long form with environment key', () async {
    modrinth.registerVersion(
      slug: 'iris',
      versionNumber: '1.8.12',
      versionType: 'release',
    );
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
    final out = await runCli([
      '-C',
      packDir.path,
      'add',
      'iris',
      '--env',
      'client',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, contains('iris:'));
    expect(yaml, contains('version: ^1.8.12'));
    expect(yaml, contains('client: required'));
    expect(yaml, contains('server: unsupported'));
  });

  group('--accepts-mc', () {
    test(
      'widens Modrinth query, writes long-form entry with accepts-mc scalar',
      () async {
        modrinth.registerVersion(
          slug: 'appleskin',
          versionNumber: '3.0.9',
          versionType: 'release',
          gameVersion: '1.21',
        );
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
''');

        final out = await runCli([
          '-C',
          packDir.path,
          'add',
          'appleskin',
          '--accepts-mc',
          '1.21',
        ], environment: env());
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

        final q = modrinth.lastVersionQuery['appleskin'];
        expect(q!['game_versions'], '["1.21.1","1.21"]');

        final yaml = readYaml();
        expect(yaml, contains('appleskin:'));
        expect(yaml, contains('version: ^3.0.9'));
        // yaml_edit quotes numeric-looking string scalars to preserve
        // string type on round-trip.
        expect(yaml, contains(RegExp(r'''accepts-mc:\s*['"]?1\.21['"]?''')));
      },
    );

    test('multiple values written as a list', () async {
      modrinth.registerVersion(
        slug: 'appleskin',
        versionNumber: '3.0.9',
        versionType: 'release',
        gameVersion: '1.21',
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
''');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'appleskin',
        '--accepts-mc=1.21',
        '--accepts-mc=1.20.1',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final q = modrinth.lastVersionQuery['appleskin'];
      expect(q!['game_versions'], '["1.21.1","1.21","1.20.1"]');

      final yaml = readYaml();
      // yaml_edit emits the list block-style.
      expect(
        yaml,
        contains(
          RegExp(
            r'''accepts-mc:\s*\n\s+-\s*['"]?1\.21['"]?\s*\n\s+-\s*['"]?1\.20\.1['"]?''',
          ),
        ),
      );
    });

    test('accepts snapshot/pre-release tags', () async {
      modrinth.registerVersion(
        slug: 'appleskin',
        versionNumber: '3.0.9',
        versionType: 'release',
        gameVersion: '24w10a',
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
''');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'appleskin',
        '--accepts-mc',
        '24w10a',
        '--accepts-mc',
        '1.21-pre1',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

      final q = modrinth.lastVersionQuery['appleskin'];
      expect(q!['game_versions'], '["1.21.1","24w10a","1.21-pre1"]');
    });

    test('malformed version rejected with helpful error', () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
''');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'appleskin',
        '--accepts-mc',
        '1.21 snapshot',
      ], environment: env());
      expect(out.exitCode, isNot(0));
      expect(out.stderr, contains('1.21 snapshot'));
    });

    test('--accepts-mc is mutually exclusive with --url', () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
''');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'custom',
        '--url',
        'https://example.com/x.jar',
        '--accepts-mc',
        '1.21',
      ], environment: env());
      expect(out.exitCode, isNot(0));
      expect(out.stderr, contains('--accepts-mc'));
    });
  });

  group('--pin', () {
    test('writes the resolved version as bare semver (no caret)', () async {
      modrinth.registerVersion(
        slug: 'sodium',
        versionNumber: '0.6.2',
        versionType: 'release',
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'sodium',
        '--pin',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(readYaml(), contains('sodium: 0.6.2'));
      expect(readYaml(), isNot(contains('^0.6.2')));
    });

    test('strips build metadata from the resolved version', () async {
      modrinth.registerVersion(
        slug: 'create',
        versionNumber: '6.0.10+mc1.21.1',
        versionType: 'release',
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'create',
        '--pin',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(readYaml(), contains('create: 6.0.10'));
      expect(readYaml(), isNot(contains('mc1.21.1')));
    });

    test('--pin and --exact are mutually exclusive', () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'sodium',
        '--pin',
        '--exact',
      ], environment: env());
      expect(out.exitCode, 64);
      expect(out.stderr, contains('--pin and --exact'));
    });

    test('--pin is rejected with --url', () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'custom',
        '--url',
        'https://example.com/x.jar',
        '--pin',
      ], environment: env());
      expect(out.exitCode, 64);
      expect(out.stderr, contains('--pin'));
    });

    test('--pin with an explicit @constraint is a UsageError', () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'sodium@^0.6.0',
        '--pin',
      ], environment: env());
      expect(out.exitCode, 64);
      expect(out.stderr, contains('--pin has no effect'));
    });
  });

  group('--type', () {
    test('--type resourcepack routes a --url .zip to resource_packs', () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');

      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      modrinth.addArtifact('faithful', 'faithful.zip', bytes);
      final zipUrl = '${modrinth.downloadBaseUrl}/faithful/faithful.zip';

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'faithful',
        '--url',
        zipUrl,
        '--type',
        'resourcepack',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final yaml = readYaml();
      expect(yaml, contains('resource_packs:'));
      expect(yaml, contains('faithful:'));
      expect(yaml, contains('url: $zipUrl'));
    });

    test('--url .zip without --type still errors, mentions --type', () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'faithful',
        '--url',
        'https://example.com/faithful.zip',
      ], environment: env());
      expect(out.exitCode, isNot(0));
      expect(out.stderr, contains('--type'));
    });

    test(
      '--type matching the inferred section leaves the entry where inference '
      'would put it anyway',
      () async {
        modrinth.registerVersion(
          slug: 'sodium',
          versionNumber: '0.6.2',
          versionType: 'release',
        );
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
''');
        final out = await runCli([
          '-C',
          packDir.path,
          'add',
          'sodium',
          '--type',
          'mod',
        ], environment: env());
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        expect(out.stderr, isNot(contains('overrides the inferred section')));
        final yaml = readYaml();
        expect(yaml, contains('mods:'));
        expect(yaml, contains('sodium:'));
      },
    );
  });

  group('incompatibility refusal', () {
    test('refuses to add when the picked version declares an existing user mod '
        'as incompatible', () async {
      modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');
      // `rei` (the new mod) v1.0.0 declares `jei` as incompatible.
      modrinth.registerVersion(
        slug: 'rei',
        versionNumber: '1.0.0',
        incompatibleDeps: const ['jei'],
      );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: ^1.0.0
''');
      // Lock jei first so the lock has its project ID.
      final get = await runCli(['-C', packDir.path, 'get'], environment: env());
      expect(get.exitCode, 0, reason: '${get.stderr}\n${get.stdout}');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'rei',
      ], environment: env());
      expect(out.exitCode, isNot(0));
      expect(out.stderr, contains('incompatible'));
      expect(out.stderr, contains('jei'));
      // Manifest unchanged.
      final yaml = readYaml();
      expect(yaml, isNot(contains('rei:')));
    });

    test('refuses to add when an existing user mod\'s locked version declares '
        'the new mod as incompatible', () async {
      // `jei` (existing) v1.0.0 declares `rei` as incompatible. Reverse
      // direction from the previous test.
      modrinth.registerVersion(
        slug: 'jei',
        versionNumber: '1.0.0',
        incompatibleDeps: const ['rei'],
      );
      modrinth.registerVersion(slug: 'rei', versionNumber: '1.0.0');
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: ^1.0.0
''');
      final get = await runCli(['-C', packDir.path, 'get'], environment: env());
      expect(get.exitCode, 0, reason: '${get.stderr}\n${get.stdout}');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'rei',
      ], environment: env());
      expect(out.exitCode, isNot(0));
      expect(out.stderr, contains('incompatible'));
      expect(out.stderr, contains('jei'));
      final yaml = readYaml();
      expect(yaml, isNot(contains('rei:')));
    });

    test('compatible add still succeeds (no false positives)', () async {
      modrinth.registerVersion(slug: 'jei', versionNumber: '1.0.0');
      modrinth.registerVersion(slug: 'rei', versionNumber: '1.0.0');
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: ^1.0.0
''');
      final get = await runCli(['-C', packDir.path, 'get'], environment: env());
      expect(get.exitCode, 0, reason: '${get.stderr}\n${get.stdout}');

      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'rei',
      ], environment: env());
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(readYaml(), contains('rei:'));
    });
  });
}
