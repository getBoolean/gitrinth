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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_downgrade_');
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

  Future<CapturedOutput> runGet() =>
      runCli(['-C', packDir.path, 'get'], environment: env);

  Future<CapturedOutput> runDowngrade(List<String> extra) =>
      runCli(['-C', packDir.path, 'downgrade', ...extra], environment: env);

  test('downgrade picks oldest version within constraint', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0')
      ..registerVersion(slug: 'a', versionNumber: '1.5.0')
      ..registerVersion(slug: 'a', versionNumber: '1.7.2');
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
    // get picks newest within constraint.
    expect(readLock(), contains('version: 1.7.2'));

    final out = await runDowngrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 1.0.0'));
    expect(readLock(), isNot(contains('version: 1.7.2')));
  });

  test('downgrade <slug> only walks back the named entry', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0')
      ..registerVersion(slug: 'a', versionNumber: '1.5.0')
      ..registerVersion(slug: 'b', versionNumber: '2.0.0')
      ..registerVersion(slug: 'b', versionNumber: '2.7.3');
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
    expect(readLock(), contains('version: 1.5.0'));
    expect(readLock(), contains('version: 2.7.3'));

    final out = await runDowngrade(['a']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 1.0.0'));
    // b stayed at its previously-locked version.
    expect(readLock(), contains('version: 2.7.3'));
  });

  test('downgrade --dry-run reports diff but does not write lock', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0')
      ..registerVersion(slug: 'a', versionNumber: '1.5.0');
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
    expect(readLock(), contains('version: 1.5.0'));

    final out = await runDowngrade(['--dry-run']);
    // exitValidationError when the lock would change under --dry-run,
    // mirroring `get --dry-run`.
    expect(out.exitCode, isNot(0), reason: out.stdout);
    // Lock not rewritten.
    expect(readLock(), contains('version: 1.5.0'));
  });

  test('unknown slug surfaces a usage error', () async {
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

    final out = await runDowngrade(['ghost']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('unknown entry'));
  });
}
