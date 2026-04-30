import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge_api.dart';
import 'package:gitrinth/src/service/curseforge_api_factory.dart';
import 'package:gitrinth/src/service/curseforge_auth_interceptor.dart';
import 'package:gitrinth/src/service/curseforge_error_interceptor.dart';
import 'package:gitrinth/src/service/curseforge_rate_limit_interceptor.dart';
import 'package:gitrinth/src/service/curseforge_url.dart';
import 'package:gitrinth/src/service/offline_guard_interceptor.dart';
import 'package:gitrinth/src/version.dart';
import 'package:test/test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final int status;
  final String body;
  final List<RequestOptions> requests = [];

  _RecordingAdapter({this.status = 200, this.body = _emptyDataEnvelope});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _emptyDataEnvelope =
    '{"data":{"id":1,"gameId":432,"name":"x","slug":"x","classId":6,"latestFiles":[],"allowModDistribution":true}}';
const String _emptySearchEnvelope =
    '{"data":[],"pagination":{"index":0,"pageSize":50,"resultCount":0,"totalCount":0}}';
const String _baseUrl = 'https://api.curseforge.com';

Dio _buildDio({int responseStatus = 200, String body = _emptyDataEnvelope}) {
  final dio = Dio();
  dio.httpClientAdapter = _RecordingAdapter(status: responseStatus, body: body);
  return dio;
}

_RecordingAdapter _adapterOf(Dio dio) =>
    dio.httpClientAdapter as _RecordingAdapter;

void main() {
  group('CurseForgeApi retrofit interface', () {
    test('getMod issues GET /v1/mods/{id} with cf_auth extra', () async {
      final dio = _buildDio();
      final api = CurseForgeApi(dio, baseUrl: _baseUrl);

      await api.getMod(238222);

      final req = _adapterOf(dio).requests.single;
      expect(req.method, 'GET');
      expect(req.uri.toString(), '$_baseUrl/v1/mods/238222');
      expect(req.extra[kCurseForgeAuthRequired], isTrue);
    });

    test(
      'searchMods issues GET /v1/mods/search with the queried filters',
      () async {
        final dio = _buildDio(body: _emptySearchEnvelope);
        final api = CurseForgeApi(dio, baseUrl: _baseUrl);

        await api.searchMods(gameId: 432, slug: 'jei', classId: 6);

        final req = _adapterOf(dio).requests.single;
        expect(req.method, 'GET');
        final uri = req.uri;
        expect(uri.path, '/v1/mods/search');
        expect(uri.queryParameters['gameId'], '432');
        expect(uri.queryParameters['slug'], 'jei');
        expect(uri.queryParameters['classId'], '6');
        expect(req.extra[kCurseForgeAuthRequired], isTrue);
      },
    );

    test('searchMods omits null query params from the wire request', () async {
      final dio = _buildDio(body: _emptySearchEnvelope);
      final api = CurseForgeApi(dio, baseUrl: _baseUrl);

      await api.searchMods(gameId: 432, slug: 'jei');

      final req = _adapterOf(dio).requests.single;
      expect(req.uri.queryParameters.containsKey('classId'), isFalse);
      expect(req.uri.queryParameters.containsKey('searchFilter'), isFalse);
    });

    test(
      'listFiles issues GET /v1/mods/{id}/files with the queried filters',
      () async {
        final dio = _buildDio(body: _emptySearchEnvelope);
        final api = CurseForgeApi(dio, baseUrl: _baseUrl);

        await api.listFiles(
          238222,
          gameVersion: '1.21.1',
          modLoaderType: 4,
          pageSize: 200,
        );

        final req = _adapterOf(dio).requests.single;
        expect(req.method, 'GET');
        final uri = req.uri;
        expect(uri.path, '/v1/mods/238222/files');
        expect(uri.queryParameters['gameVersion'], '1.21.1');
        expect(uri.queryParameters['modLoaderType'], '4');
        expect(uri.queryParameters['pageSize'], '200');
        expect(req.extra[kCurseForgeAuthRequired], isTrue);
      },
    );

    test('getFile issues GET /v1/mods/{modId}/files/{fileId}', () async {
      final dio = _buildDio(
        body:
            '{"data":{"id":1,"modId":2,"displayName":"a","fileName":"a","releaseType":1,"fileDate":"2025-01-01T00:00:00Z","gameVersions":[],"hashes":[],"dependencies":[],"downloadUrl":null}}',
      );
      final api = CurseForgeApi(dio, baseUrl: _baseUrl);

      await api.getFile(238222, 4567);

      final req = _adapterOf(dio).requests.single;
      expect(req.method, 'GET');
      expect(req.uri.toString(), '$_baseUrl/v1/mods/238222/files/4567');
      expect(req.extra[kCurseForgeAuthRequired], isTrue);
    });
  });

  group('CurseForgeApiFactory', () {
    CurseForgeApiFactory factoryFor({
      bool offline = false,
      String baseUrl = _baseUrl,
    }) {
      return CurseForgeApiFactory(
        console: const Console(),
        auth: CurseForgeAuthInterceptor(
          envTokenLookup: () => null,
          baseUrl: baseUrl,
          defaultKeyResolver: () => 'TEST',
        ),
        offline: () => offline,
        baseUrl: baseUrl,
      );
    }

    test('api returns the same instance across calls', () {
      final factory = factoryFor();
      final a = factory.api;
      final b = factory.api;
      expect(identical(a, b), isTrue);
      factory.close();
    });

    test(
      'Dio has interceptors in [OfflineGuard, Auth, RateLimit, Error] order',
      () {
        final factory = factoryFor();
        // Force the bundle to build.
        factory.api;
        // Filter out anything Dio prepends internally (e.g. its
        // ImplyContentTypeInterceptor); assert only the four we added.
        final ours = factory.dio!.interceptors
            .where(
              (i) =>
                  i is OfflineGuardInterceptor ||
                  i is CurseForgeAuthInterceptor ||
                  i is CurseForgeRateLimitInterceptor ||
                  i is CurseForgeErrorInterceptor,
            )
            .toList(growable: false);
        expect(ours, hasLength(4));
        expect(ours[0], isA<OfflineGuardInterceptor>());
        expect(ours[1], isA<CurseForgeAuthInterceptor>());
        expect(ours[2], isA<CurseForgeRateLimitInterceptor>());
        expect(ours[3], isA<CurseForgeErrorInterceptor>());
        factory.close();
      },
    );

    test('User-Agent header is gitrinth/<version>', () {
      final factory = factoryFor();
      factory.api;
      expect(
        factory.dio!.options.headers['User-Agent'],
        'gitrinth/$packageVersion (+github.com/getBoolean/gitrinth)',
      );
      factory.close();
    });

    test('configured baseUrl receives CurseForge auth', () async {
      final factory = factoryFor(baseUrl: 'https://cf-proxy.example.test');
      final adapter = _RecordingAdapter();
      factory.api;
      factory.dio!.httpClientAdapter = adapter;

      await factory.api.getMod(1);

      final req = adapter.requests.single;
      expect(req.uri.toString(), 'https://cf-proxy.example.test/v1/mods/1');
      expect(req.headers['x-api-key'], 'TEST');
      factory.close();
    });

    test('close() disposes the bundle so the next api access rebuilds', () {
      final factory = factoryFor();
      final first = factory.api;
      factory.close();
      expect(factory.dio, isNull);
      final second = factory.api;
      expect(identical(first, second), isFalse);
      factory.close();
    });

    test('OfflineGuardInterceptor blocks calls when offline=true', () async {
      final factory = factoryFor(offline: true);
      // Replace the adapter with a recorder so a leak through the guard
      // would be visible.
      final adapter = _RecordingAdapter();
      factory.api;
      factory.dio!.httpClientAdapter = adapter;

      await expectLater(
        factory.api.getMod(1),
        throwsA(
          isA<DioException>()
              .having((e) => e.error, 'error', isA<UserError>())
              .having(
                (e) => (e.error as UserError).message,
                'message',
                contains('offline'),
              ),
        ),
      );
      expect(adapter.requests, isEmpty);
      factory.close();
    });
  });

  group('CurseForgeErrorInterceptor', () {
    Dio withErrorInterceptor({required int status, String body = '{}'}) {
      final dio = Dio();
      dio.httpClientAdapter = _RecordingAdapter(status: status, body: body);
      dio.interceptors.add(CurseForgeErrorInterceptor());
      return dio;
    }

    test('401 maps to AuthenticationError', () async {
      final dio = withErrorInterceptor(status: 401);
      await expectLater(
        dio.get('$_baseUrl/v1/mods/1'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<AuthenticationError>(),
          ),
        ),
      );
    });

    test('403 maps to AuthenticationError', () async {
      final dio = withErrorInterceptor(status: 403);
      await expectLater(
        dio.get('$_baseUrl/v1/mods/1'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<AuthenticationError>(),
          ),
        ),
      );
    });

    test('404 on /v1/mods/<id> names the mod identifier', () async {
      final dio = withErrorInterceptor(status: 404);
      await expectLater(
        dio.get('$_baseUrl/v1/mods/238222'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains("'238222' not found"),
            ),
          ),
        ),
      );
    });

    test('5xx falls through to a generic UserError', () async {
      final dio = withErrorInterceptor(
        status: 503,
        body: '{"error":"upstream unavailable"}',
      );
      await expectLater(
        dio.get('$_baseUrl/v1/mods/1'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('upstream unavailable'),
            ),
          ),
        ),
      );
    });

    test(
      'does not double-wrap a GitrinthException already on the error',
      () async {
        // Build a chain where the auth interceptor produces an
        // AuthenticationError first, then the error interceptor sees it.
        final dio = Dio();
        dio.httpClientAdapter = _RecordingAdapter(status: 401);
        dio.interceptors.add(
          CurseForgeAuthInterceptor(
            envTokenLookup: () => null,
            defaultKeyResolver: () => 'TEST',
          ),
        );
        dio.interceptors.add(CurseForgeErrorInterceptor());

        await expectLater(
          dio.get(
            '$_baseUrl/v1/mods/1',
            options: Options(extra: {kCurseForgeAuthRequired: true}),
          ),
          throwsA(
            isA<DioException>().having(
              (e) => e.error,
              'error',
              isA<AuthenticationError>().having(
                (e) => e.message,
                'message',
                contains('GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64'),
              ),
            ),
          ),
        );
      },
    );
  });
}
