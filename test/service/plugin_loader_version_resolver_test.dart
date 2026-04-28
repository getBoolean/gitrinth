import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/paper_api_client.dart';
import 'package:gitrinth/src/service/plugin_loader_version_resolver.dart';
import 'package:gitrinth/src/service/sponge_api_client.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer stub;
  late Dio dio;

  setUp(() async {
    dio = Dio();
    stub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    dio.close();
    await stub.close(force: true);
  });

  PluginLoaderVersionResolver resolver() {
    final base = 'http://127.0.0.1:${stub.port}';
    return PluginLoaderVersionResolver(
      dio: dio,
      paperApi: PaperApiClient(
        dio: dio,
        buildsUrlTemplate:
            '$base/paper/projects/{project}/versions/{mc}/builds',
        downloadUrlTemplate:
            '$base/paper/projects/{project}/versions/{mc}/builds/{build}/'
            'downloads/{filename}',
      ),
      spongeApi: SpongeApiClient(
        dio: dio,
        versionsUrlTemplate:
            '$base/sponge/artifacts/{artifact}/versions?recommended='
            '{recommended}&tags=minecraft:{mc}',
        versionDetailUrlTemplate:
            '$base/sponge/artifacts/{artifact}/versions/{version}',
      ),
      buildToolsBuildNumberUrlTemplate: '$base/buildtools/buildNumber',
      buildToolsJarUrlTemplate: '$base/buildtools/{build}/BuildTools.jar',
    );
  }

  test(
    'Paper stable filters STABLE while latest accepts any channel',
    () async {
      stub.listen((req) async {
        if (req.uri.path == '/paper/projects/paper/versions/1.21.1/builds') {
          req.response.write('''
{
  "builds": [
    {"build": 10, "channel": "STABLE", "downloads": {"application": {"name": "paper-10.jar"}}},
    {"build": 11, "channel": "EXPERIMENTAL", "downloads": {"application": {"name": "paper-11.jar"}}}
  ]
}
''');
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });

      final r = resolver();
      expect(
        await r.resolve(
          loader: PluginLoader.paper,
          tag: 'stable',
          mcVersion: '1.21.1',
        ),
        '10',
      );
      expect(
        await r.resolve(
          loader: PluginLoader.paper,
          tag: 'latest',
          mcVersion: '1.21.1',
        ),
        '11',
      );
      expect(
        await r.resolve(
          loader: PluginLoader.paper,
          tag: '10',
          mcVersion: '1.21.1',
        ),
        '10',
      );
    },
  );

  test('Sponge stable uses recommended builds while latest uses any', () async {
    stub.listen((req) async {
      if (req.uri.path == '/sponge/artifacts/spongeforge/versions' &&
          req.uri.queryParameters['recommended'] == 'true') {
        req.response.write('''
{"artifacts":{"1.21.1-52.1.5-12.0.3":{"recommended":true}}}
''');
      } else if (req.uri.path == '/sponge/artifacts/spongeforge/versions' &&
          req.uri.queryParameters['recommended'] == 'false') {
        req.response.write('''
{"artifacts":{"1.21.1-52.1.5-12.0.3":{},"1.21.1-52.1.5-12.0.4-RC1":{}}}
''');
      } else if (req.uri.path ==
          '/sponge/artifacts/spongeforge/versions/1.21.1-52.1.5-12.0.3') {
        req.response.write('''
{"assets":[{"classifier":"","extension":"jar","downloadUrl":"http://127.0.0.1:${stub.port}/spongeforge.jar"}]}
''');
      } else if (req.uri.path ==
          '/sponge/artifacts/spongeforge/versions/1.21.1-52.1.5-12.0.4-RC1') {
        req.response.write('''
{"assets":[{"classifier":"","extension":"jar","downloadUrl":"http://127.0.0.1:${stub.port}/spongeforge-rc.jar"}]}
''');
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final r = resolver();
    expect(
      await r.resolve(
        loader: PluginLoader.spongeforge,
        tag: 'stable',
        mcVersion: '1.21.1',
      ),
      '1.21.1-52.1.5-12.0.3',
    );
    expect(
      await r.resolve(
        loader: PluginLoader.spongeforge,
        tag: 'latest',
        mcVersion: '1.21.1',
      ),
      '1.21.1-52.1.5-12.0.4-RC1',
    );
  });

  test('Bukkit and Spigot resolve to numeric BuildTools builds', () async {
    stub.listen((req) async {
      if (req.uri.path == '/buildtools/buildNumber') {
        req.response.write('187');
      } else if (req.uri.path == '/buildtools/151/BuildTools.jar') {
        req.response.statusCode = 200;
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final r = resolver();
    expect(
      await r.resolve(
        loader: PluginLoader.spigot,
        tag: 'stable',
        mcVersion: '1.21.1',
      ),
      '187',
    );
    expect(
      await r.resolve(
        loader: PluginLoader.bukkit,
        tag: '151',
        mcVersion: '1.21.1',
      ),
      '151',
    );
  });
}
