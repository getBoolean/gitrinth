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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_upgrade_offline_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
    cacheDir = Directory(p.join(tempRoot.path, 'cache'))..createSync();
    modrinth = FakeModrinth();
    await modrinth.start();
  });

  tearDown(() async {
    try {
      await modrinth.stop();
    } on Object {
      // already stopped — fine
    }
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Map<String, String> envWith() => {
    'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
    'GITRINTH_CACHE': cacheDir.path,
  };

  test('upgrade --offline prints the dart-pub-style warning', () async {
    final jarBytes = Uint8List.fromList(List.generate(64, (i) => i & 0xff));
    final sha = modrinth.addArtifact('jei', 'jei-1.0.0.jar', jarBytes);
    modrinth.projects['jei'] = {
      'id': 'JEI_ID',
      'slug': 'jei',
      'title': 'JEI',
      'project_type': 'mod',
    };
    modrinth.versions['jei'] = [
      {
        'id': 'JEI_V1',
        'project_id': 'JEI_ID',
        'version_number': '1.0.0',
        'files': [
          {
            'url': '${modrinth.downloadBaseUrl}/jei/jei-1.0.0.jar',
            'filename': 'jei-1.0.0.jar',
            'hashes': {'sha512': sha},
            'size': jarBytes.length,
            'primary': true,
          },
        ],
        'dependencies': [],
        'loaders': ['neoforge'],
        'game_versions': ['1.21.1'],
      },
    ];

    File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync('''
slug: testpack
name: TestPack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  jei: ^1.0.0
''');

    // Warm the cache.
    final warm = await runCli([
      '-C',
      packDir.path,
      'get',
    ], environment: envWith());
    expect(warm.exitCode, 0, reason: warm.stderr);

    final out = await runCli([
      '-C',
      packDir.path,
      'upgrade',
      '--offline',
    ], environment: envWith());
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(
      out.stderr,
      contains(
        'Upgrading when offline may not update you to the latest '
        'versions of your dependencies.',
      ),
    );
  });
}
