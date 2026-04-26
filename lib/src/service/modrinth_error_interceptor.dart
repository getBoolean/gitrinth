import 'dart:convert';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';

class ModrinthErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // A prior interceptor (e.g. auth) may have already mapped this to
    // a typed gitrinth exception — don't shroud it in UserError.
    if (err.error is GitrinthException) {
      handler.next(err);
      return;
    }

    final response = err.response;
    final reqUri = err.requestOptions.uri;
    final status = response?.statusCode;

    // The `/project/<slug>/check` route uses 404 as its documented "slug is
    // available" success case. Pass these errors through unwrapped so callers
    // can inspect the original status code without a UserError shroud.
    if (reqUri.path.endsWith('/check')) {
      handler.next(err);
      return;
    }

    // Modrinth returns 404 on `/project/<slug>` and `/project/<slug>/version`
    // when the slug doesn't exist (filter mismatches return an empty array
    // with 200). Surface the slug directly instead of the raw URL + status.
    if (status == 404) {
      final slug = _projectSlugFromPath(reqUri.path);
      if (slug != null) {
        _rejectWith(
          err,
          handler,
          UserError(
            "Modrinth project '$slug' not found. Verify the slug on modrinth.com.",
          ),
        );
        return;
      }
    }

    String? bodyMessage;
    if (response != null) {
      final data = response.data;
      if (data is Map && data['error'] is String) {
        bodyMessage = data['error'] as String;
      } else if (data is String && data.isNotEmpty) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map && decoded['error'] is String) {
            bodyMessage = decoded['error'] as String;
          }
        } catch (_) {
          // Not JSON; ignore.
        }
      }
    }
    final summary = bodyMessage != null
        ? '$bodyMessage (HTTP ${status ?? '?'})'
        : 'HTTP ${status ?? '?'} ${response?.statusMessage ?? err.message ?? ''}'
              .trim();
    _rejectWith(
      err,
      handler,
      UserError('Modrinth request failed for $reqUri: $summary'),
    );
  }

  void _rejectWith(
    DioException err,
    ErrorInterceptorHandler handler,
    UserError wrapped,
  ) {
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: wrapped,
        stackTrace: err.stackTrace,
        message: wrapped.message,
      ),
    );
  }
}

/// Returns the slug from `/v2/project/<slug>` or `/v2/project/<slug>/version`,
/// or null if the path doesn't match that shape.
String? _projectSlugFromPath(String path) {
  final segments = path
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  final i = segments.indexOf('project');
  if (i < 0 || i + 1 >= segments.length) return null;
  final tail = segments.sublist(i + 2);
  if (tail.isEmpty || (tail.length == 1 && tail.first == 'version')) {
    return Uri.decodeComponent(segments[i + 1]);
  }
  return null;
}
