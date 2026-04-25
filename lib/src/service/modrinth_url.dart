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
