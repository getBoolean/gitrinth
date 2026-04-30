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

/// Stable [UserConfig.tokens] key for the CurseForge read API.
final String curseForgeTokenKey = normalizeServerKey(defaultCurseForgeBaseUrl);

// TODO(getBoolean): replace with the project's real CurseForge read-API
// key, base64-encoded. Obtain at console.curseforge.com. The key is
// embedded so that out-of-the-box `gitrinth get` works without the user
// having to provision a personal CF key. Do not log or surface this
// constant in user-facing output.
const String kCurseForgeDefaultApiKeyB64 = '<<REPLACE_BEFORE_MERGE>>';

/// Returns the embedded default CurseForge read-API key.
///
/// While [kCurseForgeDefaultApiKeyB64] holds the placeholder marker the
/// raw marker string is returned so the targeted unit test fails the
/// build. Once the project owner supplies a real base64-encoded key,
/// the decoded string is returned.
String decodeDefaultCfApiKey() {
  final raw = kCurseForgeDefaultApiKeyB64;
  if (raw == '<<REPLACE_BEFORE_MERGE>>') return raw;
  return utf8.decode(base64.decode(raw));
}

/// Default CurseForge upload-API base URL. The upload API is a separate
/// service from the read API and is only consumed by Part 8's publish
/// path; Part 3 declares the constant so the token store and CLI surface
/// have a stable shape to build against.
const String defaultCurseForgeUploadBaseUrl =
    'https://minecraft.curseforge.com';

/// Stable [UserConfig.tokens] key for the CurseForge upload API.
final String curseForgeUploadTokenKey = normalizeServerKey(
  defaultCurseForgeUploadBaseUrl,
);

/// Resolves the per-developer CurseForge upload token.
///
/// Returns null when neither the env var nor the user-config map carries
/// a value — Part 8 surfaces a hard error in that case pointing at
/// `https://authors-old.curseforge.com/account/api-tokens` and at
/// `gitrinth token add minecraft.curseforge.com`.
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
