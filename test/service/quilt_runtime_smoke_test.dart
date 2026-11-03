@Tags(['network'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/loader_binary_fetcher.dart';
import 'package:gitrinth/src/service/server_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  if (Platform.environment['GITRINTH_NETWORK_TESTS'] != '1') {
    test(
      'Quilt runtime smoke',
      () {},
      skip: 'set GITRINTH_NETWORK_TESTS=1 with Java 21 available',
    );
    return;
  }
  test(
    'official Quilt installer creates its server runtime in an isolated directory',
    () async {
      final root = Directory.systemTemp.createTempSync('quilt_runtime_smoke_');
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      addTearDown(() {
        dio.close(force: true);
        root.deleteSync(recursive: true);
      });
      final cache = GitrinthCache(root: p.join(root.path, 'cache'));
      final fetcher = LoaderBinaryFetcher(
        cache: cache,
        downloader: Downloader(dio: dio, cache: cache),
      );
      final installer = await fetcher.fetchServerArtifact(
        loader: LoaderId.quilt,
        mcVersion: '1.21.1',
        modLoaderVersion: '0.30.2',
      );
      final output = Directory(p.join(root.path, 'server with spaces'));
      await ServerInstaller().installServer(
        loader: LoaderId.quilt,
        mcVersion: '1.21.1',
        modLoaderVersion: '0.30.2',
        outputDir: output,
        installerOrServerJar: installer,
        offline: false,
      );
      expect(
        File(p.join(output.path, 'quilt-server-launch.jar')).lengthSync(),
        greaterThan(0),
      );
      expect(
        File(p.join(output.path, 'server.jar')).lengthSync(),
        greaterThan(0),
      );
      expect(Directory(p.join(output.path, 'libraries')).existsSync(), isTrue);
      expect(File(p.join(output.path, 'eula.txt')).existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
