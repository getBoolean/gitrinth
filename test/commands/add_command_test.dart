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
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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
    'resourcepack project lands under resource_packs, no loader filter',
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
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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

  test(
    'invalid version constraint fails with ValidationError (exit 2)',
    () async {
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
  mods: neoforge
mc-version: 1.21.1
''');
      final out = await runCli([
        '-C',
        packDir.path,
        'add',
        'sodium@not-a-version',
      ], environment: env());
      expect(out.exitCode, 2, reason: out.stderr);
      expect(out.stderr, contains('Invalid version constraint'));
    },
  );

  test(
    'unknown slug yields the ModrinthErrorInterceptor not-found message',
    () async {
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
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
  mods: neoforge
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
  mods: neoforge
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
    expect(yaml, contains('environment: client'));
  });
}
