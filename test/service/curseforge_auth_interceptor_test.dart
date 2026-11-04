import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_auth_interceptor.dart';
import 'package:test/test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final int status;
  final List<RequestOptions> requests = [];

  _RecordingAdapter({this.status = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _cfBase = 'https://api.curseforge.com';

Dio _buildDio({
  String? envToken,
  String? defaultKey,
  String baseUrl = _cfBase,
  int responseStatus = 200,
}) {
  final dio = Dio();
  dio.httpClientAdapter = _RecordingAdapter(status: responseStatus);
  dio.interceptors.add(
    CurseForgeAuthInterceptor(
      envTokenLookup: () => envToken,
      baseUrl: baseUrl,
      defaultKeyResolver: defaultKey == null ? null : () => defaultKey,
    ),
  );
  return dio;
}

_RecordingAdapter _adapterOf(Dio dio) =>
    dio.httpClientAdapter as _RecordingAdapter;

Options _authed([Map<String, dynamic>? extra]) =>
    Options(extra: {kCurseForgeAuthRequired: true, ...?extra});

void main() {
  group('CurseForgeAuthInterceptor.onRequest', () {
    test('env value wins over the build-time default', () async {
      final dio = _buildDio(envToken: 'ENV', defaultKey: 'DEF');

      await dio.get('$_cfBase/v1/mods/1', options: _authed());

      expect(_adapterOf(dio).requests.single.headers['x-api-key'], 'ENV');
    });

    test(
      'falls back to the build-time default key when env is absent',
      () async {
        final dio = _buildDio(defaultKey: 'DEF');

        await dio.get('$_cfBase/v1/mods/1', options: _authed());

        expect(_adapterOf(dio).requests.single.headers['x-api-key'], 'DEF');
      },
    );

    test('does not attach x-api-key for non-CF hosts', () async {
      final dio = _buildDio(envToken: 'ENV');

      await dio.get('https://example.com/api/x', options: _authed());

      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers.containsKey('x-api-key'), isFalse);
    });

    test('attaches x-api-key for the configured CF host override', () async {
      final dio = _buildDio(
        envToken: 'ENV',
        baseUrl: 'https://cf-proxy.example.test',
      );

      await dio.get(
        'https://cf-proxy.example.test/v1/mods/1',
        options: _authed(),
      );

      expect(_adapterOf(dio).requests.single.headers['x-api-key'], 'ENV');
    });

    test('does not attach x-api-key when the marker extra is absent', () async {
      final dio = _buildDio(envToken: 'ENV');

      await dio.get('$_cfBase/v1/mods/1');

      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers.containsKey('x-api-key'), isFalse);
    });

    test(
      'rejects auth-gated request when the embedded default decodes empty',
      () async {
        final dio = _buildDio(defaultKey: '');

        await expectLater(
          dio.get('$_cfBase/v1/mods/1', options: _authed()),
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

        expect(
          _adapterOf(dio).requests,
          isEmpty,
          reason: 'request must not reach the network without a key',
        );
      },
    );
  });

  group('CurseForgeAuthInterceptor.onError', () {
    test(
      'wraps a 401 response in AuthenticationError pointing at token add',
      () async {
        final dio = _buildDio(envToken: 'ENV', responseStatus: 401);

        await expectLater(
          dio.get('$_cfBase/v1/mods/1', options: _authed()),
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

    test('non-401 errors pass through untouched', () async {
      final dio = _buildDio(envToken: 'ENV', responseStatus: 500);

      await expectLater(
        dio.get('$_cfBase/v1/mods/1', options: _authed()),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isNot(isA<AuthenticationError>()),
          ),
        ),
      );
    });

    test('401 from non-CF host is passed through unchanged', () async {
      final dio = _buildDio(responseStatus: 401);

      await expectLater(
        dio.get('https://example.com/api/x'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isNot(isA<AuthenticationError>()),
          ),
        ),
      );
    });
  });

  group('CurseForgeAuthInterceptor origin check', () {
    test('does not attach x-api-key when only the port differs', () async {
      final dio = _buildDio(
        envToken: 'ENV',
        baseUrl: 'https://cf-proxy.example.test:8443',
      );

      await dio.get(
        'https://cf-proxy.example.test/v1/mods/1',
        options: _authed(),
      );

      expect(
        _adapterOf(dio).requests.single.headers.containsKey('x-api-key'),
        isFalse,
      );
    });

    test('does not attach x-api-key when only the scheme differs', () async {
      final dio = _buildDio(envToken: 'ENV');

      await dio.get('http://api.curseforge.com/v1/mods/1', options: _authed());

      expect(
        _adapterOf(dio).requests.single.headers.containsKey('x-api-key'),
        isFalse,
      );
    });
  });

  group('CurseForgeAuthInterceptor redirects over real HTTP', () {
    late HttpServer source;
    late HttpServer target;
    late List<String?> targetKeys;
    late Dio dio;
    late String base;

    setUp(() async {
      source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      targetKeys = [];
      target.listen((request) async {
        targetKeys.add(request.headers.value('x-api-key'));
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      base = 'http://127.0.0.1:${source.port}';
      dio = Dio()
        ..interceptors.add(
          CurseForgeAuthInterceptor(
            envTokenLookup: () => 'fixture-only',
            baseUrl: base,
          ),
        );
    });

    tearDown(() async {
      dio.close(force: true);
      await source.close(force: true);
      await target.close(force: true);
    });

    void redirectTo(String location, {int status = 302}) {
      source.listen((request) async {
        request.response.statusCode = status;
        request.response.headers.set('location', location);
        await request.response.close();
      });
    }

    Matcher refusedRedirect() => throwsA(
      isA<DioException>().having(
        (e) => e.error,
        'error',
        isA<UserError>().having(
          (e) => e.message,
          'message',
          allOf(contains('redirected'), contains('GITRINTH_CURSEFORGE_URL')),
        ),
      ),
    );

    for (final (label, location) in [
      ('host', (int port) => 'http://localhost:$port/capture'),
      ('port', (int port) => 'http://127.0.0.1:$port/capture'),
    ]) {
      test('refuses a cross-origin redirect that changes the $label', () async {
        redirectTo(location(target.port));

        await expectLater(
          dio.get('$base/v1/mods/1', options: _authed()),
          refusedRedirect(),
        );

        expect(targetKeys, isEmpty, reason: 'the key must not be replayed');
      });
    }

    test('refuses a redirect that changes the scheme', () async {
      redirectTo('https://127.0.0.1:${target.port}/capture', status: 307);

      await expectLater(
        dio.get('$base/v1/mods/1', options: _authed()),
        refusedRedirect(),
      );

      expect(targetKeys, isEmpty);
    });

    test(
      'refuses redirects even when the caller accepts every status',
      () async {
        redirectTo('http://localhost:${target.port}/capture');

        await expectLater(
          dio.get(
            '$base/v1/mods/1',
            options: _authed()..validateStatus = (_) => true,
          ),
          refusedRedirect(),
        );

        expect(targetKeys, isEmpty);
      },
    );

    test('unauthenticated requests keep default redirect handling', () async {
      redirectTo('http://localhost:${target.port}/capture');

      final response = await dio.get<dynamic>('$base/v1/mods/1');

      expect(response.statusCode, 200);
      expect(targetKeys, [null]);
    });
  });
}
