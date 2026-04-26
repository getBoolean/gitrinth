import 'dart:convert';
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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_deps_');
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

  Future<CapturedOutput> runGet() =>
      runCli(['-C', packDir.path, 'get'], environment: env);

  Future<CapturedOutput> runDeps(List<String> extra) =>
      runCli(['-C', packDir.path, 'deps', ...extra], environment: env);

  test('tree style shows direct + transitive structure', () async {
    modrinth
      ..registerVersion(
        slug: 'create',
        versionNumber: '6.0.10',
        requiredDeps: ['flywheel'],
      )
      ..registerVersion(slug: 'flywheel', versionNumber: '1.0.0');
    await writeManifest('''
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
    expect((await runGet()).exitCode, 0);

    final out = await runDeps([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('pack 0.1.0'));
    expect(out.stdout, contains('direct dependencies'));
    expect(out.stdout, contains('mods/create'));
    expect(out.stdout, contains('transitive dependencies'));
    expect(out.stdout, contains('flywheel'));
  });

  test('list style flattens children one level', () async {
    modrinth
      ..registerVersion(
        slug: 'create',
        versionNumber: '6.0.10',
        requiredDeps: ['flywheel'],
      )
      ..registerVersion(slug: 'flywheel', versionNumber: '1.0.0');
    await writeManifest('''
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
    expect((await runGet()).exitCode, 0);

    final out = await runDeps(['--style', 'list']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('direct dependencies:'));
    expect(out.stdout, contains('- mods/create'));
    expect(out.stdout, contains('  - flywheel'));
    expect(out.stdout, contains('transitive dependencies:'));
  });

  test('compact style lists kid slugs in brackets', () async {
    modrinth
      ..registerVersion(
        slug: 'create',
        versionNumber: '6.0.10',
        requiredDeps: ['flywheel'],
      )
      ..registerVersion(slug: 'flywheel', versionNumber: '1.0.0');
    await writeManifest('''
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
    expect((await runGet()).exitCode, 0);

    final out = await runDeps(['--style', 'compact']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('- mods/create 6.0.10 [flywheel]'));
  });

  test('--json emits root + packages', () async {
    modrinth
      ..registerVersion(
        slug: 'create',
        versionNumber: '6.0.10',
        requiredDeps: ['flywheel'],
      )
      ..registerVersion(slug: 'flywheel', versionNumber: '1.0.0');
    await writeManifest('''
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
    expect((await runGet()).exitCode, 0);

    final out = await runDeps(['--json']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final decoded = jsonDecode(out.stdout) as Map<String, dynamic>;
    expect(decoded['root'], 'pack');
    expect(decoded['version'], '0.1.0');
    final packages = (decoded['packages'] as List).cast<Map<String, dynamic>>();
    final create = packages.firstWhere((e) => e['slug'] == 'create');
    expect(create['kind'], 'direct');
    expect(create['version'], '6.0.10');
    expect((create['dependencies'] as List), contains('flywheel'));
    final flywheel = packages.firstWhere((e) => e['slug'] == 'flywheel');
    expect(flywheel['kind'], 'transitive');
  });

  test('errors out when mods.lock is missing', () async {
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
    final out = await runDeps([]);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('mods.lock'));
  });

  test('errors out when given a transitive slug', () async {
    modrinth
      ..registerVersion(
        slug: 'create',
        versionNumber: '6.0.10',
        requiredDeps: ['flywheel'],
      )
      ..registerVersion(slug: 'flywheel', versionNumber: '1.0.0');
    await writeManifest('''
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
    expect((await runGet()).exitCode, 0);

    final out = await runDeps(['flywheel']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('transitive'));
  });
}
