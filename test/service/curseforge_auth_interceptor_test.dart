import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/curseforge_api.dart';
import 'package:gitrinth/src/service/curseforge_auth_interceptor.dart';
import 'package:gitrinth/src/service/curseforge_url.dart';
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
  required Map<String, String> tokens,
  String? envToken,
  String? defaultKey,
  int responseStatus = 200,
}) {
  final dio = Dio();
  dio.httpClientAdapter = _RecordingAdapter(status: responseStatus);
  dio.interceptors.add(
    CurseForgeAuthInterceptor(
      tokensProvider: () => tokens,
      envTokenLookup: () => envToken,
      tokenKey: curseForgeTokenKey,
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
    test('env value wins over user-config and embedded default', () async {
      final dio = _buildDio(
        tokens: {curseForgeTokenKey: 'USR'},
        envToken: 'ENV',
        defaultKey: 'DEF',
      );

      await dio.get('$_cfBase/v1/mods/1', options: _authed());

      expect(_adapterOf(dio).requests.single.headers['x-api-key'], 'ENV');
    });

    test('user-config beats embedded default', () async {
      final dio = _buildDio(
        tokens: {curseForgeTokenKey: 'USR'},
        defaultKey: 'DEF',
      );

      await dio.get('$_cfBase/v1/mods/1', options: _authed());

      expect(_adapterOf(dio).requests.single.headers['x-api-key'], 'USR');
    });

    test('falls back to the embedded default key when env and user-config '
        'are absent', () async {
      final dio = _buildDio(tokens: const {}, defaultKey: 'DEF');

      await dio.get('$_cfBase/v1/mods/1', options: _authed());

      expect(_adapterOf(dio).requests.single.headers['x-api-key'], 'DEF');
    });

    test('does not attach x-api-key for non-CF hosts', () async {
      final dio = _buildDio(tokens: {curseForgeTokenKey: 'USR'});

      await dio.get('https://example.com/api/x', options: _authed());

      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers.containsKey('x-api-key'), isFalse);
    });

    test('does not attach x-api-key when the marker extra is absent', () async {
      final dio = _buildDio(tokens: {curseForgeTokenKey: 'USR'});

      await dio.get('$_cfBase/v1/mods/1');

      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers.containsKey('x-api-key'), isFalse);
    });

    test(
      'rejects auth-gated request when the embedded default decodes empty',
      () async {
        final dio = _buildDio(tokens: const {}, defaultKey: '');

        await expectLater(
          dio.get('$_cfBase/v1/mods/1', options: _authed()),
          throwsA(
            isA<DioException>().having(
              (e) => e.error,
              'error',
              isA<AuthenticationError>().having(
                (e) => e.message,
                'message',
                contains('gitrinth token add curseforge.com'),
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
        final dio = _buildDio(
          tokens: {curseForgeTokenKey: 'USR'},
          responseStatus: 401,
        );

        await expectLater(
          dio.get('$_cfBase/v1/mods/1', options: _authed()),
          throwsA(
            isA<DioException>().having(
              (e) => e.error,
              'error',
              isA<AuthenticationError>().having(
                (e) => e.message,
                'message',
                contains('gitrinth token add curseforge.com'),
              ),
            ),
          ),
        );
      },
    );

    test('non-401 errors pass through untouched', () async {
      final dio = _buildDio(
        tokens: {curseForgeTokenKey: 'USR'},
        responseStatus: 500,
      );

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
      final dio = _buildDio(tokens: const {}, responseStatus: 401);

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
}
