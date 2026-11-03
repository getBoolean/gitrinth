import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_publication_receipt.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_publication_service.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_upload_client.dart';
import 'package:gitrinth/src/service/prepared_publication.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'timed-out child is unknown until remote hash and parent reconcile it',
    () async {
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
              ArchiveFile(
                'manifest.json',
                clientManifest.length,
                clientManifest,
              ),
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
          ArchiveFile(
            'gitrinth-server-distribution.json',
            marker.length,
            marker,
          ),
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
        if (requests == 1) {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"id":100}');
          await request.response.close();
        }
      });
      final remote = <Map<String, dynamic>>[];
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
        listFiles: (_) async => remote,
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
      final prepared = await prepare();
      await expectLater(
        service.publish(prepared),
        throwsA(
          isA<CurseForgePublicationFailure>()
              .having((e) => e.parentId, 'parent ID', 100)
              .having((e) => e.unknownOutcome, 'unknown outcome', isTrue),
        ),
      );
      expect(requests, 2);
      final saved = store.read(42, '1.0.0');
      expect(saved?.client.state, PublicationStepState.complete);
      expect(saved?.server.state, PublicationStepState.unknown);
      expect(
        File(store.path(42, '1.0.0')).readAsStringSync(),
        isNot(contains('never-store-this-token')),
      );
      await expectLater(
        prepare(),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('unknown'),
          ),
        ),
      );
      expect(requests, 2);
      remote.add({
        'id': 200,
        'modId': 42,
        'parentProjectFileId': 100,
        'hashes': [
          {
            'algo': 1,
            'value': sha1.convert(distribution.readAsBytesSync()).toString(),
          },
        ],
      });
      final recovered = await service.publish(await prepare());
      expect(recovered.childId, 200);
      expect(requests, 2);
      expect(
        store.read(42, '1.0.0')?.server.state,
        PublicationStepState.complete,
      );
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
