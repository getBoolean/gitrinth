import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import 'curseforge_api.dart';
import 'curseforge_url.dart';
import 'dio_error_helpers.dart';

/// Attaches `x-api-key: <token>` to outbound CurseForge requests that
/// opt into auth via `extra[kCurseForgeAuthRequired]`. Resolution order:
///   1. `envTokenLookup()` — typically `GITRINTH_CURSEFORGE_TOKEN`.
///   2. `tokensProvider()[tokenKey]` — user-config map, normally
///      `UserConfig.tokens['https://api.curseforge.com']`.
///   3. The embedded default key from `decodeDefaultCfApiKey()` (or a
///      caller-supplied resolver in tests).
///
/// CurseForge requests against non-CF hosts pass through unchanged —
/// the marker's host check uses `api.curseforge.com` exactly, so a
/// stray `dio.get('https://example.com/...')` does not leak the key.
class CurseForgeAuthInterceptor extends Interceptor {
  final Map<String, String> Function() tokensProvider;
  final String? Function() envTokenLookup;
  final String tokenKey;
  final String Function() _defaultKeyResolver;

  CurseForgeAuthInterceptor({
    required this.tokensProvider,
    required this.envTokenLookup,
    required this.tokenKey,
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
    final fromUser = tokensProvider()[tokenKey];
    if (fromUser != null && fromUser.isNotEmpty) return fromUser;
    final fromDefault = _defaultKeyResolver();
    if (fromDefault.isEmpty) return null;
    return fromDefault;
  }
}

const String _missingTokenMessage =
    'No CurseForge API key is available. The build is missing its '
    'embedded default key. Run `gitrinth token add curseforge.com` to '
    'configure your own.';

const String _unauthorizedMessage =
    'CurseForge rejected the configured API key. Run '
    '`gitrinth token add curseforge.com` to update it.';
