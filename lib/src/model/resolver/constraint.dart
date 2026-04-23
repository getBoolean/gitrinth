import 'package:pub_semver/pub_semver.dart';

import '../../cli/exceptions.dart';

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
