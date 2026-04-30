import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge_rate_limit_interceptor.dart';
import 'package:test/test.dart';

typedef _ScriptedResponse = ({
  int status,
  Map<String, List<String>> headers,
  List<int> bytes,
});

class _ScriptedAdapter implements HttpClientAdapter {
  final List<_ScriptedResponse> queue;
  final List<RequestOptions> requests = [];

  _ScriptedAdapter(this.queue);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (queue.isEmpty) {
      return ResponseBody.fromString('queue exhausted', 500);
    }
    final r = queue.removeAt(0);
    return ResponseBody.fromBytes(
      r.bytes,
      r.status,
      headers: {
        ...r.headers,
        Headers.contentLengthHeader: ['${r.bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _cfBase = 'https://api.curseforge.com';

_ScriptedResponse _ok({String body = '{}'}) =>
    (status: 200, headers: const {}, bytes: utf8.encode(body));

_ScriptedResponse _rateLimited({
  Map<String, List<String>> headers = const {},
}) => (status: 429, headers: headers, bytes: utf8.encode('{"error":"rate"}'));

void main() {
  group('CurseForgeRateLimitInterceptor', () {
    test('429 with Retry-After: 2 sleeps ~2s and retries', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'retry-after': ['2'],
          },
        ),
        _ok(body: '{"ok":true}'),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        CurseForgeRateLimitInterceptor(
          dio: dio,
          sleep: (d) async => sleeps.add(d),
        ),
      );

      final response = await dio.get<dynamic>('$_cfBase/v1/mods/1');

      expect(response.statusCode, 200);
      expect(sleeps, [const Duration(seconds: 2)]);
      expect(adapter.requests, hasLength(2));
    });

    test('429 without Retry-After ramps backoff with attempt count up to a 65s '
        'cap', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(),
        _rateLimited(),
        _rateLimited(),
        _rateLimited(),
        _rateLimited(),
        _rateLimited(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        CurseForgeRateLimitInterceptor(
          dio: dio,
          sleep: (d) async => sleeps.add(d),
        ),
      );

      await expectLater(
        dio.get<dynamic>('$_cfBase/v1/mods/1'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            429,
          ),
        ),
      );

      // 5 retries → 5 sleeps. Backoff ramps with attempt count and is
      // bounded by the [_minSleep, _maxSleep] envelope.
      expect(sleeps, hasLength(5));
      for (final s in sleeps) {
        expect(s, greaterThanOrEqualTo(const Duration(seconds: 1)));
        expect(s, lessThanOrEqualTo(const Duration(seconds: 65)));
      }
      expect(sleeps.last, greaterThanOrEqualTo(sleeps.first));
      expect(adapter.requests, hasLength(6));
    });

    test('429 from a non-CF host passes through unchanged', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'retry-after': ['10'],
          },
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        CurseForgeRateLimitInterceptor(
          dio: dio,
          sleep: (d) async => sleeps.add(d),
        ),
      );

      await expectLater(
        dio.get<dynamic>('https://example.com/api'),
        throwsA(isA<DioException>()),
      );

      expect(sleeps, isEmpty);
      expect(adapter.requests, hasLength(1));
    });

    test('429 from the configured CF host override is retried', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'retry-after': ['2'],
          },
        ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        CurseForgeRateLimitInterceptor(
          dio: dio,
          baseUrl: 'https://cf-proxy.example.test',
          sleep: (d) async => sleeps.add(d),
        ),
      );

      final response = await dio.get<dynamic>(
        'https://cf-proxy.example.test/v1/mods/1',
      );

      expect(response.statusCode, 200);
      expect(sleeps, [const Duration(seconds: 2)]);
      expect(adapter.requests, hasLength(2));
    });

    test(
      'on exhausted retries, propagates the original DioException',
      () async {
        final adapter = _ScriptedAdapter([
          for (var i = 0; i < 6; i++)
            _rateLimited(
              headers: {
                'retry-after': ['1'],
              },
            ),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final sleeps = <Duration>[];
        dio.interceptors.add(
          CurseForgeRateLimitInterceptor(
            dio: dio,
            sleep: (d) async => sleeps.add(d),
          ),
        );

        await expectLater(
          dio.get<dynamic>('$_cfBase/v1/mods/1'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              429,
            ),
          ),
        );

        expect(sleeps, hasLength(5));
        expect(adapter.requests, hasLength(6));
      },
    );

    test('Console.io fires when the sleep is at or above the verbose '
        'threshold', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'retry-after': ['3'],
          },
        ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final console = _CapturingConsole();
      dio.interceptors.add(
        CurseForgeRateLimitInterceptor(
          dio: dio,
          console: console,
          sleep: (_) async {},
        ),
      );

      await dio.get<dynamic>('$_cfBase/v1/mods/1');

      expect(console.details, hasLength(1));
      expect(console.details.single, contains('CurseForge rate limit'));
      expect(console.details.single, contains('~3s'));
    });
  });
}

class _CapturingConsole extends Console {
  final List<String> details = [];

  _CapturingConsole() : super(level: LogLevel.io);

  @override
  void io(String message) {
    details.add(message);
  }
}
