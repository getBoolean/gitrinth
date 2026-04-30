import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import 'curseforge_api.dart';
import 'curseforge_url.dart';
import 'dio_error_helpers.dart';

/// Attaches `x-api-key: <token>` to outbound CurseForge requests that
/// opt into auth via `extra[kCurseForgeAuthRequired]`. Resolution order:
///   1. `envTokenLookup()` — typically `GITRINTH_CURSEFORGE_TOKEN`.
///   2. The build-time default key from `decodeDefaultCfApiKey()`
///      (or a caller-supplied resolver in tests).
///
/// User config tokens are not used for downloads; `gitrinth token add
/// curseforge.com` stores the separate CurseForge publish key.
///
/// CurseForge requests against non-CF hosts pass through unchanged —
/// the marker's host check uses `api.curseforge.com` exactly, so a
/// stray `dio.get('https://example.com/...')` does not leak the key.
class CurseForgeAuthInterceptor extends Interceptor {
  final String? Function() envTokenLookup;
  final String Function() _defaultKeyResolver;

  CurseForgeAuthInterceptor({
    required this.envTokenLookup,
    String Function()? defaultKeyResolver,
  }) : _defaultKeyResolver = defaultKeyResolver ?? decodeDefaultCfApiKey;

  static const String _cfHost = 'api.curseforge.com';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[kCurseForgeAuthRequired] != true) {
      handler.next(options);
      return;
    }
    if (options.uri.host.toLowerCase() != _cfHost) {
      handler.next(options);
      return;
    }
    final token = _resolveToken();
    if (token != null && token.isNotEmpty) {
      options.headers['x-api-key'] = token;
      handler.next(options);
      return;
    }
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: const AuthenticationError(_missingTokenMessage),
        message: _missingTokenMessage,
      ),
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    if (err.requestOptions.uri.host.toLowerCase() != _cfHost) {
      handler.next(err);
      return;
    }
    handler.reject(
      wrapDioError(err, const AuthenticationError(_unauthorizedMessage)),
    );
  }

  String? _resolveToken() {
    final fromEnv = envTokenLookup();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    final fromDefault = _defaultKeyResolver();
    if (fromDefault.isEmpty) return null;
    return fromDefault;
  }
}

const String _missingTokenMessage =
    'No CurseForge download API key is configured. Set '
    'GITRINTH_CURSEFORGE_TOKEN or build with '
    'GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64.';

const String _unauthorizedMessage =
    'CurseForge rejected the configured download API key. Set '
    'GITRINTH_CURSEFORGE_TOKEN or rebuild with '
    'GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64.';
