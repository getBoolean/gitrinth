import 'dart:io';

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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_override_');
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

  String readStandalone() =>
      File(p.join(packDir.path, 'project_overrides.yaml')).readAsStringSync();

  Future<void> baseManifest() => writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  jei: ^19.0.0
''');

  test("override <slug>@<version> writes to mods.yaml's "
      'project_overrides: section by default', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.27.0',
      versionType: 'release',
    );
    await baseManifest();

    final out = await runCli([
      '-C',
      packDir.path,
      'override',
      'jei@19.27.0',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

    final yaml = readYaml();
    expect(yaml, contains('project_overrides:'));
    expect(yaml, contains('jei: 19.27.0'));
    // mods.lock reflects the override version.
    final lockPath = p.join(packDir.path, 'mods.lock');
    expect(File(lockPath).existsSync(), isTrue);
    expect(File(lockPath).readAsStringSync(), contains('19.27.0'));
  });

  test('override --standalone writes to project_overrides.yaml, '
      'creating the file if absent', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.27.0',
      versionType: 'release',
    );
    await baseManifest();

    final out = await runCli([
      '-C',
      packDir.path,
      'override',
      'jei@19.27.0',
      '--standalone',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

    expect(
      File(p.join(packDir.path, 'project_overrides.yaml')).existsSync(),
      isTrue,
    );
    final standalone = readStandalone();
    expect(standalone, contains('project_overrides:'));
    expect(standalone, contains('jei: 19.27.0'));
    // mods.yaml is left alone.
    expect(readYaml(), isNot(contains('project_overrides:')));
  });

  test('override --standalone preserves existing entries in the '
      'standalone file', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'create',
      versionNumber: '6.0.0',
      versionType: 'release',
    );
    await baseManifest();
    File(p.join(packDir.path, 'project_overrides.yaml')).writeAsStringSync('''
project_overrides:
  create:
    version: 6.0.0
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'override',
      'jei@19.0.0',
      '--standalone',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

    final standalone = readStandalone();
    expect(standalone, contains('jei: 19.0.0'));
    expect(standalone, contains('create:'));
    expect(standalone, contains('version: 6.0.0'));
  });

  test('override <slug> with no @ picks latest release matching '
      'loader+mc', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.5.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.27.0',
      versionType: 'release',
    );
    await baseManifest();

    final out = await runCli([
      '-C',
      packDir.path,
      'override',
      'jei',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');

    final yaml = readYaml();
    // Default emits a caret on major.minor.patch (mirrors `add`).
    expect(yaml, contains('jei: ^19.27.0'));
  });

  test('override on a slug already in project_overrides errors', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.0.0',
      versionType: 'release',
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
  jei: ^19.0.0
project_overrides:
  jei:
    version: 19.0.0
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'override',
      'jei@19.0.0',
    ], environment: env());
    expect(out.exitCode, isNot(0));
    expect(
      '${out.stderr}\n${out.stdout}',
      contains('already in project_overrides'),
    );
  });

  test('override --dry-run prints the change but does not write', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.27.0',
      versionType: 'release',
    );
    await baseManifest();

    final out = await runCli([
      '-C',
      packDir.path,
      'override',
      'jei@19.27.0',
      '--dry-run',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('Would add'));
    expect(out.stdout, contains('jei'));
    expect(out.stdout, contains('19.27.0'));
    // mods.yaml unchanged.
    expect(readYaml(), isNot(contains('project_overrides:')));
    // No lock written.
    expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isFalse);
  });

  test('override does not run the incompatibility-prevention check '
      'that add applies', () async {
    // Fixture: `other` and `mod_a 1.0.0` are in mods:; we override
    // mod_a to 2.0.0, where 2.0.0 declares `other` as incompatible.
    // `add` would refuse this; `override` accepts it (the resolver
    // drops the incompatible edge because mod_a is overridden).
    modrinth.registerVersion(
      slug: 'other',
      versionNumber: '1.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'mod_a',
      versionNumber: '1.0.0',
      versionType: 'release',
    );
    modrinth.registerVersion(
      slug: 'mod_a',
      versionNumber: '2.0.0',
      versionType: 'release',
      incompatibleDeps: ['other'],
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
  other: ^1.0.0
  mod_a: ^1.0.0
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'override',
      'mod_a@2.0.0',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, contains('mod_a: 2.0.0'));
    // both `other` and `mod_a 2.0.0` end up locked despite the
    // incompatible declaration.
    final lock = File(p.join(packDir.path, 'mods.lock')).readAsStringSync();
    expect(lock, contains('mod_a'));
    expect(lock, contains('other'));
    expect(lock, contains('2.0.0'));
  });
}
