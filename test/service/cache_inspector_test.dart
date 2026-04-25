import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/cache_inspector.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _StaticAdapter implements HttpClientAdapter {
  /// url -> (status, bytes)
  final Map<String, ({int status, List<int> bytes})> responses;

  _StaticAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    final r = responses[url];
    if (r == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromBytes(
      r.bytes,
      r.status,
      headers: {
        Headers.contentLengthHeader: ['${r.bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tempRoot;
  late GitrinthCache cache;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_inspector_');
    cache = GitrinthCache(root: tempRoot.path);
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  String sha512Hex(List<int> bytes) => sha512.convert(bytes).toString();

  void seedModrinth({
    required String projectId,
    required String versionId,
    required String filename,
    required String body,
    String? url,
    String? declaredSha512,
  }) {
    final dir = Directory(p.join(cache.modrinthRoot, projectId, versionId));
    dir.createSync(recursive: true);
    final bytes = utf8.encode(body);
    File(p.join(dir.path, filename)).writeAsBytesSync(bytes);
    final version = <String, Object?>{
      'id': versionId,
      'project_id': projectId,
      'version_number': '1.0.0',
      'files': [
        {
          'url': url ?? 'https://example.invalid/$filename',
          'filename': filename,
          'hashes': {
            'sha1': '0' * 40,
            'sha512': declaredSha512 ?? sha512Hex(bytes),
          },
          'size': bytes.length,
          'primary': true,
        },
      ],
      'dependencies': <Object?>[],
      'loaders': <String>['fabric'],
      'game_versions': <String>['1.21.1'],
    };
    File(cache.modrinthVersionMetadataPath(
      projectId: projectId,
      versionId: versionId,
    )).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(version),
    );
  }

  void seedUrl({
    required String expectedSha512,
    required String filename,
    required String body,
  }) {
    final destPath = cache.urlPath(sha512: expectedSha512, filename: filename);
    Directory(p.dirname(destPath)).createSync(recursive: true);
    File(destPath).writeAsBytesSync(utf8.encode(body));
  }

  Downloader buildDownloader(Map<String, ({int status, List<int> bytes})> responses) {
    final dio = Dio()..httpClientAdapter = _StaticAdapter(responses);
    return Downloader(dio: dio, cache: cache);
  }

  group('walkArtifacts', () {
    test('returns empty when cache root has no subtrees', () {
      final inspector = CacheInspector(cache);
      expect(inspector.walkArtifacts().toList(), isEmpty);
    });

    test('skips version.json siblings under modrinth/', () {
      seedModrinth(
        projectId: 'P',
        versionId: 'V',
        filename: 'mod.jar',
        body: 'payload',
      );
      final inspector = CacheInspector(cache);
      final list = inspector.walkArtifacts().toList();
      expect(list, hasLength(1));
      expect(list.single.filename, 'mod.jar');
      expect(list.single.source, 'modrinth');
      expect(list.single.projectId, 'P');
      expect(list.single.versionId, 'V');
    });

    test('encodes url-cached sha512 from the path', () {
      final body = 'whatever';
      final hash = sha512Hex(utf8.encode(body));
      seedUrl(expectedSha512: hash, filename: 'mod.jar', body: body);
      final inspector = CacheInspector(cache);
      final list = inspector.walkArtifacts().toList();
      expect(list, hasLength(1));
      expect(list.single.source, 'url');
      expect(list.single.sha512, hash);
    });
  });

  group('repair', () {
    test('verifies a healthy modrinth file without re-downloading', () async {
      seedModrinth(
        projectId: 'P',
        versionId: 'V',
        filename: 'mod.jar',
        body: 'payload',
      );
      final inspector = CacheInspector(cache);
      // No responses configured; if it tries to download, the adapter
      // returns 404 and the test fails.
      final downloader = buildDownloader({});
      final outcome = await inspector.repair(
        downloader,
        console: const Console(),
      );
      expect(outcome.verified, 1);
      expect(outcome.redownloaded, 0);
      expect(outcome.deleted, 0);
      expect(outcome.skippedOrphans, isEmpty);
      expect(outcome.stillCorrupt, isEmpty);
    });

    test('re-downloads a corrupt modrinth file from version.json url',
        () async {
      const url = 'https://example.invalid/mod.jar';
      const goodBody = 'good content';
      final goodSha = sha512Hex(utf8.encode(goodBody));

      // Seed a corrupt jar (wrong bytes) but a version.json declaring
      // the *good* sha. The downloader will be asked to fetch from
      // [url] and will return [goodBody] from the fake adapter.
      seedModrinth(
        projectId: 'P',
        versionId: 'V',
        filename: 'mod.jar',
        body: 'TAMPERED',
        url: url,
        declaredSha512: goodSha,
      );
      // Sanity: version.json declares goodSha, not the tampered body's hash.
      expect(
        File(cache.modrinthVersionMetadataPath(projectId: 'P', versionId: 'V'))
            .readAsStringSync(),
        contains(goodSha),
      );

      final downloader = buildDownloader({
        url: (status: 200, bytes: utf8.encode(goodBody)),
      });
      final inspector = CacheInspector(cache);
      final outcome = await inspector.repair(
        downloader,
        console: const Console(),
      );

      expect(outcome.redownloaded, 1);
      expect(outcome.verified, 0);
      expect(outcome.stillCorrupt, isEmpty);
      // The on-disk file is now the good content.
      final destPath = cache.modrinthPath(
        projectId: 'P',
        versionId: 'V',
        filename: 'mod.jar',
      );
      expect(File(destPath).readAsStringSync(), goodBody);
    });

    test('throws CacheCorruptionError when re-download still mismatches',
        () async {
      const url = 'https://example.invalid/mod.jar';
      final declaredSha = sha512Hex(utf8.encode('expected'));
      seedModrinth(
        projectId: 'P',
        versionId: 'V',
        filename: 'mod.jar',
        body: 'TAMPERED',
        url: url,
        declaredSha512: declaredSha,
      );
      // The fake server returns wrong bytes too — sha512 will mismatch
      // both before and after re-download.
      final downloader = buildDownloader({
        url: (status: 200, bytes: utf8.encode('still wrong')),
      });
      final inspector = CacheInspector(cache);
      await expectLater(
        inspector.repair(downloader, console: const Console()),
        throwsA(isA<CacheCorruptionError>()),
      );
    });

    test('deletes a corrupt url-cached file and prunes empty parents',
        () async {
      final expected = sha512Hex(utf8.encode('original'));
      seedUrl(
        expectedSha512: expected,
        filename: 'mod.jar',
        body: 'TAMPERED',
      );
      final downloader = buildDownloader({});
      final inspector = CacheInspector(cache);
      final outcome = await inspector.repair(
        downloader,
        console: const Console(),
      );
      expect(outcome.deleted, 1);
      expect(outcome.verified, 0);
      final filePath = cache.urlPath(sha512: expected, filename: 'mod.jar');
      expect(File(filePath).existsSync(), isFalse);
      expect(
        Directory(p.join(cache.urlRoot, expected.substring(0, 2)))
            .existsSync(),
        isFalse,
      );
    });

    test('skips modrinth jar with missing version.json (orphan)', () async {
      final dir = Directory(p.join(cache.modrinthRoot, 'P', 'V'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'orphan.jar')).writeAsStringSync('garbage');
      final downloader = buildDownloader({});
      final inspector = CacheInspector(cache);
      final outcome = await inspector.repair(
        downloader,
        console: const Console(),
      );
      expect(outcome.skippedOrphans, hasLength(1));
      expect(outcome.verified, 0);
      // Still on disk.
      expect(File(p.join(dir.path, 'orphan.jar')).existsSync(), isTrue);
    });

    test('skips modrinth jar when version.json lacks files array', () async {
      final dir = Directory(p.join(cache.modrinthRoot, 'P', 'V'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'jar.jar')).writeAsStringSync('garbage');
      File(p.join(dir.path, 'version.json'))
          .writeAsStringSync('{"dependencies":[]}'); // old-format
      final downloader = buildDownloader({});
      final inspector = CacheInspector(cache);
      final outcome = await inspector.repair(
        downloader,
        console: const Console(),
      );
      expect(outcome.skippedOrphans, hasLength(1));
    });
  });

  group('wipe', () {
    test('deletes contents but preserves the cache root', () async {
      seedModrinth(
        projectId: 'P',
        versionId: 'V',
        filename: 'mod.jar',
        body: 'payload',
      );
      final inspector = CacheInspector(cache);
      await inspector.wipe();
      expect(Directory(cache.root).existsSync(), isTrue);
      expect(Directory(cache.modrinthRoot).existsSync(), isFalse);
    });
  });
}
