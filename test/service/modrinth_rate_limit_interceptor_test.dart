import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/modrinth_rate_limit_interceptor.dart';
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

class _CapturingConsole extends Console {
  final List<String> details = [];

  _CapturingConsole() : super(level: LogLevel.io);

  @override
  void io(String message) {
    details.add(message);
  }
}

const String _modrinthBase = 'https://api.modrinth.com/v2';

_ScriptedResponse _ok({
  Map<String, List<String>> headers = const {},
  String body = '{}',
}) => (status: 200, headers: headers, bytes: utf8.encode(body));

_ScriptedResponse _rateLimited({
  Map<String, List<String>> headers = const {},
  String body = '{"error":"rate limited"}',
}) => (status: 429, headers: headers, bytes: utf8.encode(body));

void main() {
  group('ModrinthRateLimitInterceptor', () {
    test('onResponse updates the budget — subsequent request throttles when '
        'remaining < floor', () async {
      final adapter = _ScriptedAdapter([
        _ok(
          headers: {
            'x-ratelimit-remaining': ['2'],
            'x-ratelimit-reset': ['10'],
          },
        ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      final frozenNow = DateTime.utc(2026, 1, 1, 12);
      dio.interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: _modrinthBase,
          sleep: (d) async => sleeps.add(d),
          now: () => frozenNow,
        ),
      );

      await dio.get<dynamic>('$_modrinthBase/tag/game_version');
      await dio.get<dynamic>('$_modrinthBase/tag/game_version');

      expect(sleeps, hasLength(1));
      expect(sleeps.single, const Duration(seconds: 10));
    });

    test('onResponse is a no-op for non-Modrinth hosts', () async {
      final adapter = _ScriptedAdapter([
        _ok(
          headers: {
            'x-ratelimit-remaining': ['0'],
            'x-ratelimit-reset': ['30'],
          },
        ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: _modrinthBase,
          sleep: (d) async => sleeps.add(d),
          now: () => DateTime.utc(2026),
        ),
      );

      await dio.get<dynamic>('https://meta.fabricmc.net/v2/versions/loader');
      await dio.get<dynamic>('$_modrinthBase/tag/game_version');

      expect(sleeps, isEmpty);
    });

    test(
      'onRequest does not throttle when remaining stays at or above floor',
      () async {
        final adapter = _ScriptedAdapter([
          _ok(
            headers: {
              'x-ratelimit-remaining': ['5'],
              'x-ratelimit-reset': ['30'],
            },
          ),
          _ok(),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final sleeps = <Duration>[];
        dio.interceptors.add(
          ModrinthRateLimitInterceptor(
            dio: dio,
            modrinthBaseUrl: _modrinthBase,
            sleep: (d) async => sleeps.add(d),
            now: () => DateTime.utc(2026),
          ),
        );

        await dio.get<dynamic>('$_modrinthBase/tag/game_version');
        await dio.get<dynamic>('$_modrinthBase/tag/game_version');

        expect(sleeps, isEmpty);
      },
    );

    test(
      '429 with X-Ratelimit-Reset: 0 triggers minSleep then succeeds on retry',
      () async {
        final adapter = _ScriptedAdapter([
          _rateLimited(
            headers: {
              'x-ratelimit-reset': ['0'],
            },
          ),
          _ok(body: '{"ok":true}'),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final sleeps = <Duration>[];
        dio.interceptors.add(
          ModrinthRateLimitInterceptor(
            dio: dio,
            modrinthBaseUrl: _modrinthBase,
            sleep: (d) async => sleeps.add(d),
            now: () => DateTime.utc(2026),
          ),
        );

        final response = await dio.get<dynamic>(
          '$_modrinthBase/tag/game_version',
        );

        expect(response.statusCode, 200);
        expect(sleeps, [const Duration(seconds: 1)]);
        expect(adapter.requests, hasLength(2));
      },
    );

    test('Retry-After header is preferred over X-Ratelimit-Reset', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'retry-after': ['7'],
            'x-ratelimit-reset': ['30'],
          },
        ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: _modrinthBase,
          sleep: (d) async => sleeps.add(d),
          now: () => DateTime.utc(2026),
        ),
      );

      await dio.get<dynamic>('$_modrinthBase/tag/game_version');

      expect(sleeps, [const Duration(seconds: 7)]);
    });

    test('429 retries exhaust at maxRetries and surface the error', () async {
      final adapter = _ScriptedAdapter([
        for (var i = 0; i < 6; i++)
          _rateLimited(
            headers: {
              'x-ratelimit-reset': ['0'],
            },
          ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: _modrinthBase,
          sleep: (d) async => sleeps.add(d),
          now: () => DateTime.utc(2026),
        ),
      );

      await expectLater(
        dio.get<dynamic>('$_modrinthBase/tag/game_version'),
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
    });

    test('Console.detail fires when sleep >= verbose threshold', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'x-ratelimit-reset': ['3'],
          },
        ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final console = _CapturingConsole();
      dio.interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: _modrinthBase,
          console: console,
          sleep: (_) async {},
          now: () => DateTime.utc(2026),
        ),
      );

      await dio.get<dynamic>('$_modrinthBase/tag/game_version');

      expect(console.details, hasLength(1));
      expect(console.details.single, contains('~3s'));
      expect(console.details.single, contains('Modrinth rate limit'));
    });

    test('Console.detail does NOT fire for sleeps below threshold', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'x-ratelimit-reset': ['1'],
          },
        ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final console = _CapturingConsole();
      dio.interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: _modrinthBase,
          console: console,
          sleep: (_) async {},
          now: () => DateTime.utc(2026),
        ),
      );

      await dio.get<dynamic>('$_modrinthBase/tag/game_version');

      expect(console.details, isEmpty);
    });

    test('429 from a non-Modrinth host is passed through unchanged', () async {
      final adapter = _ScriptedAdapter([
        _rateLimited(
          headers: {
            'x-ratelimit-reset': ['10'],
          },
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: _modrinthBase,
          sleep: (d) async => sleeps.add(d),
          now: () => DateTime.utc(2026),
        ),
      );

      await expectLater(
        dio.get<dynamic>('https://meta.fabricmc.net/v2/versions/loader'),
        throwsA(isA<DioException>()),
      );

      expect(sleeps, isEmpty);
      expect(adapter.requests, hasLength(1));
    });
  });
}
