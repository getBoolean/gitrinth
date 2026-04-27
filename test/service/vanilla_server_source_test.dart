import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/vanilla_server_source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late GitrinthCache cache;
  late Dio dio;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_vanilla_src_');
    cache = GitrinthCache(root: p.join(tempRoot.path, 'cache'));
    cache.ensureRoot();
    dio = Dio();
  });

  tearDown(() {
    dio.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<HttpServer> startStub({
    required Map<String, ({int status, String? body, List<int>? bytes})>
    responses,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final r = responses[req.uri.path];
      if (r == null) {
        req.response.statusCode = 404;
      } else {
        req.response.statusCode = r.status;
        if (r.bytes != null) {
          req.response.add(r.bytes!);
        } else if (r.body != null) {
          req.response.write(r.body);
        }
      }
      await req.response.close();
    });
    return server;
  }

  test(
    'verifies sha1 returned by piston-meta and succeeds on a match',
    () async {
      final jarBytes = utf8.encode('FAKE-VANILLA-SERVER-JAR');
      final goodSha1 = sha1.convert(jarBytes).toString();

      final stub = await startStub(
        responses: {
          '/mc/game/version_manifest_v2.json': (
            status: 200,
            body: jsonEncode({
              'versions': [
                {'id': '1.21.1', 'url': 'http://EMBED/1.21.1.json'},
              ],
            }),
            bytes: null,
          ),
          '/1.21.1.json': (
            status: 200,
            body: jsonEncode({
              'downloads': {
                'server': {'url': 'http://EMBED/server.jar', 'sha1': goodSha1},
              },
            }),
            bytes: null,
          ),
          '/server.jar': (status: 200, body: null, bytes: jarBytes),
        },
      );
      addTearDown(() => stub.close(force: true));

      final base = 'http://127.0.0.1:${stub.port}';
      // Rewrite the per-version + jar URLs the manifest hands back so the
      // downloader hits the loopback stub instead of going to the
      // (embedded) absolute URLs.
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.path = options.path.replaceFirst('http://EMBED', base);
            handler.next(options);
          },
        ),
      );
      final src = VanillaServerSource(
        dio: dio,
        downloader: Downloader(dio: dio, cache: cache),
        cache: cache,
        versionManifestUrl: '$base/mc/game/version_manifest_v2.json',
      );

      final file = await src.fetchServerJar(
        mcVersion: '1.21.1',
        offline: false,
      );
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), jarBytes);
    },
  );

  test('throws checksum-mismatch UserError when the jar bytes do not '
      'match the advertised sha1', () async {
    final jarBytes = utf8.encode('CORRUPT-JAR-BYTES');
    // sha1 of *different* content — e.g. of "honest" bytes that aren't
    // what the server actually serves.
    final claimedSha1 = sha1.convert(utf8.encode('SOMETHING-ELSE')).toString();

    final stub = await startStub(
      responses: {
        '/mc/game/version_manifest_v2.json': (
          status: 200,
          body: jsonEncode({
            'versions': [
              {'id': '1.21.1', 'url': 'http://EMBED/1.21.1.json'},
            ],
          }),
          bytes: null,
        ),
        '/1.21.1.json': (
          status: 200,
          body: jsonEncode({
            'downloads': {
              'server': {'url': 'http://EMBED/server.jar', 'sha1': claimedSha1},
            },
          }),
          bytes: null,
        ),
        '/server.jar': (status: 200, body: null, bytes: jarBytes),
      },
    );
    addTearDown(() => stub.close(force: true));

    final base = 'http://127.0.0.1:${stub.port}';
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.path = options.path.replaceFirst('http://EMBED', base);
          handler.next(options);
        },
      ),
    );
    final src = VanillaServerSource(
      dio: dio,
      downloader: Downloader(dio: dio, cache: cache),
      cache: cache,
      versionManifestUrl: '$base/mc/game/version_manifest_v2.json',
    );

    await expectLater(
      src.fetchServerJar(mcVersion: '1.21.1', offline: false),
      throwsA(
        isA<UserError>().having(
          (e) => e.message,
          'message',
          contains('checksum mismatch'),
        ),
      ),
    );
  });
}
