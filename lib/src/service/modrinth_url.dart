import 'dart:io';

const String defaultModrinthBaseUrl = 'https://api.modrinth.com/v2';

String resolveModrinthBaseUrl() {
  final fromEnv = Platform.environment['GITRINTH_MODRINTH_URL'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv.endsWith('/') ? fromEnv.substring(0, fromEnv.length - 1) : fromEnv;
  }
  return defaultModrinthBaseUrl;
}
