import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/app/env.dart';
import 'package:gitrinth/src/app/loader_registry_provider.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/loader_catalog_cache.dart';
import 'package:gitrinth/src/service/loader_registry.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

/// Drives loader discovery end to end: `prepareLoaderRegistry` →
/// `CurseForgeApiFactory.listMinecraftLoaders` (with the production
/// auth/offline interceptors) → the persisted catalog cache → snapshot.
void main() {
  late Directory root;
  late HttpServer server;
  late String host;
  late List<String> paths;
  late List<String?> apiKeys;
  late Object Function(HttpRequest request) cfBody;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('cf_loader_discovery_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    host = 'http://127.0.0.1:${server.port}';
    paths = [];
    apiKeys = [];
    cfBody = (_) => {
      'data': [
        {
          'name': 'future-loader-2.0.0',
          'gameVersion': '1.21.1',
          'latest': true,
          'recommended': true,
          'type': 42,
        },
        {
          'name': 'future-loader-1.0.0',
          'gameVersion': '1.21.1',
          'latest': false,
          'recommended': false,
          'type': 42,
        },
      ],
    };
    server.listen((request) async {
      paths.add(request.uri.path);
      apiKeys.add(request.headers.value('x-api-key'));
      request.response.headers.contentType = ContentType.json;
      final body = request.uri.path == '/v1/minecraft/modloader'
          ? cfBody(request)
          : request.uri.path == '/tag/loader'
          ? [
              {
                'name': 'future',
                'supported_project_types': ['mod'],
              },
            ]
          : (request.response.statusCode = 404);
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        environmentProvider.overrideWithValue({
          'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
          'GITRINTH_CACHE': p.join(root.path, 'cache'),
          'GITRINTH_CURSEFORGE_URL': host,
          'GITRINTH_CURSEFORGE_TOKEN': 'read-key',
          'GITRINTH_MODRINTH_URL': host,
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  LoaderCatalogCache catalogs() =>
      LoaderCatalogCache(GitrinthCache(root: p.join(root.path, 'cache')));

  String manifest({
    required String loader,
    String modrinth = 'disabled',
    String curseforge = 'enabled',
  }) =>
      '''
slug: demo
name: Demo
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: '$loader'}
gitrinth: {modrinth: $modrinth, curseforge: $curseforge}
mods: {}
''';

  Future<LoaderRegistry> prepare(String yaml, {bool offline = false}) =>
      prepareLoaderRegistry(
        container(),
        parseModsYaml(yaml, filePath: 'mods.yaml'),
        offline: offline,
      );

  final unknown = LoaderId('curseforge-type-42');

  test(
    'discovers an unknown numeric loader type and reuses it offline',
    () async {
      final registry = await prepare(
        manifest(loader: 'curseforge-type-42:2.0.0'),
      );

      expect(paths, ['/v1/minecraft/modloader']);
      expect(apiKeys, ['read-key']);
      final discovered = registry[unknown];
      expect(discovered?.curseforgeType, 42);
      expect(discovered?.role, LoaderRole.mod);
      expect(discovered?.versions, [
        'future-loader-2.0.0',
        'future-loader-1.0.0',
      ]);
      expect(catalogs().read('curseforge', host)?.map((e) => e['name']), [
        'future-loader-2.0.0',
        'future-loader-1.0.0',
      ]);

      await server.close(force: true);
      final offline = await prepare(
        manifest(loader: 'curseforge-type-42:2.0.0'),
        offline: true,
      );

      expect(offline[unknown]?.curseforgeType, 42);
      expect(offline[unknown]?.versions, discovered?.versions);
      expect(paths, hasLength(1), reason: 'offline reuse sends no request');
    },
  );

  for (final (label, body) in [
    ('a missing data list', (HttpRequest _) => {'data': 'nope'}),
    (
      'a non-object entry',
      (HttpRequest _) => {
        'data': ['future-loader-2.0.0'],
      },
    ),
    ('a bare list envelope', (HttpRequest _) => <Object>[]),
  ]) {
    test('rejects $label without caching it', () async {
      cfBody = body;

      await expectLater(
        prepare(manifest(loader: 'curseforge-type-42:2.0.0')),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('CurseForge loader discovery'),
          ),
        ),
      );

      expect(paths, ['/v1/minecraft/modloader']);
      expect(File(catalogs().path('curseforge', host)).existsSync(), isFalse);
    });
  }

  test('a disabled CurseForge provider sends no CurseForge request', () async {
    final registry = await prepare(
      manifest(
        loader: 'future:1.0.0',
        modrinth: 'enabled',
        curseforge: 'disabled',
      ),
    );

    expect(registry[LoaderId('future')]?.modrinthTag(host), 'future');
    expect(paths, ['/tag/loader']);
    expect(apiKeys, [null], reason: 'Modrinth discovery never gets the CF key');
    expect(File(catalogs().path('curseforge', host)).existsSync(), isFalse);
  });
}
