import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api_factory.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_auth_interceptor.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_publication_receipt.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_publication_service.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_upload_client.dart';
import 'package:gitrinth/src/service/prepared_publication.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A release whose client upload completed and whose dependent server
/// upload timed out, leaving `receipt.server` in the unknown state.
class _UnknownChild {
  final CurseForgePublicationService service;
  final CurseForgePublicationReceiptStore store;
  final Future<PreparedCurseForgePublication> Function() prepare;
  final int Function() uploadRequests;
  final String serverSha1;

  _UnknownChild({
    required this.service,
    required this.store,
    required this.prepare,
    required this.uploadRequests,
    required this.serverSha1,
  });

  PublicationStepState? get serverState =>
      store.read(42, '1.0.0')?.server.state;

  /// A remote record that satisfies every reconciliation condition.
  Map<String, dynamic> matchingRecord({int id = 200}) => {
    'id': id,
    'modId': 42,
    'parentProjectFileId': 100,
    'hashes': [
      {'algo': 1, 'value': serverSha1},
    ],
  };
}

Future<_UnknownChild> _unknownChild({
  required Future<List<Map<String, dynamic>>> Function(int project) listFiles,
}) async {
  final root = Directory.systemTemp.createTempSync('cf_unknown_child_');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final dio = Dio(
    BaseOptions(receiveTimeout: const Duration(milliseconds: 150)),
  );
  addTearDown(() async {
    dio.close(force: true);
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });
  final host = 'http://127.0.0.1:${server.port}';
  final clientManifest = utf8.encode(
    jsonEncode({
      'manifestType': 'minecraftModpack',
      'manifestVersion': 1,
      'name': 'Test',
      'version': '1.0.0',
      'minecraft': {
        'version': '1.21.1',
        'modLoaders': [
          {'id': 'fabric-0.16.0', 'primary': true},
        ],
      },
      'files': [],
      'overrides': 'overrides',
    }),
  );
  final client = File(p.join(root.path, 'client.zip'))
    ..writeAsBytesSync(
      ZipEncoder().encode(
        Archive()..addFile(
          ArchiveFile('manifest.json', clientManifest.length, clientManifest),
        ),
      ),
    );
  final payload = utf8.encode('server mod');
  final marker = utf8.encode(
    jsonEncode({
      'formatVersion': 1,
      'artifactType': 'gitrinth-server-distribution',
      'slug': 'test',
      'version': '1.0.0',
      'minecraft': '1.21.1',
      'loader': {'id': 'fabric', 'version': '0.16.0'},
      'runtimeBundled': false,
      'files': [
        {
          'path': 'mods/server.jar',
          'sha256': sha256.convert(payload).toString(),
        },
      ],
    }),
  );
  final archive = Archive()
    ..addFile(
      ArchiveFile('gitrinth-server-distribution.json', marker.length, marker),
    )
    ..addFile(ArchiveFile('mods/server.jar', payload.length, payload));
  final distribution = File(p.join(root.path, 'server.zip'))
    ..writeAsBytesSync(ZipEncoder().encode(archive));
  final metadata = {
    'displayName': 'Test 1.0.0',
    'releaseType': 'release',
    'isMarkedForManualRelease': false,
  };
  final plan = PreparedPublication(
    target: SourceKind.curseforge,
    serverUrl: host,
    token: 'never-store-this-token',
    artifact: client,
    curseforgeProjectId: 42,
    payload: metadata,
    dependentServer: PreparedPublication(
      target: SourceKind.curseforge,
      serverUrl: host,
      token: 'never-store-this-token',
      artifact: distribution,
      curseforgeProjectId: 42,
      payload: metadata,
      role: PublicationArtifactRole.server,
    ),
  );
  var requests = 0;
  server.listen((request) async {
    requests++;
    await request.drain<void>();
    // The parent upload answers; the child upload stalls into a timeout.
    if (requests == 1) {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"id":100}');
      await request.response.close();
    }
  });
  final store = CurseForgePublicationReceiptStore(root.path);
  final service = CurseForgePublicationService(
    uploadClient: CurseForgeUploadClient(dio, baseUrl: host),
    store: store,
    readFile: (project, id) async => {
      'id': id,
      'modId': project,
      'displayName': 'Test 1.0.0',
      'releaseType': 1,
      'isServerPack': false,
    },
    listFiles: listFiles,
  );
  Future<PreparedCurseForgePublication> prepare() => service.prepare(
    plan: plan,
    slug: 'test',
    version: '1.0.0',
    displayName: 'Test 1.0.0',
    minecraft: '1.21.1',
    loaderId: 'fabric',
    loaderVersion: '0.16.0',
    clientLoaderToken: 'fabric',
  );
  await expectLater(
    service.publish(await prepare()),
    throwsA(
      isA<CurseForgePublicationFailure>()
          .having((e) => e.parentId, 'parent ID', 100)
          .having((e) => e.unknownOutcome, 'unknown outcome', isTrue),
    ),
  );
  expect(requests, 2);
  expect(store.read(42, '1.0.0')?.client.state, PublicationStepState.complete);
  expect(store.read(42, '1.0.0')?.server.state, PublicationStepState.unknown);
  return _UnknownChild(
    service: service,
    store: store,
    prepare: prepare,
    uploadRequests: () => requests,
    serverSha1: sha1.convert(distribution.readAsBytesSync()).toString(),
  );
}

void main() {
  test(
    'timed-out child is unknown until remote hash and parent reconcile it',
    () async {
      final remote = <Map<String, dynamic>>[];
      final fixture = await _unknownChild(listFiles: (_) async => remote);
      expect(
        File(fixture.store.path(42, '1.0.0')).readAsStringSync(),
        isNot(contains('never-store-this-token')),
      );
      await expectLater(
        fixture.prepare(),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('unknown'),
          ),
        ),
      );
      expect(fixture.uploadRequests(), 2);
      remote.add(fixture.matchingRecord());
      final recovered = await fixture.service.publish(await fixture.prepare());
      expect(recovered.childId, 200);
      expect(fixture.uploadRequests(), 2);
      expect(fixture.serverState, PublicationStepState.complete);
    },
  );

  group('unknown child stays unknown without exactly one exact match', () {
    final cases = <String, List<Map<String, dynamic>> Function(_UnknownChild)>{
      'wrong parent': (f) => [
        {...f.matchingRecord(), 'parentProjectFileId': 101},
      ],
      'missing parent': (f) => [
        {...f.matchingRecord()}..remove('parentProjectFileId'),
      ],
      'wrong project': (f) => [
        {...f.matchingRecord(), 'modId': 43},
      ],
      'wrong hash': (f) => [
        {
          ...f.matchingRecord(),
          'hashes': [
            {'algo': 1, 'value': 'f' * 40},
          ],
        },
      ],
      'hash of another algorithm': (f) => [
        {
          ...f.matchingRecord(),
          'hashes': [
            {'algo': 2, 'value': f.serverSha1},
          ],
        },
      ],
      'missing hashes': (f) => [
        {...f.matchingRecord()}..remove('hashes'),
      ],
      'zero ID': (f) => [f.matchingRecord(id: 0)],
      'negative ID': (f) => [f.matchingRecord(id: -200)],
      'non-integer ID': (f) => [
        {...f.matchingRecord(), 'id': '200'},
      ],
      'two matching records': (f) => [
        f.matchingRecord(),
        f.matchingRecord(id: 201),
      ],
    };
    for (final MapEntry(key: label, value: records) in cases.entries) {
      test(label, () async {
        final remote = <Map<String, dynamic>>[];
        final fixture = await _unknownChild(listFiles: (_) async => remote);
        remote.addAll(records(fixture));

        await expectLater(
          fixture.prepare(),
          throwsA(
            isA<ValidationError>().having(
              (e) => e.message,
              'message',
              allOf(contains('unknown'), contains('no duplicate POST')),
            ),
          ),
        );

        expect(fixture.uploadRequests(), 2, reason: 'no further POST');
        expect(fixture.serverState, PublicationStepState.unknown);
      });
    }
  });

  test(
    'reconciliation walks the full remote history through the read API',
    () async {
      final read = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => read.close(force: true));
      final readHost = 'http://127.0.0.1:${read.port}';
      final factory = CurseForgeApiFactory(
        console: const Console(),
        auth: CurseForgeAuthInterceptor(
          envTokenLookup: () => 'read-key',
          baseUrl: readHost,
        ),
        offline: () => false,
        baseUrl: readHost,
      );
      addTearDown(factory.close);
      final fixture = await _unknownChild(listFiles: factory.publicationFiles);
      final pages = <Map<String, String>>[];
      // Page one is full of unrelated history; the match is on page two.
      final history = [
        for (var i = 0; i < 50; i++)
          {
            'id': 1000 + i,
            'modId': 42,
            'parentProjectFileId': 7,
            'hashes': <Object>[],
          },
        fixture.matchingRecord(),
      ];
      read.listen((request) async {
        expect(request.uri.path, '/v1/mods/42/files');
        expect(request.headers.value('x-api-key'), 'read-key');
        pages.add(request.uri.queryParameters);
        final index = int.parse(request.uri.queryParameters['index']!);
        final size = int.parse(request.uri.queryParameters['pageSize']!);
        final page = history.skip(index).take(size).toList();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': page,
            'pagination': {
              'index': index,
              'pageSize': size,
              'resultCount': page.length,
              'totalCount': history.length,
            },
          }),
        );
        await request.response.close();
      });

      final recovered = await fixture.service.publish(await fixture.prepare());

      expect(recovered.childId, 200);
      expect(pages.map((q) => q['index']), ['0', '50']);
      expect(fixture.uploadRequests(), 2);
      expect(fixture.serverState, PublicationStepState.complete);
    },
  );

  test(
    'upload HTTP rejection does not invoke generic retry interceptors',
    () async {
      final root = Directory.systemTemp.createTempSync('cf_post_rejection_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = Dio();
      addTearDown(() async {
        dio.close(force: true);
        await server.close(force: true);
        root.deleteSync(recursive: true);
      });
      var requests = 0;
      var retries = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            retries++;
            handler.next(error);
          },
        ),
      );
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.statusCode = 429;
        await request.response.close();
      });
      final artifact = File(p.join(root.path, 'client.zip'))
        ..writeAsBytesSync([1]);
      await expectLater(
        CurseForgeUploadClient(
          dio,
          baseUrl: 'http://127.0.0.1:${server.port}',
        ).upload(
          projectId: 42,
          token: 'token',
          archive: artifact,
          metadata: {},
        ),
        throwsA(
          isA<CurseForgeUploadFailure>().having(
            (e) => e.unknownOutcome,
            'unknown',
            isFalse,
          ),
        ),
      );
      expect(requests, 1);
      expect(retries, 0);
    },
  );

  test('release keys cannot escape the project receipt directory', () {
    const store = CurseForgePublicationReceiptStore('C:/project');
    final path = store.path(42, '../../other-release');
    expect(p.basename(path), matches(RegExp(r'^[a-f0-9]{64}\.json$')));
    expect(
      p.dirname(path),
      p.join('C:/project', '.gitrinth', 'publications', 'curseforge', '42'),
    );
  });
}
