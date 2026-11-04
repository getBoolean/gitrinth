import 'package:dio/dio.dart';

import '../../cli/exceptions.dart';
import '../dio_error_helpers.dart';
import 'curseforge_api.dart';
import 'curseforge_url.dart';

/// Attaches `x-api-key: <token>` to outbound CurseForge requests that
/// opt into auth via `extra[kCurseForgeAuthRequired]`. Resolution order:
///   1. `envTokenLookup()` — typically `GITRINTH_CURSEFORGE_TOKEN`.
///   2. The build-time default key from `decodeDefaultCfApiKey()`
///      (or a caller-supplied resolver in tests).
///
/// User config tokens are not used for downloads; `gitrinth token add
/// curseforge.com` stores the separate CurseForge publish key.
///
/// The key is attached only when the request targets the exact origin
/// (scheme, host and port) of the resolved read-API base URL, so a stray
/// `dio.get('https://example.com/...')` does not leak it. Credentialed
/// requests never follow redirects: the HTTP client would replay the
/// key to the redirect target without re-running this origin check, so
/// any 3xx response is rejected instead.
class CurseForgeAuthInterceptor extends Interceptor {
  final String? Function() envTokenLookup;
  final String Function() _defaultKeyResolver;
  final Uri _origin;

  CurseForgeAuthInterceptor({
    required this.envTokenLookup,
    String baseUrl = defaultCurseForgeBaseUrl,
    String Function()? defaultKeyResolver,
  }) : _origin = Uri.parse(baseUrl),
       _defaultKeyResolver = defaultKeyResolver ?? decodeDefaultCfApiKey;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[kCurseForgeAuthRequired] != true) {
      handler.next(options);
      return;
    }
    if (!_sameOrigin(options.uri)) {
      handler.next(options);
      return;
    }
    final token = _resolveToken();
    if (token != null && token.isNotEmpty) {
      options.headers['x-api-key'] = token;
      options.followRedirects = false;
      options.extra[_credentialedKey] = true;
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
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (!_isCredentialedRedirect(response)) {
      handler.next(response);
      return;
    }
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: UserError(_redirectMessage(response)),
        message: _redirectMessage(response),
      ),
      true,
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null &&
        err.error is! GitrinthException &&
        _isCredentialedRedirect(response)) {
      handler.reject(wrapDioError(err, UserError(_redirectMessage(response))));
      return;
    }
    if (response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    if (!_sameOrigin(err.requestOptions.uri)) {
      handler.next(err);
      return;
    }
    handler.reject(
      wrapDioError(err, const AuthenticationError(_unauthorizedMessage)),
    );
  }

  bool _sameOrigin(Uri uri) =>
      uri.scheme.toLowerCase() == _origin.scheme.toLowerCase() &&
      uri.host.toLowerCase() == _origin.host.toLowerCase() &&
      uri.port == _origin.port;

  static bool _isCredentialedRedirect(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    return response.requestOptions.extra[_credentialedKey] == true &&
        status >= 300 &&
        status < 400;
  }

  static String _redirectMessage(Response<dynamic> response) {
    final location = response.headers.value('location');
    return 'CurseForge API request to ${response.requestOptions.uri} was '
        'redirected (HTTP ${response.statusCode}'
        '${location == null ? '' : ' to $location'}). Redirects are not '
        'followed for requests that carry the download API key; check '
        'GITRINTH_CURSEFORGE_URL.';
  }

  String? _resolveToken() {
    final fromEnv = envTokenLookup();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    final fromDefault = _defaultKeyResolver();
    if (fromDefault.isEmpty) return null;
    return fromDefault;
  }
}

const String _credentialedKey = 'gitrinth.curseforgeCredentialed';

const String _missingTokenMessage =
    'No CurseForge download API key is configured. Set '
    'GITRINTH_CURSEFORGE_TOKEN or build with '
    'GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64.';

const String _unauthorizedMessage =
    'CurseForge rejected the configured download API key. Set '
    'GITRINTH_CURSEFORGE_TOKEN or rebuild with '
    'GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64.';
