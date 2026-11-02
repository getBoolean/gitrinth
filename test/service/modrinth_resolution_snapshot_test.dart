import 'package:dio/dio.dart';
import 'package:gitrinth/src/model/modrinth/game_version.dart';
import 'package:gitrinth/src/model/modrinth/project.dart';
import 'package:gitrinth/src/model/modrinth/version.dart';
import 'package:gitrinth/src/service/modrinth/modrinth_api.dart';
import 'package:gitrinth/src/service/modrinth/modrinth_api_source.dart';
import 'package:gitrinth/src/service/modrinth/modrinth_resolution_snapshot.dart';
import 'package:gitrinth/src/service/modrinth/modrinth_url.dart';
import 'package:retrofit/retrofit.dart';
import 'package:test/test.dart';

void main() {
  late _Source transport;
  late ModrinthApiSource reads;
  setUp(() {
    transport = _Source();
    reads = ModrinthResolutionSnapshot(transport);
  });

  test(
    'concurrent public reads retain the first response for this resolve',
    () async {
      final api = reads.forHost(null);
      final results = await Future.wait([
        api.getProject('a'),
        api.getProject('a'),
      ]);
      expect(results.map((p) => p.title), everyElement('first'));
      transport.forHost(null).title = 'changed';
      expect((await api.getProject('a')).title, 'first');
      expect(transport.forHost(null).calls, {'project:a': 1});
    },
  );

  test(
    'full host keys normalize case and slash but retain port and path',
    () async {
      await reads.forHost('https://EXAMPLE.test:8443/api/v2/').getProject('a');
      await reads.forHost('https://example.test:8443/api/v2').getProject('a');
      await reads.forHost('https://example.test:9443/api/v2').getProject('a');
      await reads.forHost('https://example.test:8443/other/v2').getProject('a');
      expect(transport.apis.length, 3);
      expect(
        transport.apis.values.map((a) => a.calls['project:a']),
        everyElement(1),
      );
    },
  );

  test(
    'version filters stay separate and selected versions cannot truncate raw lists',
    () async {
      final api = reads.forHost(null);
      final all = await api.listVersions('a');
      final selected = all.where((v) => v.id == 'old').toList();
      expect(selected.single.id, 'old');
      expect(() => all.removeLast(), throwsUnsupportedError);
      expect((await api.listVersions('a')).map((v) => v.id), ['new', 'old']);
      await api.listVersions('a', loadersJson: '["fabric"]');
      await api.listVersions('a', loadersJson: '["forge"]');
      await api.listVersions(
        'a',
        loadersJson: '["fabric"]',
        gameVersionsJson: '["1.21"]',
      );
      await api.listVersions(
        'a',
        loadersJson: '["fabric"]',
        gameVersionsJson: '["1.20"]',
      );
      await api.listVersions(
        'a',
        loadersJson: '["fabric"]',
        gameVersionsJson: '["1.20"]',
      );
      expect(transport.forHost(null).calls.values, everyElement(1));
      expect(transport.forHost(null).calls.length, 5);
    },
  );

  test(
    'member and search data remain immutable and search arguments are isolated',
    () async {
      final api = reads.forHost(null);
      final members = await api.getProjectMembers('a');
      expect(
        () => members.data[0]['user']['username'] = 'changed',
        throwsUnsupportedError,
      );
      await api.getProjectMembers('a');
      final hits = await api.searchProjects(query: 'a', facets: '[]');
      expect(() => hits.data['hits'].clear(), throwsUnsupportedError);
      await api.searchProjects(query: 'a', facets: '[]');
      await api.searchProjects(query: 'b', facets: '[]');
      await api.searchProjects(query: 'a', facets: '[[]]');
      await api.searchProjects(query: 'a', facets: '[]', limit: 40);
      expect(transport.forHost(null).calls.values, everyElement(1));
      expect(transport.forHost(null).calls.length, 5);
    },
  );

  test('auth and non-resolution endpoints are never retained', () async {
    final api = reads.forHost(null);
    for (var i = 0; i < 2; i++) {
      await api.getCurrentUser();
      await api.checkProjectValidity('a');
      await api.getGameVersions();
    }
    expect(transport.forHost(null).calls.values, everyElement(2));
  });

  test(
    'a new resolution observes fresh metadata from the same transport',
    () async {
      expect((await reads.forHost(null).getProject('a')).title, 'first');
      transport.forHost(null).title = 'second';
      final next = ModrinthResolutionSnapshot(transport);
      expect((await next.forHost(null).getProject('a')).title, 'second');
      expect((await reads.forHost(null).getProject('a')).title, 'first');
      expect(transport.forHost(null).calls['project:a'], 2);
    },
  );
}

class _Source implements ModrinthApiSource {
  @override
  final String defaultBaseUrl = 'https://example.test/v2';
  final apis = <String, _Api>{};
  @override
  _Api forHost(String? hostUrl) =>
      apis.putIfAbsent(normalizeServerKey(hostUrl ?? defaultBaseUrl), _Api.new);
}

class _Api implements ModrinthApi {
  final calls = <String, int>{};
  String title = 'first';
  void record(String key) => calls.update(key, (n) => n + 1, ifAbsent: () => 1);
  HttpResponse<dynamic> response(dynamic body) =>
      HttpResponse(body, Response(requestOptions: RequestOptions(path: '/')));
  @override
  Future<Project> getProject(String slug) async {
    record('project:$slug');
    return Project(id: slug, slug: slug, title: title, projectType: 'mod');
  }

  @override
  Future<List<Version>> listVersions(
    String slug, {
    String? loadersJson,
    String? gameVersionsJson,
  }) async {
    record('versions:$slug:$loadersJson:$gameVersionsJson');
    return [
      for (final id in ['new', 'old'])
        Version(
          id: id,
          projectId: slug,
          versionNumber: '1.0',
          files: [],
          dependencies: [],
          loaders: [],
          gameVersions: [],
        ),
    ];
  }

  @override
  Future<HttpResponse<dynamic>> getProjectMembers(String slug) async {
    record('members:$slug');
    return response([
      {
        'user': {'username': 'author'},
      },
    ]);
  }

  @override
  Future<HttpResponse<dynamic>> searchProjects({
    required String query,
    required String facets,
    int limit = 20,
  }) async {
    record('search:$query:$facets:$limit');
    return response({
      'hits': [
        {'project_id': 'a'},
      ],
    });
  }

  @override
  Future<HttpResponse<dynamic>> getCurrentUser() async {
    record('user');
    return response({'username': 'author'});
  }

  @override
  Future<HttpResponse<dynamic>> checkProjectValidity(String slug) async {
    record('check:$slug');
    return response({'id': slug});
  }

  @override
  Future<List<GameVersion>> getGameVersions() async {
    record('game-versions');
    return [];
  }
}
