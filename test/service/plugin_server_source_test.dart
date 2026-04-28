import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/build_tools_runner.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/paper_api_client.dart';
import 'package:gitrinth/src/service/plugin_server_source.dart';
import 'package:gitrinth/src/service/sponge_api_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeBuildToolsRunner implements BuildToolsRunner {
  SpigotFlavor? lastFlavor;
  String? lastMc;
  String? lastBuildToolsVersion;
  late File toReturn;

  @override
  Future<File> buildSpigotFamily({
    required String mc,
    required SpigotFlavor flavor,
    required String buildToolsVersion,
    required Console console,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
  }) async {
    lastFlavor = flavor;
    lastMc = mc;
    lastBuildToolsVersion = buildToolsVersion;
    return toReturn;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempRoot;
  late GitrinthCache cache;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_plugin_src_');
    cache = GitrinthCache(root: p.join(tempRoot.path, 'cache'));
    cache.ensureRoot();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<HttpServer> startStub(
    Map<String, ({int status, String body, List<int>? bytes})> responses,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final route = '${req.uri.path}?${req.uri.query}';
      final pathOnly = req.uri.path;
      final r = responses[route] ?? responses[pathOnly];
      if (r == null) {
        req.response.statusCode = 404;
      } else {
        req.response.statusCode = r.status;
        if (r.bytes != null) {
          req.response.add(r.bytes!);
        } else {
          req.response.write(r.body);
        }
      }
      await req.response.close();
    });
    return server;
  }

  test(
    'paper strategy hits PaperApiClient and downloads the latest stable build',
    () async {
      final stub = await startStub({
        '/paper/v2/projects/paper/versions/1.21.1/builds': (
          status: 200,
          body: '''
{
  "builds": [
    {"build": 5, "channel": "EXPERIMENTAL", "downloads": {"application": {"name": "paper-1.21.1-5.jar"}}},
    {"build": 100, "channel": "STABLE", "downloads": {"application": {"name": "paper-1.21.1-100.jar"}}}
  ]
}
''',
          bytes: null,
        ),
        '/paper/v2/projects/paper/versions/1.21.1/builds/100/downloads/paper-1.21.1-100.jar':
            (status: 200, body: '', bytes: const [1, 2, 3, 4]),
      });
      addTearDown(() => stub.close(force: true));
      final base = 'http://127.0.0.1:${stub.port}/paper/v2';

      final dio = Dio();
      addTearDown(dio.close);
      final paperApi = PaperApiClient(
        dio: dio,
        buildsUrlTemplate: '$base/projects/{project}/versions/{mc}/builds',
        downloadUrlTemplate:
            '$base/projects/{project}/versions/{mc}/builds/{build}/downloads/'
            '{filename}',
      );
      final source = PluginServerSource.forLoader(
        PluginLoader.paper,
        paperApi: paperApi,
        spongeApi: SpongeApiClient(dio: dio),
        buildTools: _FakeBuildToolsRunner(),
        cache: cache,
        downloader: Downloader(dio: dio, cache: cache),
      );

      final jar = await source.fetchServerJar(
        mcVersion: '1.21.1',
        pluginLoaderVersion: '100',
        offline: false,
        console: const Console(),
      );
      expect(jar.existsSync(), isTrue);
      expect(jar.readAsBytesSync(), const [1, 2, 3, 4]);
      expect(p.basename(jar.path), 'paper-1.21.1-100.jar');
      expect(source.installMarker, 'plugin-paper');
    },
  );

  test('spongeforge strategy with modLoader=forge fetches spongeforge', () async {
    final stub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => stub.close(force: true));
    stub.listen((req) async {
      if (req.uri.path ==
          '/sponge/v2/groups/org.spongepowered/artifacts/spongeforge/versions') {
        req.response.statusCode = 200;
        req.response.write('''
{
  "artifacts": {
    "1.21.1-1.0.0": {
      "recommended": true,
      "tagValues": {"minecraft": "1.21.1"}
    }
  }
}
''');
      } else if (req.uri.path ==
          '/sponge/v2/groups/org.spongepowered/artifacts/spongeforge/versions/1.21.1-1.0.0') {
        req.response.statusCode = 200;
        req.response.write('''
{
  "assets": [
    {"classifier": "accessors", "extension": "jar", "downloadUrl": "http://127.0.0.1:${stub.port}/sponge/dl/spongeforge-accessors.jar"},
    {"classifier": "", "extension": "jar", "downloadUrl": "http://127.0.0.1:${stub.port}/sponge/dl/spongeforge-1.21.1.jar"}
  ]
}
''');
      } else if (req.uri.path == '/sponge/dl/spongeforge-1.21.1.jar') {
        req.response.statusCode = 200;
        req.response.add(const [9, 9, 9]);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final dio = Dio();
    addTearDown(dio.close);
    final spongeApi = SpongeApiClient(
      dio: dio,
      versionsUrlTemplate:
          'http://127.0.0.1:${stub.port}/sponge/v2/groups/org.spongepowered/'
          'artifacts/{artifact}/versions',
      versionDetailUrlTemplate:
          'http://127.0.0.1:${stub.port}/sponge/v2/groups/org.spongepowered/'
          'artifacts/{artifact}/versions/{version}',
    );
    final source = PluginServerSource.forLoader(
      PluginLoader.spongeforge,
      paperApi: PaperApiClient(dio: dio),
      spongeApi: spongeApi,
      buildTools: _FakeBuildToolsRunner(),
      cache: cache,
      downloader: Downloader(dio: dio, cache: cache),
    );
    final jar = await source.fetchServerJar(
      mcVersion: '1.21.1',
      pluginLoaderVersion: '1.21.1-1.0.0',
      offline: false,
      console: const Console(),
    );
    expect(jar.readAsBytesSync(), const [9, 9, 9]);
    expect(source.installMarker, 'plugin-spongeforge');
  });

  test(
    'spongeneo strategy with modLoader=neoforge picks spongeneo install marker',
    () {
      final dio = Dio();
      addTearDown(dio.close);
      final source = PluginServerSource.forLoader(
        PluginLoader.spongeneo,
        paperApi: PaperApiClient(dio: dio),
        spongeApi: SpongeApiClient(dio: dio),
        buildTools: _FakeBuildToolsRunner(),
        cache: cache,
        downloader: Downloader(dio: dio, cache: cache),
      );
      expect(source.installMarker, 'plugin-spongeneo');
    },
  );

  test(
    'spigot strategy delegates to BuildToolsRunner with SpigotFlavor.spigot',
    () async {
      final fakeRunner = _FakeBuildToolsRunner();
      fakeRunner.toReturn = File(p.join(tempRoot.path, 'cached-spigot.jar'))
        ..writeAsBytesSync(const [4, 2]);

      final dio = Dio();
      addTearDown(dio.close);
      final source = PluginServerSource.forLoader(
        PluginLoader.spigot,
        paperApi: PaperApiClient(dio: dio),
        spongeApi: SpongeApiClient(dio: dio),
        buildTools: fakeRunner,
        cache: cache,
        downloader: Downloader(dio: dio, cache: cache),
      );
      final jar = await source.fetchServerJar(
        mcVersion: '1.21.1',
        pluginLoaderVersion: '187',
        offline: false,
        console: const Console(),
      );
      expect(jar.path, fakeRunner.toReturn.path);
      expect(fakeRunner.lastFlavor, SpigotFlavor.spigot);
      expect(fakeRunner.lastMc, '1.21.1');
      expect(fakeRunner.lastBuildToolsVersion, '187');
      expect(source.installMarker, 'plugin-spigot');
    },
  );

  test(
    'bukkit strategy delegates to BuildToolsRunner with SpigotFlavor.craftbukkit',
    () async {
      final fakeRunner = _FakeBuildToolsRunner();
      fakeRunner.toReturn = File(
        p.join(tempRoot.path, 'cached-craftbukkit.jar'),
      )..writeAsBytesSync(const [1]);

      final dio = Dio();
      addTearDown(dio.close);
      final source = PluginServerSource.forLoader(
        PluginLoader.bukkit,
        paperApi: PaperApiClient(dio: dio),
        spongeApi: SpongeApiClient(dio: dio),
        buildTools: fakeRunner,
        cache: cache,
        downloader: Downloader(dio: dio, cache: cache),
      );
      await source.fetchServerJar(
        mcVersion: '1.21.1',
        pluginLoaderVersion: '187',
        offline: false,
        console: const Console(),
      );
      expect(fakeRunner.lastFlavor, SpigotFlavor.craftbukkit);
      expect(fakeRunner.lastBuildToolsVersion, '187');
      expect(source.installMarker, 'plugin-craftbukkit');
    },
  );
}
