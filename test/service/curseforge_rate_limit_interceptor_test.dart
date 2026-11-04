import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_rate_limit_interceptor.dart';
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

    test('429 without Retry-After doubles the backoff on each attempt '
        '(1, 2, 4, 8, 16s)', () async {
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

      // 5 retries → 5 sleeps, doubling per attempt. Five attempts stay
      // below the 65s cap; the cap is covered by the Retry-After cases.
      expect(sleeps, [
        for (final s in [1, 2, 4, 8, 16]) Duration(seconds: s),
      ]);
      expect(adapter.requests, hasLength(6));
    });

    final now = DateTime.utc(2026, 11, 4, 12);
    for (final (label, header, expected) in [
      ('below the minimum (0)', '0', 1),
      ('negative', '-5', 1),
      ('above the maximum', '120', 65),
      ('padded with whitespace', ' 7 ', 7),
      ('an HTTP-date 30s ahead', HttpDate.format(now.add(_s(30))), 30),
      ('an HTTP-date far ahead', HttpDate.format(now.add(_s(600))), 65),
      ('an HTTP-date in the past', HttpDate.format(now.subtract(_s(30))), 1),
      // Malformed values fall back to the first backoff step.
      ('malformed (word)', 'soon', 1),
      ('malformed (decimal)', '2.5', 1),
      ('malformed (empty)', '', 1),
    ]) {
      test('Retry-After $label sleeps ${expected}s', () async {
        final adapter = _ScriptedAdapter([
          _rateLimited(
            headers: {
              'retry-after': [header],
            },
          ),
          _ok(),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final sleeps = <Duration>[];
        dio.interceptors.add(
          CurseForgeRateLimitInterceptor(
            dio: dio,
            sleep: (d) async => sleeps.add(d),
            now: () => now,
          ),
        );

        final response = await dio.get<dynamic>('$_cfBase/v1/mods/1');

        expect(response.statusCode, 200);
        expect(sleeps, [Duration(seconds: expected)]);
      });
    }

    test('malformed Retry-After keeps ramping on later attempts', () async {
      final adapter = _ScriptedAdapter([
        for (var i = 0; i < 3; i++)
          _rateLimited(
            headers: {
              'retry-after': ['soon'],
            },
          ),
        _ok(),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final sleeps = <Duration>[];
      dio.interceptors.add(
        CurseForgeRateLimitInterceptor(
          dio: dio,
          sleep: (d) async => sleeps.add(d),
        ),
      );

      await dio.get<dynamic>('$_cfBase/v1/mods/1');

      expect(sleeps, [
        for (final s in [1, 2, 4]) Duration(seconds: s),
      ]);
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

Duration _s(int seconds) => Duration(seconds: seconds);
