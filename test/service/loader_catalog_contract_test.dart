import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/app/env.dart';
import 'package:gitrinth/src/app/loader_registry_provider.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/loader_catalog_cache.dart';
import 'package:gitrinth/src/service/loader_descriptor_config.dart';
import 'package:gitrinth/src/service/loader_registry.dart';
import 'package:gitrinth/src/service/paper_api_client.dart';
import 'package:gitrinth/src/service/resolve/mod_loader_version_resolver.dart';
import 'package:gitrinth/src/service/resolve/plugin_loader_version_resolver.dart';
import 'package:gitrinth/src/service/sponge_api_client.dart';
import 'package:riverpod/riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void _writeCatalog(List<Object> args) {
  final result = args[0] as SendPort;
  final cache = LoaderCatalogCache(GitrinthCache(root: args[1] as String));
  try {
    for (var i = 0; i < 100; i++) {
      cache.write('modrinth', 'https://example.test/v2', [
        {
          'name': '${args[2]}-$i',
          'supported_project_types': ['mod'],
        },
      ]);
    }
    result.send(null);
  } on Object catch (error) {
    result.send(error.toString());
  }
}

void main() {
  late Directory root;
  late Dio dio;
  setUp(() {
    root = Directory.systemTemp.createTempSync('loader_contract_');
    dio = Dio();
  });
  tearDown(() {
    dio.close(force: true);
    root.deleteSync(recursive: true);
  });

  test(
    'concurrent provider refreshes keep independent staging files',
    () async {
      final results = ReceivePort();
      addTearDown(results.close);
      await Future.wait([
        for (var i = 0; i < 4; i++)
          Isolate.spawn(_writeCatalog, <Object>[
            results.sendPort,
            root.path,
            i,
          ]),
      ]);
      expect(await results.take(4).toList(), everyElement(isNull));
      final cache = LoaderCatalogCache(GitrinthCache(root: root.path));
      expect(
        cache.read('modrinth', 'https://example.test/v2')?.single['name'],
        isA<String>(),
      );
      expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.contains('.tmp')),
        isEmpty,
      );
    },
  );

  test(
    'plugin applicability wins over legacy mod markers in any entry order',
    () {
      for (final types in [
        [
          ['plugin', 'project', 'mod'],
        ],
        [
          ['plugin'],
          ['mod'],
        ],
        [
          ['mod'],
          ['plugin'],
        ],
      ]) {
        final registry = LoaderRegistryService.mergeModrinth(
          LoaderRegistry.builtins,
          'https://example.test/v2',
          [
            for (final entry in types)
              {'name': 'purpur', 'supported_project_types': entry},
          ],
        );
        expect(registry[LoaderId('purpur')]?.role, LoaderRole.plugin);
      }
    },
  );

  test(
    'hybrid plugin compatibility accepts Forge and rejects Fabric',
    () async {
      final registry = LoaderDescriptorConfig.parse('''
version: 1
loaders:
  hybrid:
    role: plugin
    modrinth: {https://api.modrinth.com/v2: hybrid}
    compatible_mods: [forge]
''');
      for (final loader in ['forge', 'fabric']) {
        final container = ProviderContainer(
          overrides: [
            environmentProvider.overrideWithValue({
              'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(loaderRegistryProvider.notifier).replace(registry);
        final manifest = parseModsYaml('''
slug: demo
name: Demo
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: '$loader:1.0', plugins: 'hybrid:1.0'}
mods: {}
''', filePath: 'mods.yaml');
        final prepared = prepareLoaderRegistry(
          container,
          manifest,
          offline: true,
        );
        if (loader == 'forge') {
          await prepared;
        } else {
          await expectLater(
            prepared,
            throwsA(
              isA<ValidationError>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('hybrid'),
                  contains('fabric'),
                  contains('forge'),
                ),
              ),
            ),
          );
        }
      }
    },
  );

  test(
    'offline selected provider ignores a corrupt disabled catalog',
    () async {
      const host = 'https://example.test/v2';
      const cfHost = 'https://api.curseforge.com';
      final cache = LoaderCatalogCache(GitrinthCache(root: root.path));
      cache.write('modrinth', host, [
        {
          'name': 'future',
          'supported_project_types': ['mod'],
        },
      ]);
      final corrupt = File(cache.path('curseforge', cfHost));
      corrupt.parent.createSync(recursive: true);
      corrupt.writeAsStringSync('{');
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      final service = LoaderRegistryService(
        configured: LoaderRegistry.builtins,
        cache: cache,
        dio: dio,
      );
      final registry = await service.snapshot(
        modrinthHost: host,
        curseforgeHost: cfHost,
        needed: [LoaderId('future')],
        offline: true,
      );
      expect(registry[LoaderId('future')]?.modrinthTag(host), 'future');
      expect(requests, 0);
      await expectLater(
        service.snapshot(
          modrinthHost: host,
          curseforgeHost: cfHost,
          needed: [LoaderId('future')],
          offline: true,
          readCurseforge: () async => [],
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(requests, 0);
    },
  );

  test('CurseForge Any is not a filterable loader identity', () {
    final registry = LoaderRegistryService.mergeCurseforge(
      LoaderRegistry.builtins,
      [
        {'type': 0, 'name': 'any'},
        {'type': -1, 'name': 'invalid'},
        {'type': 42, 'name': 'future'},
      ],
    );
    expect(registry[LoaderId('curseforge-type-0')], isNull);
    expect(registry[LoaderId('curseforge-type-42')]?.curseforgeType, 42);
  });

  test(
    'catalog aliases and concrete versions stay within Minecraft releases',
    () async {
      final id = LoaderId('future');
      final configured = LoaderRegistry.builtins.merge([
        LoaderDescriptor(
          id: id,
          role: LoaderRole.mod,
          curseforgeType: 42,
          versionSource: VersionSourceFamily.catalog,
        ),
      ]);
      final registry = LoaderRegistryService.mergeCurseforge(configured, [
        {'type': 42, 'name': 'unscoped', 'latest': true, 'recommended': true},
        {
          'type': 42,
          'name': 'old-latest',
          'gameVersion': '1.20.1',
          'latest': true,
          'recommended': true,
        },
        {
          'type': 42,
          'name': 'new-beta',
          'gameVersion': '1.21.1',
          'latest': true,
          'recommended': false,
        },
        {
          'type': 42,
          'name': 'new-stable',
          'gameVersion': '1.21.1',
          'latest': false,
          'recommended': true,
        },
      ]);
      final mods = ModLoaderVersionResolver(dio: dio);
      final plugins = PluginLoaderVersionResolver(
        dio: dio,
        paperApi: PaperApiClient(dio: dio),
        spongeApi: SpongeApiClient(dio: dio),
      );
      for (final resolve in [mods.resolve, plugins.resolve]) {
        expect(
          await resolve(
            loader: id,
            registry: registry,
            tag: 'latest',
            mcVersion: '1.21.1',
          ),
          'new-beta',
        );
        expect(
          await resolve(
            loader: id,
            registry: registry,
            tag: 'stable',
            mcVersion: '1.21.1',
          ),
          'new-stable',
        );
        expect(
          await resolve(
            loader: id,
            registry: registry,
            tag: 'new-stable',
            mcVersion: '1.21.1',
          ),
          'new-stable',
        );
        await expectLater(
          resolve(
            loader: id,
            registry: registry,
            tag: 'old-latest',
            mcVersion: '1.21.1',
          ),
          throwsA(isA<ValidationError>()),
        );
        await expectLater(
          resolve(
            loader: id,
            registry: registry,
            tag: 'latest',
            mcVersion: '1.19.4',
          ),
          throwsA(isA<ValidationError>()),
        );
      }
    },
  );
}
