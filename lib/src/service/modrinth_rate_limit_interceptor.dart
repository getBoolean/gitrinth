import 'dart:async';

import 'package:dio/dio.dart';

import 'console.dart';

/// Coordinates outbound calls to the Modrinth API against the published
/// 300 req/min/IP budget. Reads `X-Ratelimit-*` headers on every response,
/// proactively delays requests when the remaining budget falls below
/// [_floor], and on `429` sleeps until the window resets and retries
/// (capped at [_maxRetries]).
///
/// Scoped to the configured Modrinth API host; calls to other upstreams
/// (fabric-meta, forge, neoforge, adoptium) flow through unchanged.
class ModrinthRateLimitInterceptor extends Interceptor {
  final Dio _dio;
  final String _host;
  final Console? _console;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  _RateLimitBudget? _budget;

  ModrinthRateLimitInterceptor({
    required Dio dio,
    required String modrinthBaseUrl,
    Console? console,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _dio = dio,
       _host = Uri.parse(modrinthBaseUrl).host,
       _console = console,
       _sleep = sleep ?? Future.delayed,
       _now = now ?? DateTime.now;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.uri.host != _host) {
      handler.next(options);
      return;
    }
    final budget = _budget;
    if (budget != null && budget.remaining < _floor) {
      final wait = _proactiveWait(budget.resetAt);
      if (wait > Duration.zero) {
        _maybeLog(wait, 'budget low');
        await _sleep(wait);
      }
      _budget = null;
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (response.requestOptions.uri.host == _host) {
      _updateBudgetFrom(response.headers);
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null ||
        response.statusCode != 429 ||
        err.requestOptions.uri.host != _host) {
      handler.next(err);
      return;
    }

    final retries = (err.requestOptions.extra[_retryCountKey] as int?) ?? 0;
    if (retries >= _maxRetries) {
      handler.next(err);
      return;
    }

    final wait = _retryWait(response);
    _maybeLog(wait, 'received HTTP 429');
    await _sleep(wait);
    _budget = null;

    final retryOptions = err.requestOptions.copyWith(
      extra: {
        ...err.requestOptions.extra,
        _retryCountKey: retries + 1,
      },
    );

    try {
      final retried = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(retried);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  void _updateBudgetFrom(Headers headers) {
    final remaining = _parseInt(headers.value('x-ratelimit-remaining'));
    final resetSeconds = _parseInt(headers.value('x-ratelimit-reset'));
    if (remaining == null || resetSeconds == null) return;
    _budget = _RateLimitBudget(
      remaining: remaining,
      resetAt: _now().add(Duration(seconds: resetSeconds)),
    );
  }

  Duration _proactiveWait(DateTime resetAt) {
    final delta = resetAt.difference(_now());
    if (delta <= Duration.zero) return Duration.zero;
    if (delta > _maxSleep) return _maxSleep;
    return delta;
  }

  Duration _retryWait(Response<dynamic> response) {
    final headers = response.headers;
    final retryAfter = _parseInt(headers.value('retry-after'));
    if (retryAfter != null) return _clampRetry(Duration(seconds: retryAfter));
    final reset = _parseInt(headers.value('x-ratelimit-reset'));
    if (reset != null) return _clampRetry(Duration(seconds: reset));
    return _minSleep;
  }

  Duration _clampRetry(Duration d) {
    if (d < _minSleep) return _minSleep;
    if (d > _maxSleep) return _maxSleep;
    return d;
  }

  void _maybeLog(Duration wait, String reason) {
    if (wait < _verboseSleepThreshold) return;
    _console?.io(
      'Modrinth rate limit: $reason, waiting ~${wait.inSeconds}s before request',
    );
  }
}

class _RateLimitBudget {
  final int remaining;
  final DateTime resetAt;

  _RateLimitBudget({required this.remaining, required this.resetAt});
}

int? _parseInt(String? raw) {
  if (raw == null) return null;
  return int.tryParse(raw.trim());
}

const int _floor = 5;
const int _maxRetries = 5;
const Duration _minSleep = Duration(seconds: 1);
const Duration _maxSleep = Duration(seconds: 65);
const Duration _verboseSleepThreshold = Duration(seconds: 2);
const String _retryCountKey = 'gitrinth.modrinthRateLimitRetries';
