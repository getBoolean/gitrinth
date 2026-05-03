const String defaultModrinthBaseUrl = 'https://api.modrinth.com/v2';

String resolveModrinthBaseUrl(Map<String, String> env) {
  final fromEnv = env['GITRINTH_MODRINTH_URL'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv.endsWith('/')
        ? fromEnv.substring(0, fromEnv.length - 1)
        : fromEnv;
  }
  return defaultModrinthBaseUrl;
}

/// Stable key for the per-server token map. Lowercases scheme+host,
/// strips a trailing slash, preserves the path. Throws [FormatException]
/// when [url] is not absolute.
String normalizeServerKey(String url) {
  final uri = Uri.parse(url.trim());
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('Server URL must be absolute: $url');
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final port = uri.hasPort ? ':${uri.port}' : '';
  var path = uri.path;
  if (path.endsWith('/') && path.length > 1) {
    path = path.substring(0, path.length - 1);
  }
  return '$scheme://$host$port$path';
}
