import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/modrinth_auth_interceptor.dart';
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
    return ResponseBody.fromString('{}', status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const String _defaultBase = 'https://api.modrinth.com/v2';

Dio _buildDio({
  required Map<String, String> tokens,
  String? envToken,
  int responseStatus = 200,
}) {
  final dio = Dio();
  final adapter = _RecordingAdapter(status: responseStatus);
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(
    ModrinthAuthInterceptor(
      tokensProvider: () => tokens,
      envTokenLookup: () => envToken,
      defaultBaseUrl: _defaultBase,
    ),
  );
  return dio;
}

_RecordingAdapter _adapterOf(Dio dio) =>
    dio.httpClientAdapter as _RecordingAdapter;

void main() {
  group('ModrinthAuthInterceptor.onRequest', () {
    test('attaches stored token for the default Modrinth host', () async {
      final dio = _buildDio(
        tokens: {'https://api.modrinth.com/v2': 'mrp_stored'},
      );
      await dio.get('$_defaultBase/user');
      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers['Authorization'], equals('mrp_stored'));
      expect(
        headers['Authorization'].toString().startsWith('Bearer'),
        isFalse,
        reason: 'Modrinth PATs are bare, no Bearer prefix',
      );
    });

    test('passes through unauthenticated when no token is configured',
        () async {
      final dio = _buildDio(tokens: const {});
      await dio.get('$_defaultBase/user');
      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('GITRINTH_TOKEN overrides stored token on the default host',
        () async {
      final dio = _buildDio(
        tokens: {'https://api.modrinth.com/v2': 'mrp_stored'},
        envToken: 'mrp_env_override',
      );
      await dio.get('$_defaultBase/project/sodium');
      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers['Authorization'], equals('mrp_env_override'));
    });

    test('GITRINTH_TOKEN does not leak to non-default hosts', () async {
      final dio = _buildDio(
        tokens: {'https://my.host/api': 'mrp_other'},
        envToken: 'mrp_env_override',
      );
      await dio.get('https://my.host/api/user');
      final headers = _adapterOf(dio).requests.single.headers;
      expect(headers['Authorization'], equals('mrp_other'));
    });

    test('matches stored key as a path prefix of the request URL', () async {
      final dio = _buildDio(
        tokens: {'https://api.modrinth.com/v2': 'mrp_stored'},
      );
      await dio.get('$_defaultBase/project/sodium/version');
      expect(
        _adapterOf(dio).requests.single.headers['Authorization'],
        equals('mrp_stored'),
      );
    });

    test('preserves an Authorization header set by the caller', () async {
      final dio = _buildDio(
        tokens: {'https://api.modrinth.com/v2': 'mrp_stored'},
      );
      await dio.get(
        '$_defaultBase/user',
        options: Options(headers: {'Authorization': 'mrp_oneshot'}),
      );
      expect(
        _adapterOf(dio).requests.single.headers['Authorization'],
        equals('mrp_oneshot'),
      );
    });
  });

  group('ModrinthAuthInterceptor.onError', () {
    test('wraps 401 from default host in AuthenticationError mentioning login',
        () async {
      final dio = _buildDio(
        tokens: {'https://api.modrinth.com/v2': 'mrp_bad'},
        responseStatus: 401,
      );
      await expectLater(
        dio.get('$_defaultBase/user'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<AuthenticationError>().having(
              (e) => e.message,
              'message',
              contains('gitrinth modrinth login'),
            ),
          ),
        ),
      );
    });

    test('wraps 401 from non-default host in AuthenticationError mentioning '
        'token add', () async {
      final dio = _buildDio(
        tokens: {'https://my.host/api': 'mrp_bad'},
        responseStatus: 401,
      );
      await expectLater(
        dio.get('https://my.host/api/user'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<AuthenticationError>().having(
              (e) => e.message,
              'message',
              contains('gitrinth modrinth token add'),
            ),
          ),
        ),
      );
    });

    test('non-401 errors pass through untouched', () async {
      final dio = _buildDio(
        tokens: const {},
        responseStatus: 500,
      );
      await expectLater(
        dio.get('$_defaultBase/user'),
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
