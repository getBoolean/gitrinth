import 'package:pub_semver/pub_semver.dart';

import '../../cli/exceptions.dart';
import '../manifest/mods_yaml.dart';

/// Parses a `mods.yaml` version constraint into a [VersionConstraint].
///
/// Forms:
///   - null/empty → `VersionConstraint.any` (latest compatible).
///   - `^x.y.z[+meta]` → caret range (pub_semver semantics — same major for
///     `1.x.y`, same minor for `0.x.y`).
///   - `x.y.z` → exact match (`==`).
VersionConstraint parseConstraint(String? raw) {
  if (raw == null) return VersionConstraint.any;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return VersionConstraint.any;
  try {
    if (trimmed.startsWith('^')) {
      return VersionConstraint.parse(trimmed);
    }
    // Exact match — Version implements VersionConstraint, allowing only ==.
    return parseModrinthVersion(trimmed);
  } on FormatException catch (e) {
    throw ValidationError('Invalid version constraint "$raw": ${e.message}');
  }
}

/// Parses a Modrinth `version_number` string into a [Version].
///
/// Modrinth versions often carry build metadata (`6.0.10+mc1.21.1`) or
/// four-segment numeric forms (`19.27.0.340`). This normalizes the latter
/// to `19.27.0+340` so pub_semver accepts them.
Version parseModrinthVersion(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('empty version string');
  }
  // First attempt: pub_semver as-is.
  try {
    return Version.parse(trimmed);
  } on FormatException {
    // fall through to normalization
  }
  // Normalize purely numeric four-segment versions (e.g. 19.27.0.340 → 19.27.0+340).
  final fourSegment = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$');
  final m = fourSegment.firstMatch(trimmed);
  if (m != null) {
    return Version.parse('${m[1]}.${m[2]}.${m[3]}+${m[4]}');
  }
  throw FormatException('cannot parse version "$raw"');
}

/// Parses a release-channel token (`release`, `beta`, `alpha`) into a [Channel].
///
/// Case-insensitive, whitespace-trimmed, whole-string match. Returns `null`
/// for anything that isn't a channel token — callers that accept a union of
/// constraint-or-channel (short-form entries) use the null to fall through
/// to constraint parsing; callers that require a channel (`channel:` field)
/// should raise their own scoped error on null.
Channel? parseChannelToken(String? raw) {
  if (raw == null) return null;
  switch (raw.trim().toLowerCase()) {
    case 'release':
      return Channel.release;
    case 'beta':
      return Channel.beta;
    case 'alpha':
      return Channel.alpha;
    default:
      return null;
  }
}

/// Modrinth `version_type` values admitted by [channel], as a stability floor:
/// `beta` includes `release`; `alpha` includes `release` and `beta`.
Set<String> allowedVersionTypes(Channel channel) {
  switch (channel) {
    case Channel.release:
      return const {'release'};
    case Channel.beta:
      return const {'release', 'beta'};
    case Channel.alpha:
      return const {'release', 'beta', 'alpha'};
  }
}
