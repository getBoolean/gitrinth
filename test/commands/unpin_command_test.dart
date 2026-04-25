import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';

void main() {
  late Directory tempRoot;
  late Directory packDir;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_unpin_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  void writeManifest(String body) {
    File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync(body);
  }

  String readYaml() =>
      File(p.join(packDir.path, 'mods.yaml')).readAsStringSync();

  test('unpin adds a caret to a bare-semver short-form scalar', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: 19.27.0.340
''');
    final out = await runCli(['-C', packDir.path, 'unpin', 'jei']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    // Per spec: the 4-segment version normalises to major.minor.patch+build,
    // so the caret keeps the numeric build metadata.
    expect(readYaml(), contains('jei: ^19.27.0+340'));
  });

  test('unpin adds a caret to a long-form `version:` value', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  iris:
    version: 1.8.12
    client: required
    server: unsupported
''');
    final out = await runCli(['-C', packDir.path, 'unpin', 'iris']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readYaml();
    expect(yaml, contains('version: ^1.8.12'));
    expect(yaml, contains('client: required'));
    expect(yaml, contains('server: unsupported'));
  });

  test('unpin errors when the constraint already has a caret', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: ^19.27.0.340
''');
    final out = await runCli(['-C', packDir.path, 'unpin', 'jei']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('not pinned'));
  });

  test('unpin errors when the constraint is a channel token', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: release
''');
    final out = await runCli(['-C', packDir.path, 'unpin', 'jei']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('channel token'));
  });

  test('unpin strips build metadata when adding caret', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  create: 6.0.10+mc1.21.1
''');
    final out = await runCli(['-C', packDir.path, 'unpin', 'create']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), contains('create: ^6.0.10'));
    expect(readYaml(), isNot(contains('^6.0.10+')));
  });

  test('unpin --dry-run does not modify mods.yaml', () async {
    writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: 19.27.0.340
''');
    final before = readYaml();
    final out = await runCli(['-C', packDir.path, 'unpin', 'jei', '--dry-run']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readYaml(), before);
    expect(out.stdout, contains('Would unpin'));
  });

  test(
    'unpin --type disambiguates when slug is in multiple sections',
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
  terralith: 2.5.8
data_packs:
  terralith: 2.5.8
''');
      final ambiguous = await runCli([
        '-C',
        packDir.path,
        'unpin',
        'terralith',
      ]);
      expect(ambiguous.exitCode, isNot(0));
      expect(ambiguous.stderr, contains('--type'));

      final ok = await runCli([
        '-C',
        packDir.path,
        'unpin',
        'terralith',
        '--type',
        'mod',
      ]);
      expect(ok.exitCode, 0, reason: '${ok.stderr}\n${ok.stdout}');

      final yaml = readYaml();
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
}
