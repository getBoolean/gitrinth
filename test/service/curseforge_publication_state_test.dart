import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api_factory.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_auth_interceptor.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_publication_receipt.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_publication_service.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_upload_client.dart';
import 'package:gitrinth/src/service/prepared_publication.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Fixture {
  final Directory root;
  final CurseForgePublicationService service;
  final Future<PreparedCurseForgePublication> Function(
    List<PreparedPublication>,
  )
  _prepare;
  Future<PreparedCurseForgePublication> prepare([
    List<PreparedPublication> peers = const [],
  ]) => _prepare(peers);
  final CurseForgePublicationReceiptStore store;
  final int Function() requests;
  _Fixture(this.root, this.service, this._prepare, this.store, this.requests);
}

Future<_Fixture> _fixture({
  bool checkDurability = false,
  bool stallChild = false,
  bool stallReadback = false,
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
  late final CurseForgePublicationReceiptStore store;
  server.listen((request) async {
    if (request.method == 'GET') return;
    requests++;
    if (checkDurability) {
      final recorded = store.read(42, '1.0.0');
      expect(
        recorded?.client.state,
        requests == 1
            ? PublicationStepState.inFlight
            : PublicationStepState.complete,
      );
      expect(
        recorded?.server.state,
        requests == 1
            ? PublicationStepState.pending
            : PublicationStepState.inFlight,
      );
    }
    await request.drain<void>();
    if (stallChild && requests == 2) return;
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"id":${100 + requests}}');
    await request.response.close();
  });
  final remote = <Map<String, dynamic>>[];
  store = CurseForgePublicationReceiptStore(root.path);
  final readFactory = CurseForgeApiFactory(
    console: const Console(),
    auth: CurseForgeAuthInterceptor(
      envTokenLookup: () => 'fixture',
      baseUrl: host,
    ),
    offline: () => false,
    baseUrl: host,
  );
  addTearDown(readFactory.close);
  readFactory.api;
  final readClient = readFactory.dio;
  if (readClient == null) throw StateError('missing client');
  readClient.options.receiveTimeout = const Duration(milliseconds: 25);
  final service = CurseForgePublicationService(
    uploadClient: CurseForgeUploadClient(dio, baseUrl: host),
    store: store,
    readFile: (project, id) async {
      if (stallReadback) return readFactory.publicationFile(project, id);
      return {
        'id': id,
        'modId': project,
        'displayName': 'Test 1.0.0',
        'releaseType': 1,
        'isServerPack': false,
      };
    },
    listFiles: (_) async => remote,
  );
  Future<PreparedCurseForgePublication> prepare(
    List<PreparedPublication> peers,
  ) => service.prepare(
    plan: plan,
    slug: 'test',
    version: '1.0.0',
    displayName: 'Test 1.0.0',
    minecraft: '1.21.1',
    loaderId: 'fabric',
    loaderVersion: '0.16.0',
    clientLoaderToken: 'fabric',
    peers: peers,
  );
  return _Fixture(root, service, prepare, store, () => requests);
}

void main() {
  for (final existingPending in [false, true]) {
    test(
      'stale prepared receipt cannot duplicate uploads (existing: $existingPending)',
      () async {
        final fixture = await _fixture();
        if (existingPending) {
          fixture.store.writeIfUnchanged(
            (await fixture.prepare()).receipt,
            null,
          );
        }
        final first = await fixture.prepare();
        final stale = await fixture.prepare();
        await fixture.service.publish(first);
        await expectLater(
          fixture.service.publish(stale),
          throwsA(isA<CurseForgePublicationFailure>()),
        );
        expect(fixture.requests(), 2);
        expect(fixture.store.read(42, '1.0.0')?.childId, 102);
      },
    );
  }
  test(
    'overlapping pending publications allow only one upload sequence',
    () async {
      final fixture = await _fixture();
      fixture.store.writeIfUnchanged((await fixture.prepare()).receipt, null);
      final first = await fixture.prepare();
      final second = await fixture.prepare();
      Future<Object> publish(PreparedCurseForgePublication plan) async {
        try {
          return await fixture.service.publish(plan);
        } catch (e) {
          return e;
        }
      }

      final results = await Future.wait([publish(first), publish(second)]);
      expect(results.whereType<CurseForgePublicationResult>(), hasLength(1));
      expect(results.whereType<CurseForgePublicationFailure>(), hasLength(1));
      expect(fixture.requests(), 2);
      expect(fixture.store.read(42, '1.0.0')?.childId, 102);
    },
  );
  test(
    'parent and child are durably in flight before their POST begins',
    () async {
      final fixture = await _fixture(checkDurability: true);
      await fixture.service.publish(await fixture.prepare());
      expect(fixture.requests(), 2);
    },
  );
  test('receipt write failure sends no upload', () async {
    final fixture = await _fixture();
    final plan = await fixture.prepare();
    File(
      p.join(fixture.root.path, '.gitrinth'),
    ).writeAsStringSync('obstruction');
    await expectLater(
      fixture.service.publish(plan),
      throwsA(isA<CurseForgePublicationFailure>()),
    );
    expect(fixture.requests(), 0);
  });
  test('stale preparation cannot overwrite an unknown child outcome', () async {
    final fixture = await _fixture(stallChild: true);
    final first = await fixture.prepare();
    final stale = await fixture.prepare();
    await expectLater(
      fixture.service.publish(first),
      throwsA(isA<CurseForgePublicationFailure>()),
    );
    await expectLater(
      fixture.service.publish(stale),
      throwsA(isA<CurseForgePublicationFailure>()),
    );
    expect(fixture.requests(), 2);
    final saved = fixture.store.read(42, '1.0.0');
    expect(saved?.parentId, 101);
    expect(saved?.server.state, PublicationStepState.unknown);
  });
  test('stalled readback returns pending and reuses both upload IDs', () async {
    final fixture = await _fixture(stallReadback: true);
    final first = await fixture.service.publish(await fixture.prepare());
    expect(first.classificationConfirmed, isFalse);
    final second = await fixture.service.publish(await fixture.prepare());
    expect(second.parentId, first.parentId);
    expect(second.childId, first.childId);
    expect(fixture.requests(), 2);
  });
  test('stale peer state cannot erase a completed peer upload', () async {
    final fixture = await _fixture();
    final peer = PreparedPublication(
      target: SourceKind.modrinth,
      serverUrl: 'https://api.modrinth.com/v2',
      token: 'fixture',
      artifact: File(p.join(fixture.root.path, 'client.zip')),
      payload: {},
    );
    final first = await fixture.prepare([peer]);
    final stale = await fixture.prepare([peer]);
    await fixture.service.startPeer(first, peer);
    fixture.service.completePeer(first, peer, 'mr-version');
    await expectLater(
      fixture.service.startPeer(stale, peer),
      throwsA(isA<ValidationError>()),
    );
    expect(
      fixture.store.read(42, '1.0.0')?.peers.values.single.id,
      'mr-version',
    );
    expect(fixture.requests(), 0);
  });
}
