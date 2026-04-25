import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';

void main() {
  late Directory tempRoot;
  late Directory packDir;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_pin_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  void writeManifest(String body) {
    File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync(body);
  }

  void writeLock(String body) {
    File(p.join(packDir.path, 'mods.lock')).writeAsStringSync(body);
  }

  String readYaml() =>
      File(p.join(packDir.path, 'mods.yaml')).readAsStringSync();

  const baseManifest = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: ^19.27.0.340
''';

  const baseLock = '''
gitrinth-version: 0.1.0
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei:
    source: modrinth
    version: "19.27.0.340"
    project-id: jei-id
    version-id: jei-version
    file:
      name: jei.jar
      url: https://example.com/jei.jar
      sha1: "0000000000000000000000000000000000000000"
      size: 100
    env: both
resource_packs: {}
data_packs: {}
shaders: {}
''';

  test(
    'pin preserves the 4th-segment build number while dropping the caret',
    () async {
      // baseLock has version "19.27.0.340" (4-segment). bareVersionForPin
      // encodes that as "19.27.0+340" (numeric build metadata kept).
      writeManifest(baseManifest);
      writeLock(baseLock);

      final out = await runCli(['-C', packDir.path, 'pin', 'jei']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(readYaml(), contains('jei: 19.27.0+340'));
      expect(readYaml(), isNot(contains('^19.27.0')));
    },
  );

  test('pin rewrites long-form `version:` only', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei:
    version: ^19.27.0.340
    client: required
    server: unsupported
''');
    writeLock(baseLock);

    final out = await runCli(['-C', packDir.path, 'pin', 'jei']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, contains('version: 19.27.0+340'));
    expect(yaml, contains('client: required'));
    expect(yaml, contains('server: unsupported'));
  });

  test('pin strips build metadata from the locked version', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  create: ^6.0.10
''');
    writeLock('''
gitrinth-version: 0.1.0
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  create:
    source: modrinth
    version: "6.0.10+mc1.21.1"
    project-id: c
    version-id: v
    file:
      name: create.jar
      url: https://example.com/create.jar
      sha1: "0000000000000000000000000000000000000000"
      size: 1
    env: both
resource_packs: {}
data_packs: {}
shaders: {}
''');

    final out = await runCli(['-C', packDir.path, 'pin', 'create']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), contains('create: 6.0.10'));
    expect(readYaml(), isNot(contains('mc1.21.1')));
  });

  test('pin --dry-run prints the edit without writing', () async {
    writeManifest(baseManifest);
    writeLock(baseLock);

    final before = readYaml();
    final out = await runCli(['-C', packDir.path, 'pin', 'jei', '--dry-run']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), before);
    expect(out.stdout, contains('Would pin'));
  });

  test('pin errors when mods.lock is missing', () async {
    writeManifest(baseManifest);
    final out = await runCli(['-C', packDir.path, 'pin', 'jei']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('mods.lock not found'));
  });

  test('pin errors for non-Modrinth (url) source', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  custom:
    url: https://example.com/custom.jar
''');
    writeLock('''
gitrinth-version: 0.1.0
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  custom:
    source: url
    file:
      name: custom.jar
      url: https://example.com/custom.jar
      sha1: "0000000000000000000000000000000000000000"
      size: 1
    env: both
resource_packs: {}
data_packs: {}
shaders: {}
''');
    final out = await runCli(['-C', packDir.path, 'pin', 'custom']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('only Modrinth'));
  });

  test(
    'pin errors when slug exists in multiple sections, points to --type',
    () async {
      writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  terralith: ^2.5.8
data_packs:
  terralith: ^2.5.8
''');
      writeLock('''
gitrinth-version: 0.1.0
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  terralith:
    source: modrinth
    version: "2.5.8"
    project-id: t
    version-id: v
    file:
      name: t.jar
      url: https://example.com/t.jar
      sha1: "0000000000000000000000000000000000000000"
      size: 1
    env: both
resource_packs: {}
data_packs:
  terralith:
    source: modrinth
    version: "2.5.8"
    project-id: t
    version-id: v
    file:
      name: t.zip
      url: https://example.com/t.zip
      sha1: "0000000000000000000000000000000000000000"
      size: 1
    env: both
shaders: {}
''');

      final ambiguous = await runCli(['-C', packDir.path, 'pin', 'terralith']);
      expect(ambiguous.exitCode, isNot(0));
      expect(ambiguous.stderr, contains('--type'));

      final disambiguated = await runCli([
        '-C',
        packDir.path,
        'pin',
        'terralith',
        '--type',
        'datapack',
      ]);
      expect(
        disambiguated.exitCode,
        0,
        reason: '${disambiguated.stderr}\n${disambiguated.stdout}',
      );
      final yaml = readYaml();
      // mods: line still has caret; data_packs: line is pinned.
      final lines = yaml.split('\n');
      final modsIdx = lines.indexWhere((l) => l.trim() == 'mods:');
      final dataIdx = lines.indexWhere((l) => l.trim() == 'data_packs:');
      expect(
        lines.sublist(modsIdx + 1, dataIdx).join('\n'),
        contains('terralith: ^2.5.8'),
      );
      expect(
        lines.sublist(dataIdx + 1).join('\n'),
        contains('terralith: 2.5.8'),
      );
    },
  );

  test('pin errors when slug is not in mods.yaml', () async {
    writeManifest(baseManifest);
    writeLock(baseLock);
    final out = await runCli(['-C', packDir.path, 'pin', 'missing']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains("'missing' is not in mods.yaml"));
  });
}
