import 'dart:convert';

import 'modrinth_url.dart';

/// Default CurseForge read-API base URL. The CurseForge API has a single
/// canonical host; per-call overrides exist for testing only.
const String defaultCurseForgeBaseUrl = 'https://api.curseforge.com';

/// Resolves the CurseForge read-API base URL.
///
/// Mirrors [resolveModrinthBaseUrl] — `GITRINTH_CURSEFORGE_URL` overrides
/// the default and any trailing slash is stripped. Empty values fall back
/// to [defaultCurseForgeBaseUrl].
String resolveCurseForgeBaseUrl(Map<String, String> env) {
  final fromEnv = env['GITRINTH_CURSEFORGE_URL'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv.endsWith('/')
        ? fromEnv.substring(0, fromEnv.length - 1)
        : fromEnv;
  }
  return defaultCurseForgeBaseUrl;
}

/// Build-time default CurseForge download-API key, base64-encoded.
///
/// Official builds inject this with
/// `--define=GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64=<base64-key>`.
/// User config tokens are intentionally not consulted for downloads;
/// `gitrinth token add curseforge.com` is reserved for the separate
/// CurseForge publish key.
const String kCurseForgeDefaultApiKeyB64 = String.fromEnvironment(
  'GITRINTH_CURSEFORGE_DEFAULT_API_KEY_B64',
);

/// Returns the build-time default CurseForge download-API key.
String decodeDefaultCfApiKey() {
  final raw = kCurseForgeDefaultApiKeyB64;
  if (raw.isEmpty) return '';
  return utf8.decode(base64.decode(raw));
}

/// Default CurseForge upload-API base URL. The upload API is a separate
/// service from the read API and is only consumed by Part 8's publish
/// path; Part 3 declares the constant so the token store and CLI surface
/// have a stable shape to build against.
const String defaultCurseForgeUploadBaseUrl =
    'https://minecraft.curseforge.com';

/// Stable [UserConfig.tokens] key for the CurseForge publish API.
///
/// The publish API itself lives at [defaultCurseForgeUploadBaseUrl],
/// but users manage that credential as `curseforge.com`.
final String curseForgeUploadTokenKey = normalizeServerKey(
  'https://curseforge.com',
);

/// Resolves the per-developer CurseForge upload token.
///
/// Returns null when neither the env var nor the user-config map carries
/// a value — Part 8 surfaces a hard error in that case pointing at
/// `https://authors-old.curseforge.com/account/api-tokens` and at
/// `gitrinth token add curseforge.com`.
///
/// Personal upload tokens are intentionally *not* embeddable: they tie an
/// upload to a specific CurseForge developer account. There is no
/// `decodeDefaultCfUploadToken` counterpart and there must never be one.
String? resolveCurseForgeUploadToken({
  required Map<String, String> env,
  required Map<String, String> userTokens,
}) {
  final fromEnv = env['GITRINTH_CURSEFORGE_UPLOAD_TOKEN'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final fromUser = userTokens[curseForgeUploadTokenKey];
  if (fromUser != null && fromUser.isNotEmpty) return fromUser;
  return null;
}
