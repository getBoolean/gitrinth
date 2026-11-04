import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/service/cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('GitrinthCache.listCachedVersions', () {
    late Directory tempRoot;
    late GitrinthCache cache;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('cachelist_');
      cache = GitrinthCache(root: tempRoot.path);
    });
    tearDown(() => tempRoot.deleteSync(recursive: true));

    const host = 'https://api.modrinth.com/v2';

    void writeSidecar(
      String projectId,
      String versionId,
      Map<String, dynamic> v,
    ) {
      final path = cache.modrinthVersionMetadataPath(
        host: host,
        projectId: projectId,
        versionId: versionId,
      );
      Directory(p.dirname(path)).createSync(recursive: true);
      File(path).writeAsStringSync(jsonEncode(v));
    }

    test('returns every parsed version under <host>/<projectId>/', () {
      writeSidecar(
        'p1',
        'v1',
        _versionPayload(id: 'v1', projectId: 'p1', version: '1.0.0'),
      );
      writeSidecar(
        'p1',
        'v2',
        _versionPayload(id: 'v2', projectId: 'p1', version: '1.1.0'),
      );
      writeSidecar(
        'p2',
        'vx',
        _versionPayload(id: 'vx', projectId: 'p2', version: '0.1.0'),
      );

      final got = cache.listCachedVersions(host, 'p1').toList();
      expect(got.map((v) => v.id), unorderedEquals(['v1', 'v2']));
    });

    test('returns an empty iterable when projectId never cached', () {
      expect(cache.listCachedVersions(host, 'never-seen'), isEmpty);
    });

    test('skips malformed sidecars (logs warn but does not throw)', () {
      writeSidecar(
        'p1',
        'good',
        _versionPayload(id: 'good', projectId: 'p1', version: '1.0.0'),
      );
      final badPath = cache.modrinthVersionMetadataPath(
        host: host,
        projectId: 'p1',
        versionId: 'bad',
      );
      Directory(p.dirname(badPath)).createSync(recursive: true);
      File(badPath).writeAsStringSync('{not json');

      final got = cache.listCachedVersions(host, 'p1').toList();
      expect(got.map((v) => v.id), equals(['good']));
    });

    test('default host and custom host map to different cache segments', () {
      const customHost = 'https://modrinth.example.com';
      expect(
        GitrinthCache.hostCacheSegment(host),
        isNot(equals(GitrinthCache.hostCacheSegment(customHost))),
      );
    });
  });
}

Map<String, dynamic> _versionPayload({
  required String id,
  required String projectId,
  required String version,
}) => {
  'id': id,
  'project_id': projectId,
  'version_number': version,
  'loaders': ['fabric'],
  'game_versions': ['1.21.1'],
  'files': const <Map<String, dynamic>>[],
  'dependencies': const <Map<String, dynamic>>[],
  'date_published': '2026-01-01T00:00:00Z',
  'version_type': 'release',
};
