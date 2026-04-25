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
  late Map<String, String> env;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_upgrade_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
    cacheDir = Directory(p.join(tempRoot.path, 'cache'))..createSync();
    modrinth = FakeModrinth();
    await modrinth.start();
    env = {
      'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
      'GITRINTH_CACHE': cacheDir.path,
    };
  });

  tearDown(() async {
    await modrinth.stop();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<void> writeManifest(String body) async {
    File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync(body);
  }

  String readLock() =>
      File(p.join(packDir.path, 'mods.lock')).readAsStringSync();

  String readManifest() =>
      File(p.join(packDir.path, 'mods.yaml')).readAsStringSync();

  Future<CapturedOutput> runGet() =>
      runCli(['-C', packDir.path, 'get'], environment: env);

  Future<CapturedOutput> runUpgrade(List<String> extra) =>
      runCli(['-C', packDir.path, 'upgrade', ...extra], environment: env);

  test('upgrade-all bumps every mod to newest within constraint', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0')
      ..registerVersion(slug: 'b', versionNumber: '2.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
  b: ^2.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.5.0')
      ..registerVersion(slug: 'b', versionNumber: '2.7.3');

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, contains('version: 2.7.3'));
  });

  test('subset upgrade bumps only the named slug', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0')
      ..registerVersion(slug: 'b', versionNumber: '2.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
  b: ^2.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.5.0')
      ..registerVersion(slug: 'b', versionNumber: '2.7.3');

    final out = await runUpgrade(['a']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, contains('version: 2.0.0'));
    expect(lock, isNot(contains('version: 2.7.3')));
  });

  test('caret constraint respected by default (does not cross major)', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '6.5.2')
      ..registerVersion(slug: 'a', versionNumber: '7.0.0');

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 6.5.2'));
    expect(lock, isNot(contains('version: 7.0.0')));
  });

  test('--major-versions crosses caret and rewrites mods.yaml', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '7.1.0');

    final out = await runUpgrade(['--major-versions', 'a']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 7.1.0'));
    expect(readManifest(), contains('a: ^7.1.0'));
  });

  test('--major-versions skips entries already allowed by constraint', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '6.0.10')
      ..registerVersion(slug: 'a', versionNumber: '6.5.2');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['--major-versions']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 6.5.2'));
    // resolved 6.5.2 still allowed by ^6.0.10 → no rewrite.
    expect(readManifest(), contains('a: ^6.0.10'));
  });

  test('--tighten rewrites caret base after in-major bump', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '6.5.2');

    final out = await runUpgrade(['--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 6.5.2'));
    expect(readManifest(), contains('a: ^6.5.2'));
  });

  test('--tighten is a no-op for entries that did not move', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    final before = readManifest();
    final out = await runUpgrade(['--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readManifest(), before);
  });

  test('--tighten ignores non-caret constraints (channel-only)', () async {
    modrinth
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.0.0',
        versionType: 'release',
      )
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.5.0',
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
  a: release
''');
    expect((await runGet()).exitCode, 0);

    final before = readManifest();
    final out = await runUpgrade(['--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readManifest(), before);
    // Lock still picked the newest release.
    expect(readLock(), contains('version: 1.5.0'));
  });

  test('--major-versions --tighten: combined cross + in-major rewrites', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '6.0.10')
      ..registerVersion(slug: 'b', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
  b: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '7.1.0') // crosses caret
      ..registerVersion(slug: 'b', versionNumber: '1.4.0'); // in-major

    final out = await runUpgrade(['--major-versions', '--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readManifest();
    expect(yaml, contains('a: ^7.1.0'));
    expect(yaml, contains('b: ^1.4.0'));
  });

  test('--dry-run returns exit 2 and writes nothing when changes occur',
      () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '1.5.0');
    final lockBefore = readLock();
    final yamlBefore = readManifest();

    final out = await runUpgrade(['--major-versions', '--tighten', '--dry-run']);
    expect(out.exitCode, 2, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), lockBefore);
    expect(readManifest(), yamlBefore);
  });

  test('--dry-run returns exit 0 when no changes would occur', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['--dry-run']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
  });

  test('unknown slug → exit 64', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['does-not-exist']);
    expect(out.exitCode, 64, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stderr, contains('does-not-exist'));
  });

  test('url entries are skipped, not errored', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
  custom:
    url: ${modrinth.downloadBaseUrl}/a/a-1.0.0.jar
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['custom']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
  });

  test('channel floor still respected during upgrade', () async {
    modrinth
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.0.0',
        versionType: 'release',
      )
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.5.0',
        versionType: 'release',
      )
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.7.0-beta',
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
mods:
  a:
    version: ^1.0.0
    channel: release
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, isNot(contains('1.7.0-beta')));
  });

  test('optional flag preserved through upgrade', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a:
    version: ^1.0.0
    optional: true
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '1.5.0');

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, contains('optional: true'));
  });
}
