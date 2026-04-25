import 'package:pub_semver/pub_semver.dart';

import '../../cli/exceptions.dart';
import '../manifest/mods_yaml.dart';
import '../modrinth/version.dart' as modrinth;
import 'exact_constraint.dart';

/// Parses a `mods.yaml` version constraint into a [VersionConstraint].
///
/// Forms:
///   - null/empty → `VersionConstraint.any` (latest compatible).
///   - `^x.y.z[+meta]` → caret range (pub_semver semantics — same major for
///     `1.x.y`, same minor for `0.x.y`). The version part is normalized via
///     [parseModrinthVersion] so unusual Modrinth forms (four-segment numeric,
///     `r`-prefixed shaders) are accepted.
///   - `x.y.z` → exact match (`==`).
VersionConstraint parseConstraint(String? raw) {
  if (raw == null) return VersionConstraint.any;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return VersionConstraint.any;
  try {
    if (trimmed.startsWith('^')) {
      // Carets require a semver-shaped base — the lower bound and
      // upper bound are derived by bumping the version's major, which
      // has no meaning for arbitrary-string versions. Use the strict
      // parser; failure surfaces as ValidationError below.
      final version = parseModrinthVersion(trimmed.substring(1));
      // Keep the numeric build-number prefix (real version info) on the
      // caret's lower bound; strip trailing tag metadata (e.g.
      // `+mc1.21.1`) so candidates with different or missing tags aren't
      // excluded.
      final numericPrefix = _numericBuildPrefix(version.build);
      // When the user-supplied caret base has no explicit pre-release,
      // widen the lower bound to admit `<mmp>-<label>` candidates of the
      // same MMP. In standard semver `^1.21.1` excludes `1.21.1-rc1`
      // (pre-releases sort below their base), but Modrinth doesn't use
      // pre-release suffixes as RC tags — resource packs (Faithful 32x:
      // `1.21.1-december-2025`) and shaders (`r5.7.1-rc`) treat the
      // suffix as the canonical release label. Stability floor is
      // expressed via the `channel` field, not by the version-string
      // shape, so excluding labelled releases here gives counter-intuitive
      // resolves where `^1.21.1` skips every `1.21.1-*` and lands on
      // `1.21.3-june-2025` simply because its parsed MMP is higher.
      // Using `pre: '0'` admits any non-empty pre-release identifier
      // (numeric "0" is the lowest possible identifier under semver
      // ordering) without changing the upper bound.
      final pre = version.preRelease.isEmpty
          ? '0'
          : version.preRelease.join('.');
      final bound = Version(
        version.major,
        version.minor,
        version.patch,
        pre: pre,
        build: numericPrefix.isEmpty ? null : numericPrefix.join('.'),
      );
      return VersionConstraint.compatibleWith(bound);
    }
    // Exact match: unified under SemverOnlyExactConstraint, which
    // matches on MMP + preRelease + numeric-build-prefix. Tag metadata
    // is always informational regardless of whether the constraint or
    // candidate carries it.
    final parsed = parseModrinthVersionBestEffort(trimmed);
    return SemverOnlyExactConstraint(parsed);
  } on FormatException catch (e) {
    throw ValidationError('Invalid version constraint "$raw": ${e.message}');
  }
}

/// Returns the leading run of purely-numeric segments in [build] —
/// the "build number" prefix. Stops at the first non-numeric segment
/// (tag metadata like `mc`). Empty list when [build] is empty or starts
/// with a tag segment.
///
/// Shared between [parseConstraint], [bareVersionForPin], and
/// `SemverOnlyExactConstraint` so the classifier stays in one place.
List<String> _numericBuildPrefix(List<Object> build) {
  final out = <String>[];
  for (final seg in build) {
    final s = seg.toString();
    if (!RegExp(r'^\d+$').hasMatch(s)) break;
    out.add(s);
  }
  return out;
}

/// Parses a Modrinth `version_number` string into a [Version].
///
/// Modrinth versions often carry build metadata (`6.0.10+mc1.21.1`),
/// four-segment numeric forms (`19.27.0.340`), or a leading non-digit prefix
/// (`r5.7.1` for Complementary Shaders, `v1.2.3`, `release-1.0.0`, etc.).
/// This normalizes those into shapes pub_semver accepts.
Version parseModrinthVersion(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('empty version string');
  }
  // Modrinth convention: `<mmp>-<label>-<mc-version>` (e.g.
  // `3.0.1-b-1.21.1` for Distant Horizons betas). The trailing
  // `-<mc-version>` is MC-compatibility tag metadata, not part of the
  // pre-release label. Split it out before pub_semver parses it so the
  // pre-release stays `[<label>]` and the MC tag lands in build
  // metadata. Only triggers when the suffix looks like an actual MC
  // version (at least two dotted numeric segments) so single-number
  // pre-release tails like `1.21.1-december-2025` are unaffected.
  final modrinthTag = _modrinthTagPattern.firstMatch(trimmed);
  if (modrinthTag != null) {
    final mmp = modrinthTag[1]!;
    final label = modrinthTag[2]!;
    final mc = modrinthTag[3]!;
    return Version.parse('$mmp-$label+mc.$mc');
  }
  // First attempt: pub_semver as-is.
  try {
    return Version.parse(trimmed);
  } on FormatException {
    // fall through to normalization
  }
  // Strip any leading non-digit prefix before the first digit (e.g. `r5.7.1`,
  // `v1.2.3`, `release-1.0.0`). Recurse so four-segment normalization still runs.
  final prefixed = RegExp(r'^[^\d]+(\d.*)$').firstMatch(trimmed);
  if (prefixed != null) {
    try {
      return parseModrinthVersion(prefixed[1]!);
    } on FormatException {
      // fall through
    }
  }
  // Normalize purely numeric four-segment versions (e.g. 19.27.0.340 → 19.27.0+340).
  final fourSegment = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$');
  final m = fourSegment.firstMatch(trimmed);
  if (m != null) {
    return Version.parse('${m[1]}.${m[2]}.${m[3]}+${m[4]}');
  }
  // Four-segment with a Modrinth tag tail (e.g. `19.27.0.340-b-1.21.1`
  // or `19.27.0.340+mc1.21.1`). The 4th segment is already a build
  // number, so fold everything — 4th + tail — into build metadata.
  // No pre-release: 4-segment versions don't use the `-<label>` slot
  // as a semver pre-release, it's Modrinth tag metadata.
  final fourSegmentWithTail = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)\.(\d+)[-+]([A-Za-z0-9][A-Za-z0-9.-]*)$',
  );
  final mt = fourSegmentWithTail.firstMatch(trimmed);
  if (mt != null) {
    // Convert hyphens in the tail to dots so every token is a valid build
    // identifier (semver build metadata is `[A-Za-z0-9-]`, dot-separated).
    final tail = mt[5]!.replaceAll('-', '.');
    return Version.parse(
      '${mt[1]}.${mt[2]}.${mt[3]}+${mt[4]}.$tail',
    );
  }
  throw FormatException('cannot parse version "$raw"');
}

/// Lenient variant of [parseModrinthVersion] — never throws on a
/// non-empty input (except pure-whitespace).
///
/// Tries [parseModrinthVersion] first; on failure, falls back to
/// `0.0.0-<sanitised>` where the sanitised raw (non-alphanumeric runs
/// collapsed to `-`) lands in the pre-release slot. Two parses of the
/// same raw produce the same [Version], and different raws stay
/// distinct under [SemverOnlyExactConstraint] matching (which compares
/// pre-release for equality). Used by report/resolver code paths that
/// need every Modrinth version to yield *some* Version rather than
/// silently skipping.
Version parseModrinthVersionBestEffort(String raw) {
  try {
    return parseModrinthVersion(raw);
  } on FormatException {
    final trimmed = raw.trim();
    final sanitised = trimmed
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (sanitised.isEmpty) rethrow;
    return Version.parse('0.0.0-$sanitised');
  }
}

// `<major>.<minor>.<patch>-<alphanumeric-label>-<mc-version>` where the
// MC version is at least two dotted numeric segments (`1.21`, `1.21.1`).
// The two-segment floor distinguishes Modrinth's `-b-<mc>` tagging from
// plain pre-release labels with a trailing numeric token (e.g.
// `1.21.1-december-2025`, where `2025` is a single number).
final _modrinthTagPattern = RegExp(
  r'^(\d+\.\d+\.\d+)-([A-Za-z][A-Za-z0-9]*)-(\d+\.\d+(?:\.\d+)?)$',
);

/// Returns the "pinnable bare form" of [raw] — `major.minor.patch`, plus the
/// build metadata iff it is purely numeric (which is how [parseModrinthVersion]
/// encodes 4-segment numeric versions like `19.27.0.340` → `19.27.0+340`).
///
/// Used by `pin` / `unpin` / `add --pin`: we strip tag-style metadata
/// (`+mc1.21.1`) because it's loader-compatibility noise, but we keep the
/// build-number segment that actually carries version info. Throws
/// [FormatException] when [raw] doesn't parse.
String bareVersionForPin(String raw) {
  final parsed = parseModrinthVersion(raw);
  var base = '${parsed.major}.${parsed.minor}.${parsed.patch}';
  if (parsed.preRelease.isNotEmpty) {
    base += '-${parsed.preRelease.join('.')}';
  }
  final numericPrefix = _numericBuildPrefix(parsed.build);
  return numericPrefix.isEmpty ? base : '$base+${numericPrefix.join('.')}';
}

/// Comparator: orders Modrinth versions "newest first" under the resolver's
/// selection rule — `date_published` descending, with parsed semver descending
/// as tiebreaker.
///
/// Modrinth doesn't enforce semver on `version_number`. Resource packs and
/// shaders in particular bake max-MC compatibility into the leading
/// `MAJOR.MINOR.PATCH` (Faithful 32x: `1.21.3-june-2025` was published *before*
/// `1.21.1-december-2025` even though parsed semver makes 1.21.3 look "higher").
/// Sorting by publish date matches Modrinth's UI and the user's intuition for
/// "newest within constraint"; falling back to parsed semver keeps existing
/// callers (and tests) that don't carry a publish date deterministic.
///
/// [aParsed] / [bParsed] are the pre-parsed semvers — callers typically already
/// have these from constraint matching, and threading them avoids re-parsing
/// inside the sort.
int compareModrinthSelectionOrder(
  modrinth.Version a,
  Version aParsed,
  modrinth.Version b,
  Version bParsed,
) {
  final aDate = a.datePublished;
  final bDate = b.datePublished;
  if (aDate != null && bDate != null) {
    // ISO 8601 strings sort correctly lexicographically.
    final cmp = bDate.compareTo(aDate);
    if (cmp != 0) return cmp;
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }
  return bParsed.compareTo(aParsed);
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
