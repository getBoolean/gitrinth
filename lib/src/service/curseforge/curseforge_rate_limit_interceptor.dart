import 'dart:async';
import 'dart:io' show HttpDate, HttpException;

import 'package:dio/dio.dart';

import '../console.dart';
import 'curseforge_url.dart';

/// Reactive 429 retry handler for the CurseForge read API.
///
/// CurseForge does not publish budget headers, so unlike
/// `ModrinthRateLimitInterceptor` this is purely reactive: when a
/// request comes back 429, the interceptor sleeps (`Retry-After` if
/// present, as delay-seconds or an HTTP-date, otherwise an attempt-ramped backoff inside [_minSleep,
/// _maxSleep]) and retries up to [_maxRetries] times before propagating
/// the original error.
///
/// Scoped to the resolved CurseForge read-API host so other upstreams
/// pass through.
class CurseForgeRateLimitInterceptor extends Interceptor {
  final Dio _dio;
  final Console? _console;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;
  final String _cfHost;

  CurseForgeRateLimitInterceptor({
    required Dio dio,
    String baseUrl = defaultCurseForgeBaseUrl,
    Console? console,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _dio = dio,
       _console = console,
       _cfHost = Uri.parse(baseUrl).host.toLowerCase(),
       _sleep = sleep ?? Future.delayed,
       _now = now ?? DateTime.now;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null ||
        response.statusCode != 429 ||
        err.requestOptions.uri.host.toLowerCase() != _cfHost) {
      handler.next(err);
      return;
    }

    final retries = (err.requestOptions.extra[_retryCountKey] as int?) ?? 0;
    if (retries >= _maxRetries) {
      handler.next(err);
      return;
    }

    final wait = _retryWait(response, retries);
    _maybeLog(wait);
    await _sleep(wait);

    final retryOptions = err.requestOptions.copyWith(
      extra: {...err.requestOptions.extra, _retryCountKey: retries + 1},
    );

    try {
      final retried = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(retried);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Duration _retryWait(Response<dynamic> response, int retries) {
    final retryAfter = _parseRetryAfter(
      response.headers.value('retry-after'),
      _now(),
    );
    if (retryAfter != null) return _clampRetry(retryAfter);
    // No header — ramp backoff with attempt count: 1s, 2s, 4s, 8s, 16s,
    // capped at _maxSleep. Mirrors Modrinth's clamp envelope.
    final ramp = Duration(seconds: 1 << retries);
    return _clampRetry(ramp);
  }

  Duration _clampRetry(Duration d) {
    if (d < _minSleep) return _minSleep;
    if (d > _maxSleep) return _maxSleep;
    return d;
  }

  void _maybeLog(Duration wait) {
    if (wait < _verboseSleepThreshold) return;
    _console?.io(
      'CurseForge rate limit: received HTTP 429, '
      'waiting ~${wait.inSeconds}s before retry',
    );
  }
}

/// RFC 9110 `Retry-After`: delay-seconds or an HTTP-date. Anything else
/// is ignored so the attempt-ramped backoff applies.
Duration? _parseRetryAfter(String? raw, DateTime now) {
  if (raw == null) return null;
  final value = raw.trim();
  final seconds = int.tryParse(value);
  if (seconds != null) return Duration(seconds: seconds);
  try {
    return HttpDate.parse(value).difference(now);
  } on FormatException {
    return null;
  } on HttpException {
    return null;
  }
}

const int _maxRetries = 5;
const Duration _minSleep = Duration(seconds: 1);
const Duration _maxSleep = Duration(seconds: 65);
const Duration _verboseSleepThreshold = Duration(seconds: 2);
const String _retryCountKey = 'gitrinth.curseforgeRateLimitRetries';
