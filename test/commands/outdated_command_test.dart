import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_outdated_');
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

  Future<CapturedOutput> runOutdated(List<String> extra) =>
      runCli(['-C', packDir.path, 'outdated', ...extra], environment: env);

  test('reports newly-published in-range version as upgradable', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
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
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '1.5.0');

    final out = await runOutdated([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('a'));
    expect(out.stdout, contains('1.0.0'));
    expect(out.stdout, contains('1.5.0'));
    expect(out.stdout, contains('upgradable dependency'));
  });

  test(
    'reports out-of-constraint major as latest but not upgradable',
    () async {
      modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
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
      expect((await runGet()).exitCode, 0);

      modrinth.registerVersion(slug: 'a', versionNumber: '2.0.0');

      final out = await runOutdated([]);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      // 1.0.0 is the only in-constraint version, so Upgradable == Current.
      // Latest = 2.0.0 (major bump). Should suggest --major-versions.
      expect(out.stdout, contains('2.0.0'));
      expect(out.stdout, contains('--major-versions'));
    },
  );

  test('clean lock with nothing newer says "Found no outdated mods"', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
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
    expect((await runGet()).exitCode, 0);

    final out = await runOutdated([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('Found no outdated mods.'));
  });

  test('--json emits a packages list', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
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
    expect((await runGet()).exitCode, 0);
    modrinth.registerVersion(slug: 'a', versionNumber: '1.5.0');

    final out = await runOutdated(['--json']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final decoded = jsonDecode(out.stdout) as Map<String, dynamic>;
    final packages = decoded['packages'] as List;
    final entry =
        packages.firstWhere((e) => e['slug'] == 'a') as Map<String, dynamic>;
    expect(entry['current']['version'], '1.0.0');
    expect(entry['upgradable']['version'], '1.5.0');
    expect(entry['latest']['version'], '1.5.0');
    expect(entry['kind'], 'direct');
    expect(entry['source'], 'modrinth');
    expect(entry['has_modrinth_source'], isTrue);
  });

  test('--json preserves source labels for all artifact kinds', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader:
  mods: "neoforge:21.1.50"
mods: {}
''');
    const mr = LockedModrinthSource(
      projectId: 'p',
      versionId: 'v',
      file: LockedFile(name: 'mr.jar'),
    );
    const cf = LockedCurseforgeSource(
      projectId: 42,
      fileId: 7,
      file: LockedFile(name: 'cf.jar'),
    );
    final lock = ModsLock(
      gitrinthVersion: '0.1.0',
      loader: const LoaderConfig(
        mods: ModLoader.neoforge,
        modLoaderVersion: '21.1.50',
      ),
      mcVersion: '1.21.1',
      mods: const {
        'mr': LockedEntry(
          slug: 'mr',
          kind: LockedEntryKind.resolved,
          modrinth: mr,
        ),
        'cf': LockedEntry(
          slug: 'cf',
          kind: LockedEntryKind.resolved,
          curseforge: cf,
        ),
        'dual': LockedEntry(
          slug: 'dual',
          kind: LockedEntryKind.resolved,
          modrinth: mr,
          curseforge: cf,
        ),
        'url': LockedEntry(
          slug: 'url',
          kind: LockedEntryKind.url,
          url: 'https://example.com/mod.jar',
        ),
        'path': LockedEntry(
          slug: 'path',
          kind: LockedEntryKind.path,
          path: './mod.jar',
        ),
      },
    );
    File(
      p.join(packDir.path, 'mods.lock'),
    ).writeAsStringSync(emitModsLock(lock));
    final out = await runOutdated(['--json', '--offline']);
    expect(out.exitCode, 0, reason: out.stderr);
    final rows = (jsonDecode(out.stdout) as Map)['packages'] as List;
    expect(
      {for (final row in rows) row['slug']: row['source']},
      {
        'mr': 'modrinth',
        'cf': 'curseforge',
        'dual': 'modrinth',
        'url': 'url',
        'path': 'path',
      },
    );
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
    final out = await runOutdated([]);
    expect(out.exitCode, isNot(0));
    expect(out.stderr, contains('mods.lock'));
  });
}
