import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/curseforge/cf_constants.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_filters.dart';
import 'package:test/test.dart';

void main() {
  group('SectionCfMapping.cfClassId', () {
    test('mods → 6', () {
      expect(Section.mods.cfClassId, 6);
    });

    test('resourcePacks → 12', () {
      expect(Section.resourcePacks.cfClassId, 12);
    });

    test('dataPacks → 6945', () {
      expect(Section.dataPacks.cfClassId, 6945);
    });

    test('shaders → 6552', () {
      expect(Section.shaders.cfClassId, 6552);
    });

    test('plugins → 5', () {
      expect(Section.plugins.cfClassId, 5);
    });
  });

  group('ModLoaderCfMapping.cfModLoaderType', () {
    test('forge → 1', () {
      expect(ModLoader.forge.cfModLoaderType, 1);
    });

    test('fabric → 4', () {
      expect(ModLoader.fabric.cfModLoaderType, 4);
    });

    test('quilt uses the official numeric type 5', () {
      expect(ModLoader.quilt.cfModLoaderType, 5);
    });

    test('neoforge → 6', () {
      expect(ModLoader.neoforge.cfModLoaderType, 6);
    });
  });

  group('cfReleaseTypesFor', () {
    test('release → {1}', () {
      expect(cfReleaseTypesFor(Channel.release), {1});
    });

    test('beta → {1, 2}', () {
      expect(cfReleaseTypesFor(Channel.beta), {1, 2});
    });

    test('alpha → {1, 2, 3}', () {
      expect(cfReleaseTypesFor(Channel.alpha), {1, 2, 3});
    });
  });

  group('pluginLoaderEligibleForCurseforge', () {
    test('bukkit is eligible', () {
      expect(pluginLoaderEligibleForCurseforge(PluginLoader.bukkit), isTrue);
    });

    test('spigot is eligible', () {
      expect(pluginLoaderEligibleForCurseforge(PluginLoader.spigot), isTrue);
    });

    test('paper is eligible', () {
      expect(pluginLoaderEligibleForCurseforge(PluginLoader.paper), isTrue);
    });

    test('folia is not eligible', () {
      expect(pluginLoaderEligibleForCurseforge(PluginLoader.folia), isFalse);
    });

    test('spongeforge is not eligible', () {
      expect(
        pluginLoaderEligibleForCurseforge(PluginLoader.spongeforge),
        isFalse,
      );
    });

    test('spongeneo is not eligible', () {
      expect(
        pluginLoaderEligibleForCurseforge(PluginLoader.spongeneo),
        isFalse,
      );
    });

    test('spongevanilla is not eligible', () {
      expect(
        pluginLoaderEligibleForCurseforge(PluginLoader.spongevanilla),
        isFalse,
      );
    });
  });

  group('kCurseForgeGameIdMinecraft', () {
    test('is 432', () {
      expect(kCurseForgeGameIdMinecraft, 432);
    });
  });

  group('listCompatibleFiles', () {
    test('Any cannot act as a concrete loader filter', () async {
      final adapter = _ScriptedAdapter([]);
      final loader = LoaderId('future');
      await expectLater(
        listCompatibleFiles(
          api: _apiWith(adapter),
          registry: LoaderRegistry.builtins.merge([
            LoaderDescriptor(
              id: loader,
              role: LoaderRole.mod,
              curseforgeType: 0,
            ),
          ]),
          projectId: 1,
          section: Section.mods,
          modLoader: loader,
          gameVersions: ['1.21.1'],
          channel: Channel.release,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    final filesFixture = File(
      'test/fixtures/curseforge/mod_files_response.json',
    ).readAsStringSync();

    test('drops files whose gameVersions does not intersect the requested '
        'list and respects the channel floor', () async {
      final adapter = _ScriptedAdapter([_resp(200, filesFixture)]);
      final api = _apiWith(adapter);

      final files = await listCompatibleFiles(
        api: api,
        projectId: 238222,
        section: Section.mods,
        modLoader: ModLoader.forge,
        gameVersions: const ['1.21.1'],
        channel: Channel.release,
      );

      // Release channel admits releaseType==1 only; 4 of the 5 fixture
      // files match `1.21.1`, but only the two release-type ones survive
      // and the 1.21-only file is dropped.
      expect(files, hasLength(2));
      // Newest-first by fileDate.
      expect(files.first.id, 5814200);
      expect(files.last.id, 5814100);
    });

    test(
      'explicitly unavailable newest file is excluded from candidates',
      () async {
        final fixture = jsonDecode(filesFixture) as Map<String, dynamic>;
        for (final file in fixture['data'] as List) {
          if (file['id'] == 5814200) file['isAvailable'] = false;
        }
        final api = _apiWith(
          _ScriptedAdapter([_resp(200, jsonEncode(fixture))]),
        );
        final files = await listCompatibleFiles(
          api: api,
          projectId: 238222,
          section: Section.mods,
          modLoader: ModLoader.forge,
          gameVersions: const ['1.21.1'],
          channel: Channel.release,
        );
        expect(files.map((f) => f.id), [5814100]);
      },
    );

    test('all compatible files unavailable explains availability', () async {
      final fixture = jsonDecode(filesFixture) as Map<String, dynamic>;
      for (final file in fixture['data'] as List) {
        file['isAvailable'] = false;
      }
      final api = _apiWith(_ScriptedAdapter([_resp(200, jsonEncode(fixture))]));
      await expectLater(
        listCompatibleFiles(
          api: api,
          projectId: 238222,
          section: Section.mods,
          modLoader: ModLoader.forge,
          gameVersions: const ['1.21.1'],
          channel: Channel.release,
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.toString(),
            'message',
            contains('unavailable'),
          ),
        ),
      );
    });

    test('beta channel admits releaseType ∈ {1, 2}', () async {
      final adapter = _ScriptedAdapter([_resp(200, filesFixture)]);
      final api = _apiWith(adapter);

      final files = await listCompatibleFiles(
        api: api,
        projectId: 238222,
        section: Section.mods,
        modLoader: ModLoader.fabric,
        gameVersions: const ['1.21.1'],
        channel: Channel.beta,
      );

      expect(
        files.map((f) => f.id),
        containsAll(<int>[5814200, 5814100, 5814050]),
      );
      expect(files.any((f) => f.releaseType == 3), isFalse);
    });

    test('accepts_mc unions: 1.21 and 1.21.1 both match', () async {
      final adapter = _ScriptedAdapter([
        _resp(200, filesFixture),
        _resp(200, filesFixture),
      ]);
      final api = _apiWith(adapter);

      final files = await listCompatibleFiles(
        api: api,
        projectId: 238222,
        section: Section.mods,
        modLoader: ModLoader.fabric,
        gameVersions: const ['1.21', '1.21.1'],
        channel: Channel.release,
      );

      expect(
        files.map((f) => f.id),
        containsAll(<int>[5810000, 5814200, 5814100]),
      );
      expect(files.map((f) => f.id).toSet(), hasLength(files.length));
      expect(
        adapter.requests.map((r) => r.uri.queryParameters['gameVersion']),
        ['1.21', '1.21.1'],
      );
      expect(
        adapter.requests.map((r) => r.uri.queryParameters['modLoaderType']),
        ['4', '4'],
      );
    });

    test('exactly 10000 results ends inside the request window', () async {
      final adapter = _ScriptedAdapter([
        for (var index = 0; index < 10000; index += 50)
          _resp(200, _page(index: index, total: 10000, count: 50)),
      ]);
      final files = await listCompatibleFiles(
        api: _apiWith(adapter),
        projectId: 238222,
        section: Section.mods,
        modLoader: ModLoader.fabric,
        gameVersions: const ['1.21.1'],
        channel: Channel.release,
      );
      expect(files, hasLength(10000));
      expect(adapter.requests, hasLength(200));
      for (final request in adapter.requests) {
        final query = request.uri.queryParameters;
        expect(
          int.parse(query['index']!) + int.parse(query['pageSize']!),
          lessThanOrEqualTo(10000),
        );
        expect(query['gameVersion'], '1.21.1');
      }
    });

    test(
      'filtered history beyond the window fails before paging further',
      () async {
        final adapter = _ScriptedAdapter([
          _resp(200, _page(index: 0, total: 10001, count: 50)),
        ]);
        await expectLater(
          listCompatibleFiles(
            api: _apiWith(adapter),
            projectId: 238222,
            section: Section.mods,
            modLoader: ModLoader.fabric,
            gameVersions: const ['1.21.1'],
            channel: Channel.release,
          ),
          throwsA(
            isA<ValidationError>().having(
              (e) => e.message,
              'message',
              allOf(contains('238222'), contains('1.21.1'), contains('10,000')),
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      },
    );

    test('empty history ends after one version-scoped request', () async {
      final adapter = _ScriptedAdapter([
        _resp(200, _page(index: 0, total: 0, count: 0)),
      ]);
      final files = await listCompatibleFiles(
        api: _apiWith(adapter),
        projectId: 238222,
        section: Section.mods,
        modLoader: ModLoader.fabric,
        gameVersions: const ['1.21.1', '1.21.1'],
        channel: Channel.release,
      );
      expect(files, isEmpty);
      expect(
        adapter.requests.single.uri.queryParameters['gameVersion'],
        '1.21.1',
      );
    });

    test('premature empty page rejects incomplete history', () async {
      final adapter = _ScriptedAdapter([
        _resp(200, _page(index: 0, total: 3, count: 2)),
        _resp(200, _page(index: 2, total: 3, count: 0)),
      ]);
      await expectLater(
        listCompatibleFiles(
          api: _apiWith(adapter),
          projectId: 238222,
          section: Section.mods,
          modLoader: ModLoader.fabric,
          gameVersions: const ['1.21.1'],
          channel: Channel.release,
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('incomplete'),
          ),
        ),
      );
      expect(adapter.requests, hasLength(2));
    });

    test(
      'overlapping short pages deduplicate and retain newest ordering',
      () async {
        final adapter = _ScriptedAdapter([
          _resp(200, _page(index: 0, total: 4, count: 2)),
          _resp(
            200,
            jsonEncode({
              'data': [
                _miniFile(id: 1, fileDate: '2025-01-01'),
                _miniFile(id: 3, fileDate: '2025-02-01'),
              ],
              'pagination': {
                'index': 2,
                'pageSize': 50,
                'resultCount': 2,
                'totalCount': 4,
              },
            }),
          ),
        ]);
        final files = await listCompatibleFiles(
          api: _apiWith(adapter),
          projectId: 238222,
          section: Section.mods,
          modLoader: ModLoader.fabric,
          gameVersions: const ['1.21.1'],
          channel: Channel.release,
        );
        expect(files.map((f) => f.id), [3, 0, 1]);
        expect(adapter.requests[1].uri.queryParameters['index'], '2');
      },
    );

    test('plugins+bukkit passes classId=5 and no modLoaderType', () async {
      final adapter = _ScriptedAdapter([_resp(200, filesFixture)]);
      final api = _apiWith(adapter);

      await listCompatibleFiles(
        api: api,
        projectId: 238222,
        section: Section.plugins,
        pluginLoader: PluginLoader.bukkit,
        gameVersions: const ['1.21.1'],
        channel: Channel.release,
      );

      final query = adapter.requests.single.uri.queryParameters;
      expect(query.containsKey('modLoaderType'), isFalse);
    });

    test(
      'plugins+folia throws ArgumentError before any HTTP request',
      () async {
        final adapter = _ScriptedAdapter([_resp(200, filesFixture)]);
        final api = _apiWith(adapter);

        await expectLater(
          listCompatibleFiles(
            api: api,
            projectId: 238222,
            section: Section.plugins,
            pluginLoader: PluginLoader.folia,
            gameVersions: const ['1.21.1'],
            channel: Channel.release,
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(adapter.requests, isEmpty);
      },
    );

    test('pages additional requests until the totalCount is covered', () async {
      // Synthesize a two-page response: 2 files with totalCount=3 on
      // page 1, then 1 file on page 2. listCompatibleFiles must keep
      // paging.
      final page1 = jsonEncode({
        'data': [
          _miniFile(id: 1, fileDate: '2025-01-03T00:00:00Z'),
          _miniFile(id: 2, fileDate: '2025-01-02T00:00:00Z'),
        ],
        'pagination': {
          'index': 0,
          'pageSize': 2,
          'resultCount': 2,
          'totalCount': 3,
        },
      });
      final page2 = jsonEncode({
        'data': [_miniFile(id: 3, fileDate: '2025-01-01T00:00:00Z')],
        'pagination': {
          'index': 2,
          'pageSize': 2,
          'resultCount': 1,
          'totalCount': 3,
        },
      });
      final adapter = _ScriptedAdapter([_resp(200, page1), _resp(200, page2)]);
      final api = _apiWith(adapter);

      final files = await listCompatibleFiles(
        api: api,
        projectId: 238222,
        section: Section.mods,
        modLoader: ModLoader.fabric,
        gameVersions: const ['1.21.1'],
        channel: Channel.release,
      );

      expect(files, hasLength(3));
      expect(adapter.requests, hasLength(2));
      // Second page index should advance.
      expect(adapter.requests[1].uri.queryParameters['index'], '2');
    });
  });

  group('findModBySlug', () {
    test('returns the first mod when search yields one result', () async {
      final body = File(
        'test/fixtures/curseforge/mod_search_response.json',
      ).readAsStringSync();
      final adapter = _ScriptedAdapter([_resp(200, body)]);
      final api = _apiWith(adapter);

      final mod = await findModBySlug(api, slug: 'jei', section: Section.mods);

      expect(mod, isNotNull);
      expect(mod!.slug, 'jei');
      final query = adapter.requests.single.uri.queryParameters;
      expect(query['gameId'], '432');
      expect(query['classId'], '6');
      expect(query['slug'], 'jei');
    });

    test('returns null when search yields no results', () async {
      final body = jsonEncode({
        'data': <Map<String, dynamic>>[],
        'pagination': {
          'index': 0,
          'pageSize': 50,
          'resultCount': 0,
          'totalCount': 0,
        },
      });
      final adapter = _ScriptedAdapter([_resp(200, body)]);
      final api = _apiWith(adapter);

      final mod = await findModBySlug(api, slug: 'nope', section: Section.mods);

      expect(mod, isNull);
    });
  });
}

String _page({required int index, required int total, required int count}) =>
    jsonEncode({
      'data': [
        for (var i = 0; i < count; i++)
          _miniFile(id: index + i, fileDate: '2025-01-01'),
      ],
      'pagination': {
        'index': index,
        'pageSize': 50,
        'resultCount': count,
        'totalCount': total,
      },
    });

CurseForgeApi _apiWith(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return CurseForgeApi(dio, baseUrl: 'https://api.curseforge.com');
}

typedef _ScriptedResponse = ({int status, List<int> bytes});

_ScriptedResponse _resp(int status, String body) =>
    (status: status, bytes: utf8.encode(body));

class _ScriptedAdapter implements HttpClientAdapter {
  final List<_ScriptedResponse> queue;
  final List<RequestOptions> requests = [];

  _ScriptedAdapter(this.queue);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (queue.isEmpty) {
      return ResponseBody.fromString('queue exhausted', 500);
    }
    final r = queue.removeAt(0);
    return ResponseBody.fromBytes(
      r.bytes,
      r.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        Headers.contentLengthHeader: ['${r.bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _miniFile({
  required int id,
  required String fileDate,
  int releaseType = 1,
  List<String> gameVersions = const ['1.21.1', 'Fabric'],
}) {
  return {
    'id': id,
    'modId': 1,
    'displayName': 'mini-$id',
    'fileName': 'mini-$id.jar',
    'releaseType': releaseType,
    'fileDate': fileDate,
    'gameVersions': gameVersions,
    'hashes': <Map<String, dynamic>>[],
    'dependencies': <Map<String, dynamic>>[],
    'downloadUrl': null,
  };
}
