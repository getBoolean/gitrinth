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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_remove_');
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

  test('removes a mod entry, updates mods.lock', () async {
    modrinth.registerVersion(
      slug: 'jei',
      versionNumber: '19.27.0.340',
      versionType: 'release',
    );
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
mc_version: 1.21.1
mods:
  jei: ^19.27.0.340
  sodium: release
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'remove',
      'sodium',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, isNot(contains('sodium')));
    expect(yaml, contains('jei: ^19.27.0.340'));

    final lockText = File(p.join(packDir.path, 'mods.lock')).readAsStringSync();
    expect(lockText, isNot(contains('sodium')));
    expect(lockText, contains('jei'));
  });

  test('removes a resource_packs entry', () async {
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
mc_version: 1.21.1
resource_packs:
  faithful-32x: ^1.21.0
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'remove',
      'faithful-32x',
    ], environment: env());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, isNot(contains('faithful-32x')));

    final lockText = File(p.join(packDir.path, 'mods.lock')).readAsStringSync();
    expect(lockText, isNot(contains('faithful-32x')));
  });

  test('unknown slug exits 1 with a helpful message', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  jei: ^19.27.0.340
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'remove',
      'nope',
    ], environment: env());
    expect(out.exitCode, 1, reason: out.stderr);
    expect(out.stderr, contains("'nope'"));
    expect(out.stderr, contains('not in mods.yaml'));
  });

  test('missing positional exits 64 (UsageError)', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'remove',
    ], environment: env());
    expect(out.exitCode, 64, reason: out.stderr);
  });

  test('slug@version exits 64 with a pointed message', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  sodium: release
''');

    final out = await runCli([
      '-C',
      packDir.path,
      'remove',
      'sodium@1.0.0',
    ], environment: env());
    expect(out.exitCode, 64, reason: out.stderr);
    expect(out.stderr, contains('@'));
  });

  test('--dry-run does not write mods.yaml or mods.lock', () async {
    final before = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
mods:
  sodium: release
''';
    await writeManifest(before);

    final out = await runCli([
      '-C',
      packDir.path,
      'remove',
      'sodium',
      '--dry-run',
    ], environment: env());
    expect(out.exitCode, 0, reason: out.stderr);
    expect(out.stdout, contains('Would remove'));
    expect(readYaml(), before);
    expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isFalse);
  });
}
