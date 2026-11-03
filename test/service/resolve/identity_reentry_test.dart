import 'dart:io';

import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/capture.dart';
import '../../helpers/fake_modrinth.dart';

void main() {
  late Directory root;
  late FakeModrinth defaultApi;
  late FakeModrinth hostedApi;
  late Map<String, String> environment;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('identity_reentry_');
    defaultApi = FakeModrinth();
    hostedApi = FakeModrinth();
    await defaultApi.start();
    await hostedApi.start();
    for (final api in [defaultApi, hostedApi]) {
      api.registerVersion(
        slug: 'anchor',
        versionNumber: '1.0.0',
        requiredDeps: ['library'],
      );
      api.registerVersion(slug: 'library', versionNumber: '2.0.0');
    }
    environment = {
      'GITRINTH_CACHE': p.join(root.path, 'cache'),
      'GITRINTH_MODRINTH_URL': defaultApi.baseUrl,
      'GITRINTH_NEOFORGE_VERSIONS_URL': defaultApi.neoforgeVersionsUrl,
    };
  });
  tearDown(() async {
    await defaultApi.stop();
    await hostedApi.stop();
    root.deleteSync(recursive: true);
  });
  void manifest(String entries) =>
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
modrinth_host: ${hostedApi.baseUrl}
loader:
  mods: "neoforge:21.1.50"
mods:
  default-anchor:
    modrinth: anchor
    modrinth_host: ${defaultApi.baseUrl}
$entries
''');
  Future<CapturedOutput> get() =>
      runCli(['-C', root.path, 'get'], environment: environment);

  test(
    'second online get reuses host-qualified lock entries by remote project ID',
    () async {
      manifest('  hosted-anchor: {modrinth: anchor}');
      final first = await get();
      expect(first.exitCode, 0, reason: '${first.stdout}\n${first.stderr}');
      final lock = File(p.join(root.path, 'mods.lock'));
      final before = lock.readAsStringSync();
      expect(
        parseModsLock(
          before,
          filePath: lock.path,
        ).mods.keys.any((key) => key.contains('@')),
        isTrue,
      );
      final second = await get();
      expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');
      expect(lock.readAsStringSync(), before);
    },
  );

  test('renamed declared peer wins over the old lock-only alias', () async {
    String alias(String key) =>
        '  $key: {modrinth: library, modrinth_host: ${defaultApi.baseUrl}}';
    manifest(alias('old-name'));
    final first = await get();
    expect(first.exitCode, 0, reason: first.stderr);
    manifest(alias('new-name'));
    final second = await get();
    expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');
    final lock = parseModsLock(
      File(p.join(root.path, 'mods.lock')).readAsStringSync(),
      filePath: 'mods.lock',
    );
    expect(lock.mods.keys, unorderedEquals(['default-anchor', 'new-name']));
    expect(lock.mods['new-name']!.requiredBy, ['default-anchor']);
  });
}
