import 'package:gitrinth/src/model/manifest/server_distribution.dart';
import 'package:test/test.dart';

Map<String, dynamic> fixture() => {
  'formatVersion': 1,
  'artifactType': 'gitrinth-server-distribution',
  'slug': 'pack',
  'version': '1.0.0',
  'minecraft': '1.21.1',
  'loader': {'id': 'future-runtime', 'version': '1.2.3'},
  'runtimeBundled': false,
  'files': [
    {'path': 'mods/server.jar', 'sha256': 'a' * 64},
  ],
};

void main() {
  test(
    'physical distribution marker round trips independent archive identities',
    () {
      final raw = fixture();
      final parsed = ServerDistributionManifest.fromMap(raw);
      expect(parsed.toMap(), raw);
      expect(parsed.loaderId, 'future-runtime');
      expect(parsed.files.single.path, 'mods/server.jar');
      expect(() => parsed.files.clear(), throwsUnsupportedError);
    },
  );

  test('inventory rejects unsafe and private archive paths', () {
    for (final path in [
      '../escape.jar',
      '/absolute.jar',
      r'C:\secret.jar',
      'mods/../escape.jar',
      '.gitrinth/publications/receipt.json',
      'config/credentials.json',
      '.env',
      'cache/data.json',
      'eula.txt',
      'gitrinth-server-distribution.json',
    ]) {
      final raw = fixture();
      raw['files'] = [
        {'path': path, 'sha256': 'a' * 64},
      ];
      expect(
        () => ServerDistributionManifest.fromMap(raw),
        throwsFormatException,
        reason: path,
      );
    }
    final raw = fixture();
    raw['files'] = [
      {'path': 'mods/tokens.jar', 'sha256': 'a' * 64},
    ];
    expect(
      ServerDistributionManifest.fromMap(raw).files.single.path,
      'mods/tokens.jar',
    );
  });

  test('inventory rejects duplicates and malformed hashes', () {
    final duplicate = fixture();
    duplicate['files'] = [
      {'path': 'mods/server.jar', 'sha256': 'a' * 64},
      {'path': 'mods/SERVER.jar', 'sha256': 'b' * 64},
    ];
    expect(
      () => ServerDistributionManifest.fromMap(duplicate),
      throwsFormatException,
    );
    final invalidHash = fixture();
    invalidHash['files'] = [
      {'path': 'mods/server.jar', 'sha256': 'not-a-sha256'},
    ];
    expect(
      () => ServerDistributionManifest.fromMap(invalidHash),
      throwsFormatException,
    );
  });

  test('marker cannot claim a bundled runtime or a manifest-only archive', () {
    for (final change in [
      {'runtimeBundled': true},
      {'artifactType': 'minecraftModpack'},
      {'files': <Object>[]},
      {'formatVersion': 2},
    ]) {
      expect(
        () => ServerDistributionManifest.fromMap({...fixture(), ...change}),
        throwsFormatException,
      );
    }
  });
}
