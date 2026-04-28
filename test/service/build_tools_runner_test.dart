import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/build_tools_runner.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/downloader.dart';

void main() {
  late Directory tempRoot;
  late GitrinthCache cache;
  late HttpServer stub;
  late String buildToolsUrl;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_buildtools_');
    cache = GitrinthCache(root: p.join(tempRoot.path, 'cache'));
    cache.ensureRoot();
    stub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    stub.listen((req) async {
      if (req.uri.path == '/BuildTools.jar') {
        req.response.statusCode = 200;
        req.response.add(const [0xCA, 0xFE, 0xBA, 0xBE]);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    buildToolsUrl = 'http://127.0.0.1:${stub.port}/BuildTools.jar';
  });

  tearDown(() async {
    await stub.close(force: true);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Downloader makeDownloader() {
    final dio = Dio();
    addTearDown(dio.close);
    return Downloader(dio: dio, cache: cache);
  }

  Future<int> okGitProbe(
    String exe,
    List<String> args, {
    Directory? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
  }) async => 0;

  Future<int> failingGitProbe(
    String exe,
    List<String> args, {
    Directory? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
  }) async => 1;

  test(
    'returns the cached jar without re-running BuildTools when present',
    () async {
      final cachedPath = cache.pluginServerJarPath(
        artifactKey: 'spigot',
        mcVersion: '1.21.1',
        version: '187',
        filename: 'spigot-1.21.1.jar',
      );
      Directory(p.dirname(cachedPath)).createSync(recursive: true);
      File(cachedPath).writeAsBytesSync(const [1, 2, 3]);

      var runnerCalled = false;
      Future<int> trackingRunner(
        String exe,
        List<String> args, {
        Directory? workingDirectory,
        bool runInShell = false,
        Map<String, String>? environment,
      }) async {
        runnerCalled = true;
        return 0;
      }

      final runner = BuildToolsRunner(
        downloader: makeDownloader(),
        cache: cache,
        runProcess: trackingRunner,
        buildToolsUrlTemplate: buildToolsUrl,
        gitProbe: okGitProbe,
      );
      final jar = await runner.buildSpigotFamily(
        mc: '1.21.1',
        flavor: SpigotFlavor.spigot,
        buildToolsVersion: '187',
        console: const Console(),
        offline: false,
      );
      expect(jar.path, cachedPath);
      expect(jar.readAsBytesSync(), const [1, 2, 3]);
      expect(runnerCalled, isFalse);
    },
  );

  test(
    'downloads BuildTools and spawns java -jar BuildTools.jar --rev <mc>',
    () async {
      String? spawnedExecutable;
      List<String>? spawnedArgs;
      Future<int> trackingRunner(
        String exe,
        List<String> args, {
        Directory? workingDirectory,
        bool runInShell = false,
        Map<String, String>? environment,
      }) async {
        spawnedExecutable = exe;
        spawnedArgs = args;
        // Mimic BuildTools producing the expected output jar in the work dir.
        final jar = File(p.join(workingDirectory!.path, 'spigot-1.21.1.jar'));
        jar.writeAsBytesSync(const [42]);
        return 0;
      }

      final runner = BuildToolsRunner(
        downloader: makeDownloader(),
        cache: cache,
        runProcess: trackingRunner,
        buildToolsUrlTemplate: buildToolsUrl,
        gitProbe: okGitProbe,
      );
      final jar = await runner.buildSpigotFamily(
        mc: '1.21.1',
        flavor: SpigotFlavor.spigot,
        buildToolsVersion: '187',
        console: const Console(),
        offline: false,
      );
      expect(jar.existsSync(), isTrue);
      expect(jar.readAsBytesSync(), const [42]);
      expect(spawnedExecutable, isNotNull);
      expect(spawnedArgs, isNotNull);
      expect(spawnedArgs!.contains('--rev'), isTrue);
      expect(spawnedArgs!.contains('1.21.1'), isTrue);
      expect(spawnedArgs!.contains('--compile'), isFalse);
    },
  );

  test(
    'adds --compile craftbukkit when SpigotFlavor.craftbukkit is requested',
    () async {
      List<String>? spawnedArgs;
      Future<int> trackingRunner(
        String exe,
        List<String> args, {
        Directory? workingDirectory,
        bool runInShell = false,
        Map<String, String>? environment,
      }) async {
        spawnedArgs = args;
        File(
          p.join(workingDirectory!.path, 'craftbukkit-1.21.1.jar'),
        ).writeAsBytesSync(const [1]);
        return 0;
      }

      final runner = BuildToolsRunner(
        downloader: makeDownloader(),
        cache: cache,
        runProcess: trackingRunner,
        buildToolsUrlTemplate: buildToolsUrl,
        gitProbe: okGitProbe,
      );
      await runner.buildSpigotFamily(
        mc: '1.21.1',
        flavor: SpigotFlavor.craftbukkit,
        buildToolsVersion: '187',
        console: const Console(),
        offline: false,
      );
      expect(spawnedArgs!.contains('--compile'), isTrue);
      expect(spawnedArgs!.contains('craftbukkit'), isTrue);
    },
  );

  test('throws UserError when git --version fails', () async {
    final runner = BuildToolsRunner(
      downloader: makeDownloader(),
      cache: cache,
      runProcess:
          (
            exe,
            args, {
            workingDirectory,
            runInShell = false,
            environment,
          }) async => 0,
      buildToolsUrlTemplate: buildToolsUrl,
      gitProbe: failingGitProbe,
    );
    expect(
      () => runner.buildSpigotFamily(
        mc: '1.21.1',
        flavor: SpigotFlavor.spigot,
        buildToolsVersion: '187',
        console: const Console(),
        offline: false,
      ),
      throwsA(isA<UserError>()),
    );
  });

  test(
    'throws UserError when --offline is set and the cached jar is absent',
    () async {
      final runner = BuildToolsRunner(
        downloader: makeDownloader(),
        cache: cache,
        runProcess:
            (
              exe,
              args, {
              workingDirectory,
              runInShell = false,
              environment,
            }) async => 0,
        buildToolsUrlTemplate: buildToolsUrl,
        gitProbe: okGitProbe,
      );
      expect(
        () => runner.buildSpigotFamily(
          mc: '1.21.1',
          flavor: SpigotFlavor.spigot,
          buildToolsVersion: '187',
          console: const Console(),
          offline: true,
        ),
        throwsA(isA<UserError>()),
      );
    },
  );
}
