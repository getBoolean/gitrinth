import 'dart:convert';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import 'dio_error_helpers.dart';

/// Maps raw CurseForge HTTP failures into typed [GitrinthException]s.
/// Mirrors `ModrinthErrorInterceptor`: 401/403 surface as
/// [AuthenticationError], 404 surfaces a slug/id-aware
/// [UserError], and other non-2xx codes wrap as a generic [UserError]
/// with the request URI for context.
class CurseForgeErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is GitrinthException) {
      handler.next(err);
      return;
    }

    final response = err.response;
    final reqUri = err.requestOptions.uri;
    final status = response?.statusCode;

    if (status == 401 || status == 403) {
      _rejectWith(
        err,
        handler,
        const AuthenticationError(
          'CurseForge rejected the download API key. Set '
          'GITRINTH_CURSEFORGE_TOKEN or rebuild with '
          'GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64.',
        ),
      );
      return;
    }

    if (status == 404) {
      final modIdent = _modIdentFromPath(reqUri.path);
      if (modIdent != null) {
        _rejectWith(
          err,
          handler,
          UserError(
            "CurseForge mod '$modIdent' not found. Verify the project on "
            'curseforge.com.',
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
      UserError('CurseForge request failed for $reqUri: $summary'),
    );
  }

  void _rejectWith(
    DioException err,
    ErrorInterceptorHandler handler,
    GitrinthException wrapped,
  ) {
    handler.reject(wrapDioError(err, wrapped));
  }
}

/// Extracts the mod identifier (numeric ID or slug-on-search) from
/// `/v1/mods/<id>(/...)` so 404s can name the missing project.
String? _modIdentFromPath(String path) {
  final segments = path
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  for (var i = 0; i + 1 < segments.length; i++) {
    if (segments[i] == 'mods' && segments[i + 1] != 'search') {
      return Uri.decodeComponent(segments[i + 1]);
    }
  }
  return null;
}
