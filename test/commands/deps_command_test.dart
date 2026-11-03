import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
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

  test('reports retain same local name in separate sections', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
mc_version: 1.21.1
mods:
  same: 'path:mod.jar'
resource_packs:
  same: 'path:resource.zip'
''');
    File(p.join(packDir.path, 'mods.lock')).writeAsStringSync(
      emitModsLock(
        ModsLock(
          gitrinthVersion: '0.1.0',
          loader: const LoaderConfig(mods: ModLoader.fabric),
          mcVersion: '1.21.1',
          mods: {
            'same': const LockedEntry(
              slug: 'same',
              kind: LockedEntryKind.path,
              path: 'mod.jar',
            ),
          },
          resourcePacks: {
            'same': const LockedEntry(
              slug: 'same',
              kind: LockedEntryKind.path,
              path: 'resource.zip',
            ),
          },
        ),
      ),
    );
    final json = await runDeps(['--json']);
    expect(json.exitCode, 0, reason: json.stderr);
    final packages = (jsonDecode(json.stdout) as Map)['packages'] as List;
    expect(
      packages.map((entry) => (entry as Map)['section']),
      unorderedEquals(['mods', 'resourcePacks']),
    );
    final list = await runDeps(['--style', 'list']);
    expect(list.stdout, contains('- mods/same'));
    expect(list.stdout, contains('- resourcePacks/same'));
    expect(list.stdout, isNot(contains('mods/mods/same')));
  });

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
mc_version: 1.21.1
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
mc_version: 1.21.1
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
mc_version: 1.21.1
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
mc_version: 1.21.1
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
mc_version: 1.21.1
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
mc_version: 1.21.1
mods:
  create: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    final out = await runDeps(['flywheel']);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('transitive'));
  });
}
