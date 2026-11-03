import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/loader_catalog_cache.dart';
import 'package:gitrinth/src/service/loader_descriptor_config.dart';
import 'package:gitrinth/src/service/loader_registry.dart';
import 'package:test/test.dart';

void main() {
  test(
    'online discovery repairs corrupt catalogs while offline stays network-free',
    () async {
      final root = Directory.systemTemp.createTempSync('loader_recovery_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = Dio();
      addTearDown(() async {
        dio.close(force: true);
        await server.close(force: true);
        root.deleteSync(recursive: true);
      });
      final host = 'http://127.0.0.1:${server.port}/v2';
      final cache = LoaderCatalogCache(GitrinthCache(root: root.path));
      final sidecar = File(cache.path('modrinth', host));
      sidecar.parent.createSync(recursive: true);
      sidecar.writeAsStringSync('{');
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            {
              'name': 'future',
              'supported_project_types': ['mod'],
            },
          ]),
        );
        await request.response.close();
      });
      final service = LoaderRegistryService(
        configured: LoaderRegistry.builtins,
        cache: cache,
        dio: dio,
      );
      await expectLater(
        service.snapshot(
          modrinthHost: host,
          curseforgeHost: 'https://api.curseforge.com',
          needed: [LoaderId('future')],
          offline: true,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(requests, 0);
      final repaired = await service.snapshot(
        modrinthHost: host,
        curseforgeHost: 'https://api.curseforge.com',
        needed: [LoaderId('future')],
        refresh: true,
      );
      expect(repaired[LoaderId('future')]?.modrinthTag(host), 'future');
      expect(requests, 1);
      expect(cache.read('modrinth', host)?.single['name'], 'future');
    },
  );

  test('descriptors and snapshots defensively copy caller collections', () {
    final tags = {'https://example.test/v2': 'future'};
    final versions = ['1.0.0'];
    final descriptor = LoaderDescriptor(
      id: LoaderId('future'),
      role: LoaderRole.mod,
      modrinthTags: tags,
      versions: versions,
    );
    final registry = LoaderRegistry([descriptor]);
    tags.clear();
    versions.clear();
    expect(
      registry[LoaderId('future')]?.modrinthTag('https://example.test/v2'),
      'future',
    );
    expect(descriptor.versions, ['1.0.0']);
    expect(() => descriptor.modrinthTags.clear(), throwsUnsupportedError);
    expect(() => registry.descriptors.clear(), throwsUnsupportedError);
  });

  test(
    'unknown CF numeric types preserve versions without inventing aliases or recipes',
    () {
      final registry = LoaderRegistryService.mergeCurseforge(
        LoaderRegistry.builtins,
        [
          {'type': 42, 'name': 'unmapped-loader-1.0.0'},
        ],
      );
      final descriptor = registry[LoaderId('curseforge-type-42')]!;
      expect(descriptor.curseforgeType, 42);
      expect(descriptor.versions, ['unmapped-loader-1.0.0']);
      expect(descriptor.modrinthTags, isEmpty);
      expect(descriptor.installer, isNull);
      expect(descriptor.curseforgeArchiveToken, isNull);
    },
  );

  test(
    'host catalog mappings remain scoped and remote data grants no runtime',
    () {
      const entry = {
        'name': 'future',
        'supported_project_types': ['mod', 'modpack'],
        'installer_family': 'forge',
      };
      final first = LoaderRegistryService.mergeModrinth(
        LoaderRegistry.builtins,
        'https://a.test/v2',
        [entry],
      );
      final next = LoaderRegistryService.mergeModrinth(
        first,
        'https://b.test/v2',
        [entry],
      );
      final descriptor = next[LoaderId('future')]!;
      expect(descriptor.modrinthTag('https://a.test/v2'), 'future');
      expect(descriptor.modrinthTag('https://b.test/v2'), 'future');
      expect(descriptor.modrinthTag('https://c.test/v2'), isNull);
      expect(descriptor.installer, isNull);
    },
  );

  for (final bad in [
    '../escape',
    '--install-dir',
    'http://evil.test',
    'evil;echo',
  ]) {
    test(
      'remote loader identity $bad cannot become paths or executable metadata',
      () {
        expect(
          () => LoaderRegistryService.mergeModrinth(
            LoaderRegistry.builtins,
            'https://a.test/v2',
            [
              {
                'name': bad,
                'supported_project_types': ['mod'],
              },
            ],
          ),
          throwsA(isA<ValidationError>()),
        );
      },
    );
  }

  test(
    'descriptor mappings accept data and reject unknown keys and collisions',
    () {
      final registry = LoaderDescriptorConfig.parse('''
version: 1
loaders:
  future:
    role: mod
    modrinth: {https://example.test/v2: future-tag}
    curseforge_type: 42
    archive: {modrinth: future-loader, curseforge: future}
    version_source: catalog
''');
      expect(registry[LoaderId('future')]?.curseforgeType, 42);
      expect(registry[LoaderId('future')]?.modrinthArchiveKey, 'future-loader');
      for (final text in [
        'version: 1\nloaders: {future: {role: mod, command: "echo unsafe"}}',
        'version: 1\nloaders: {forge: {role: mod}}',
        'version: 1\nloaders: {future: {role: mod, modrinth: {https://example.test/v2: fabric}}}',
        'version: 1\nloaders: {future: {role: mod, installer_family: "sh script"}}',
        'version: 1\nloaders: {future: {role: mod, curseforge_type: 4}}',
      ]) {
        expect(
          () => LoaderDescriptorConfig.parse(text),
          throwsA(isA<ValidationError>()),
        );
      }
    },
  );

  test(
    'refresh discovers a provider addition and offline reuses the exact host snapshot',
    () async {
      final root = Directory.systemTemp.createTempSync('loader_catalog_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = Dio();
      addTearDown(() async {
        dio.close(force: true);
        await server.close(force: true);
        root.deleteSync(recursive: true);
      });
      final host = 'http://127.0.0.1:${server.port}/v2';
      final entries = <Map<String, dynamic>>[];
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.uri.path, '/v2/tag/loader');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(entries));
        await request.response.close();
      });
      final service = LoaderRegistryService(
        configured: LoaderRegistry.builtins,
        cache: LoaderCatalogCache(GitrinthCache(root: root.path)),
        dio: dio,
      );
      final first = await service.snapshot(
        modrinthHost: host,
        curseforgeHost: 'https://api.curseforge.com',
        needed: [LoaderId.fabric],
        refresh: true,
      );
      expect(first[LoaderId('future')], isNull);
      entries.add({
        'name': 'future',
        'supported_project_types': ['mod', 'modpack'],
      });
      final next = await service.snapshot(
        modrinthHost: host,
        curseforgeHost: 'https://api.curseforge.com',
        needed: [LoaderId('future')],
        refresh: true,
      );
      expect(next[LoaderId('future')]?.modrinthArchiveKey, isNull);
      final offline = await service.snapshot(
        modrinthHost: host,
        curseforgeHost: 'https://api.curseforge.com',
        needed: [LoaderId('future')],
        offline: true,
      );
      expect(offline[LoaderId('future')]?.modrinthTag(host), 'future');
      expect(requests, 2);
      await expectLater(
        service.snapshot(
          modrinthHost: 'https://other.test/v2',
          curseforgeHost: 'https://api.curseforge.com',
          needed: [LoaderId('future')],
          offline: true,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(requests, 2);
    },
  );
}
