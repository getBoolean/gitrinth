import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/paper_api_client.dart';
import 'package:gitrinth/src/service/resolve/plugin_loader_version_resolver.dart';
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

  test('catalog plugin versions preserve explicit concrete requests', () async {
    final loader = LoaderId('future-plugin');
    final registry = LoaderRegistry.builtins.merge([
      LoaderDescriptor(
        id: loader,
        role: LoaderRole.plugin,
        versionSource: VersionSourceFamily.catalog,
        versions: ['3.0.0', '2.0.0'],
      ),
    ]);
    final r = resolver();
    for (final tag in ['stable', 'latest']) {
      expect(
        await r.resolve(
          loader: loader,
          registry: registry,
          tag: tag,
          mcVersion: '1.21.1',
        ),
        '3.0.0',
      );
    }
    expect(
      await r.resolve(
        loader: loader,
        registry: registry,
        tag: '2.0.0',
        mcVersion: '1.21.1',
      ),
      '2.0.0',
    );
    await expectLater(
      r.resolve(
        loader: loader,
        registry: registry,
        tag: '1.0.0',
        mcVersion: '1.21.1',
      ),
      throwsA(isA<ValidationError>()),
    );
  });

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

  test('Fill v3 uses ids and the supplied object download URL', () async {
    stub.listen((req) async {
      expect(
        req.headers.value('user-agent'),
        contains('github.com/getBoolean/gitrinth'),
      );
      req.response.headers.contentType = ContentType.json;
      req.response.write('''
[
  {"id": 12, "channel": "ALPHA", "downloads": {"server:default": {"name": "paper-12.jar", "url": "https://fill-data.papermc.io/objects/12/paper.jar"}}},
  {"id": 10, "channel": "STABLE", "downloads": {"server:default": {"name": "paper-10.jar", "url": "https://fill-data.papermc.io/objects/10/paper.jar"}}},
  {"id": 11, "channel": "STABLE", "downloads": {"server:default": {"name": "paper-11.jar", "url": "https://fill-data.papermc.io/objects/11/paper.jar"}}}
]
''');
      await req.response.close();
    });
    final api = PaperApiClient(
      dio: dio,
      buildsUrlTemplate: 'http://127.0.0.1:${stub.port}/builds',
    );
    final stable = await api.latestStableBuild(project: 'paper', mc: '1.21.1');
    expect(stable.build, 11);
    expect(
      stable.downloadUrl.toString(),
      'https://fill-data.papermc.io/objects/11/paper.jar',
    );
    expect((await api.latestBuild(project: 'paper', mc: '1.21.1')).build, 12);
    expect(
      (await api.buildByNumber(
        project: 'paper',
        mc: '1.21.1',
        build: 10,
      )).filename,
      'paper-10.jar',
    );
  });

  test('Fill v3 rejects a build without a valid download URL', () async {
    stub.listen((req) async {
      req.response.write(
        '[{"id":1,"channel":"STABLE","downloads":{"server:default":{"name":"paper.jar"}}}]',
      );
      await req.response.close();
    });
    final api = PaperApiClient(
      dio: dio,
      buildsUrlTemplate: 'http://127.0.0.1:${stub.port}/builds',
    );
    await expectLater(
      api.latestStableBuild(project: 'paper', mc: '1.21.1'),
      throwsA(isA<UserError>()),
    );
  });

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
