import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import 'modrinth_url.dart';

/// Attaches `Authorization: <token>` (no `Bearer` prefix — Modrinth's
/// PAT format) to outbound Modrinth requests, and converts 401s into
/// [AuthenticationError]. `GITRINTH_TOKEN` only applies to the default
/// host. Stored keys are matched as a scheme+host+path-prefix.
class ModrinthAuthInterceptor extends Interceptor {
  final Map<String, String> Function() tokensProvider;
  final String? Function() envTokenLookup;
  final String defaultBaseUrl;

  ModrinthAuthInterceptor({
    required this.tokensProvider,
    required this.envTokenLookup,
    required this.defaultBaseUrl,
  });

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (options.headers.containsKey('Authorization')) {
      handler.next(options);
      return;
    }
    final token = _resolveToken(options.uri);
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = token;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    final hostLabel = _hostLabel(err.requestOptions.uri);
    final isDefault =
        _matchesPrefix(_safeNormalize(defaultBaseUrl), err.requestOptions.uri);
    final message = isDefault
        ? 'Modrinth rejected the stored credentials for $hostLabel. '
            'Re-run `gitrinth modrinth login`.'
        : 'Modrinth rejected the stored credentials for $hostLabel. '
            'Re-run `gitrinth modrinth token add $hostLabel`.';
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: AuthenticationError(message),
        stackTrace: err.stackTrace,
        message: message,
      ),
    );
  }

  String? _resolveToken(Uri requestUri) {
    final defaultKey = _safeNormalize(defaultBaseUrl);
    if (_matchesPrefix(defaultKey, requestUri)) {
      final fromEnv = envTokenLookup();
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    }
    final tokens = tokensProvider();
    String? bestKey;
    for (final key in tokens.keys) {
      if (!_matchesPrefix(key, requestUri)) continue;
      if (bestKey == null || key.length > bestKey.length) bestKey = key;
    }
    return bestKey == null ? null : tokens[bestKey];
  }

  bool _matchesPrefix(String storedKey, Uri requestUri) {
    final stored = Uri.tryParse(storedKey);
    if (stored == null) return false;
    if (stored.scheme.toLowerCase() != requestUri.scheme.toLowerCase()) {
      return false;
    }
    if (stored.host.toLowerCase() != requestUri.host.toLowerCase()) {
      return false;
    }
    final storedPort =
        stored.hasPort ? stored.port : _defaultPort(stored.scheme);
    final reqPort = requestUri.hasPort
        ? requestUri.port
        : _defaultPort(requestUri.scheme);
    if (storedPort != reqPort) return false;
    final storedPath = stored.path;
    if (storedPath.isEmpty) return true;
    final reqPath = requestUri.path;
    if (reqPath == storedPath) return true;
    return reqPath.startsWith(
      storedPath.endsWith('/') ? storedPath : '$storedPath/',
    );
  }

  String _hostLabel(Uri uri) {
    final port = uri.hasPort && uri.port != _defaultPort(uri.scheme)
        ? ':${uri.port}'
        : '';
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port';
  }

  static int _defaultPort(String scheme) {
    switch (scheme.toLowerCase()) {
      case 'https':
        return 443;
      case 'http':
        return 80;
      default:
        return 0;
    }
  }

  static String _safeNormalize(String url) {
    try {
      return normalizeServerKey(url);
    } on FormatException {
      return url;
    }
  }
}
