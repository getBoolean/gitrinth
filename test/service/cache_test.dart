import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late GitrinthCache cache;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_cache_');
    cache = GitrinthCache(root: tempRoot.path);
    cache.ensureRoot();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('layout uses modrinth/<projectId>/<versionId>/<filename>', () {
    final path = cache.modrinthPath(
      projectId: 'P1',
      versionId: 'V1',
      filename: 'a.jar',
    );
    expect(path, p.join(tempRoot.path, 'modrinth', 'P1', 'V1', 'a.jar'));
  });

  test('verifySha512 accepts a matching hash and rejects a wrong one', () {
    final bytes = [1, 2, 3, 4];
    final hex = sha512.convert(bytes).toString();
    expect(() => GitrinthCache.verifySha512(bytes, hex), returnsNormally);
    expect(
      () => GitrinthCache.verifySha512(bytes, '0' * 128),
      throwsA(isA<UserError>()),
    );
  });

  test('verifySha512 is case-insensitive', () {
    final bytes = [9, 8, 7];
    final hex = sha512.convert(bytes).toString();
    expect(
      () => GitrinthCache.verifySha512(bytes, hex.toUpperCase()),
      returnsNormally,
    );
  });

  test('loadersRoot is `<root>/loaders`', () {
    expect(cache.loadersRoot, p.join(tempRoot.path, 'loaders'));
  });

  test(
    'loaderArtifactPath uses loaders/<loader>/<mc>/<loaderVersion>/<filename>',
    () {
      final path = cache.loaderArtifactPath(
        loader: Loader.forge,
        mcVersion: '1.21.1',
        loaderVersion: '52.1.5',
        filename: 'forge-installer.jar',
      );
      expect(
        path,
        p.join(
          tempRoot.path,
          'loaders',
          'forge',
          '1.21.1',
          '52.1.5',
          'forge-installer.jar',
        ),
      );
    },
  );

  test('loaderArtifactPath spells loader names with their enum name', () {
    expect(
      cache.loaderArtifactPath(
        loader: Loader.fabric,
        mcVersion: '1.20.4',
        loaderVersion: '0.16.10',
        filename: 'fabric-server-launch.jar',
      ),
      p.join(
        tempRoot.path,
        'loaders',
        'fabric',
        '1.20.4',
        '0.16.10',
        'fabric-server-launch.jar',
      ),
    );
    expect(
      cache.loaderArtifactPath(
        loader: Loader.neoforge,
        mcVersion: '1.21.1',
        loaderVersion: '21.1.50',
        filename: 'neoforge-21.1.50-installer.jar',
      ),
      p.join(
        tempRoot.path,
        'loaders',
        'neoforge',
        '1.21.1',
        '21.1.50',
        'neoforge-21.1.50-installer.jar',
      ),
    );
  });
}
