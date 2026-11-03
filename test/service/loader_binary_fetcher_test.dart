import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/loader_binary_fetcher.dart';
import 'package:gitrinth/src/service/offline_guard_interceptor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fake_modrinth.dart';

void main() {
  group('LoaderBinaryFetcher', () {
    late FakeModrinth fake;
    late Directory tempCacheRoot;
    late GitrinthCache cache;
    late Dio dio;
    late Downloader downloader;
    late LoaderBinaryFetcher fetcher;
    bool offline = false;

    setUp(() async {
      fake = FakeModrinth();
      await fake.start();
      tempCacheRoot = Directory.systemTemp.createTempSync('gitrinth_lbf_');
      cache = GitrinthCache(root: tempCacheRoot.path);
      cache.ensureRoot();
      offline = false;
      dio = Dio()..interceptors.add(OfflineGuardInterceptor(() => offline));
      downloader = Downloader(dio: dio, cache: cache);
      fetcher = LoaderBinaryFetcher(
        cache: cache,
        downloader: downloader,
        forgeInstallerUrlTemplate: fake.forgeInstallerUrlTemplate,
        neoforgeInstallerUrlTemplate: fake.neoforgeInstallerUrlTemplate,
        neoforgeLegacyInstallerUrlTemplate:
            fake.neoforgeLegacyInstallerUrlTemplate,
        fabricServerJarUrlTemplate: fake.fabricServerJarUrlTemplate,
        fabricInstallerUrlTemplate: fake.fabricInstallerUrlTemplate,
      );
    });

    tearDown(() async {
      dio.close(force: true);
      await fake.stop();
      if (tempCacheRoot.existsSync()) {
        tempCacheRoot.deleteSync(recursive: true);
      }
    });

    test(
      'online Quilt fetch repairs truncated metadata after verifying cached bytes',
      () async {
        final bytes = utf8.encode('verified quilt installer');
        final digest = sha512.convert(bytes).toString();
        final destination = cache.loaderArtifactPath(
          loader: LoaderId.quilt,
          mcVersion: '1.21.1',
          modLoaderVersion: '0.30.2',
          filename: 'quilt-installer.jar',
        );
        File(destination)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
        final metadata = File('$destination.metadata.json')
          ..writeAsStringSync('{"version":');
        var calls = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              calls++;
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: [
                    {
                      'version': '1.0.0',
                      'hashes': {'sha512': digest},
                      'url':
                          'https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/1.0.0/quilt-installer-1.0.0.jar',
                    },
                  ],
                ),
              );
            },
          ),
        );
        final quilt = LoaderBinaryFetcher(
          cache: cache,
          downloader: downloader,
          environment: {},
        );
        final artifact = await quilt.fetchServerArtifact(
          loader: LoaderId.quilt,
          mcVersion: '1.21.1',
          modLoaderVersion: '0.30.2',
        );
        expect(artifact.readAsBytesSync(), bytes);
        expect(calls, 1);
        expect(
          (jsonDecode(metadata.readAsStringSync()) as Map)['version'],
          '1.0.0',
        );
      },
    );

    test('fetches Forge installer to the loaders cache', () async {
      final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
      fake.forgeInstallerBytes['1.21.1-52.1.5'] = bytes;

      final file = await fetcher.fetchServerArtifact(
        loader: ModLoader.forge,
        mcVersion: '1.21.1',
        modLoaderVersion: '52.1.5',
      );

      expect(
        file.path,
        p.join(
          tempCacheRoot.path,
          'loaders',
          'forge',
          '1.21.1',
          '52.1.5',
          'forge-1.21.1-52.1.5-installer.jar',
        ),
      );
      expect(file.readAsBytesSync(), bytes);
    });

    test('fetches modern NeoForge installer to the loaders cache', () async {
      final bytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      fake.neoforgeInstallerBytes['21.1.50'] = bytes;

      final file = await fetcher.fetchServerArtifact(
        loader: ModLoader.neoforge,
        mcVersion: '1.21.1',
        modLoaderVersion: '21.1.50',
      );

      expect(
        file.path,
        p.join(
          tempCacheRoot.path,
          'loaders',
          'neoforge',
          '1.21.1',
          '21.1.50',
          'neoforge-21.1.50-installer.jar',
        ),
      );
      expect(file.readAsBytesSync(), bytes);
    });

    test('NeoForge on MC 1.20.1 uses the legacy `forge` namespace', () async {
      final bytes = Uint8List.fromList([7, 7, 7, 7]);
      fake.neoforgeLegacyInstallerBytes['1.20.1-47.1.106'] = bytes;

      final file = await fetcher.fetchServerArtifact(
        loader: ModLoader.neoforge,
        mcVersion: '1.20.1',
        modLoaderVersion: '47.1.106',
      );

      expect(
        file.path,
        p.join(
          tempCacheRoot.path,
          'loaders',
          'neoforge',
          '1.20.1',
          '47.1.106',
          'forge-1.20.1-47.1.106-installer.jar',
        ),
      );
      expect(file.readAsBytesSync(), bytes);
    });

    test('fetches the Fabric server-launch JAR to the loaders cache', () async {
      final bytes = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      fake.fabricServerJarBytes['1.21.1/0.17.3'] = bytes;

      final file = await fetcher.fetchServerArtifact(
        loader: ModLoader.fabric,
        mcVersion: '1.21.1',
        modLoaderVersion: '0.17.3',
      );

      expect(
        file.path,
        p.join(
          tempCacheRoot.path,
          'loaders',
          'fabric',
          '1.21.1',
          '0.17.3',
          'fabric-server-launch.jar',
        ),
      );
      expect(file.readAsBytesSync(), bytes);
    });

    test('cache hit on second call does not re-download', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      fake.forgeInstallerBytes['1.21.1-52.1.5'] = bytes;

      await fetcher.fetchServerArtifact(
        loader: ModLoader.forge,
        mcVersion: '1.21.1',
        modLoaderVersion: '52.1.5',
      );
      final hitsAfterFirst =
          fake.requestCounts['/forge-installer/1.21.1-52.1.5/'
              'forge-1.21.1-52.1.5-installer.jar'] ??
          0;
      expect(hitsAfterFirst, 1);

      await fetcher.fetchServerArtifact(
        loader: ModLoader.forge,
        mcVersion: '1.21.1',
        modLoaderVersion: '52.1.5',
      );
      final hitsAfterSecond =
          fake.requestCounts['/forge-installer/1.21.1-52.1.5/'
              'forge-1.21.1-52.1.5-installer.jar'] ??
          0;
      expect(hitsAfterSecond, 1, reason: 'second call should be a cache hit');
    });

    test(
      'offline + empty cache surfaces a UserError from the offline guard',
      () async {
        offline = true;
        fake.forgeInstallerBytes['1.21.1-52.1.5'] = Uint8List.fromList([1, 2]);

        await expectLater(
          fetcher.fetchServerArtifact(
            loader: ModLoader.forge,
            mcVersion: '1.21.1',
            modLoaderVersion: '52.1.5',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('offline'),
            ),
          ),
        );
      },
    );

    test(
      'fetchClientInstaller for Fabric pulls the universal installer JAR',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        fake.fabricInstallerBytes['1.0.1'] = bytes;

        final file = await fetcher.fetchClientInstaller(
          loader: ModLoader.fabric,
          mcVersion: '1.21.1',
          modLoaderVersion: '0.17.3',
        );

        expect(file.path, endsWith('fabric-installer.jar'));
        expect(file.readAsBytesSync(), bytes);
      },
    );

    test(
      'fetchClientInstaller for Forge reuses the server-side installer JAR',
      () async {
        final bytes = Uint8List.fromList([42]);
        fake.forgeInstallerBytes['1.21.1-52.1.5'] = bytes;

        final clientFile = await fetcher.fetchClientInstaller(
          loader: ModLoader.forge,
          mcVersion: '1.21.1',
          modLoaderVersion: '52.1.5',
        );
        final serverFile = await fetcher.fetchServerArtifact(
          loader: ModLoader.forge,
          mcVersion: '1.21.1',
          modLoaderVersion: '52.1.5',
        );
        expect(clientFile.path, serverFile.path);
      },
    );

    test('falls back to env-var URL templates when args omitted', () async {
      final bytes = Uint8List.fromList([42]);
      fake.forgeInstallerBytes['1.21.1-52.1.5'] = bytes;
      final envFetcher = LoaderBinaryFetcher(
        cache: cache,
        downloader: downloader,
        environment: {
          'GITRINTH_FORGE_INSTALLER_URL': fake.forgeInstallerUrlTemplate,
        },
      );
      final file = await envFetcher.fetchServerArtifact(
        loader: ModLoader.forge,
        mcVersion: '1.21.1',
        modLoaderVersion: '52.1.5',
      );
      expect(file.readAsBytesSync(), bytes);
    });
  });
}
