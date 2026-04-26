import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

/// Returns the leading run of purely-numeric segments in [build] —
/// the "build number" prefix. Stops at the first non-numeric segment
/// (tag metadata like `mc`). Empty list when [build] is empty or starts
/// with a tag segment.
///
/// Shared between `parseConstraint`, `bareVersionForPin`, and
/// [SemverOnlyExactConstraint] so the classifier stays in one place.
List<String> numericBuildPrefix(List<Object> build) {
  final out = <String>[];
  for (final seg in build) {
    final s = seg.toString();
    if (!RegExp(r'^\d+$').hasMatch(s)) break;
    out.add(s);
  }
  return out;
}

const _stringListEq = ListEquality<Object>();
const _intListEq = ListEquality<int>();

/// Exact-pin [VersionConstraint] with Modrinth-aware metadata handling.
///
/// Treats a parsed [Version]'s identity as the tuple
/// `(major, minor, patch, preRelease, numericBuildPrefix)`, where
/// `numericBuildPrefix` is the leading run of purely-numeric segments in
/// the build metadata. Tag metadata (non-numeric build segments like
/// `mc`, `neoforge`) is always informational and is ignored when
/// matching.
///
/// Examples:
///   - constraint `6.0.10` → prefix `[]`. Matches `6.0.10`,
///     `6.0.10+mc1.21.1`. Does NOT match `6.0.10+340` (candidate has
///     a distinct build number).
///   - constraint `19.27.0.340` → prefix `[340]`. Matches
///     `19.27.0+340`, `19.27.0+340.b.1.21.1`. Does NOT match
///     `19.27.0+341` (different build number).
///   - constraint `3.0.1-b` → preRelease `[b]`, prefix `[]`. Matches
///     any `3.0.1-b+<anything>` including `3.0.1-b+mc.1.21.1`.
///
/// This is a single-point constraint — [isAny] and [isEmpty] are always
/// false, and union/difference with arbitrary ranges aren't meaningful;
/// `union` throws `UnsupportedError` if invoked against an unrelated
/// range since the resolver doesn't exercise that path today.
class SemverOnlyExactConstraint implements VersionConstraint {
  final Version base;
  final List<int> buildNumber;

  SemverOnlyExactConstraint(this.base)
    : buildNumber = numericBuildPrefix(base.build).map(int.parse).toList();

  @override
  bool allows(Version other) =>
      base.major == other.major &&
      base.minor == other.minor &&
      base.patch == other.patch &&
      _stringListEq.equals(base.preRelease, other.preRelease) &&
      _intListEq.equals(
        buildNumber,
        numericBuildPrefix(other.build).map(int.parse).toList(),
      );

  @override
  bool get isAny => false;

  @override
  bool get isEmpty => false;

  @override
  bool allowsAll(VersionConstraint other) {
    if (other.isEmpty) return true;
    if (other is Version) return allows(other);
    if (other is SemverOnlyExactConstraint) return allows(other.base);
    // A single-point constraint can't contain a range.
    return false;
  }

  @override
  bool allowsAny(VersionConstraint other) {
    if (other.isEmpty) return false;
    if (other is Version) return allows(other);
    if (other is SemverOnlyExactConstraint) return allows(other.base);
    return other.allows(base);
  }

  @override
  VersionConstraint intersect(VersionConstraint other) {
    if (other.isEmpty) return VersionConstraint.empty;
    if (other is Version) {
      return allows(other) ? other : VersionConstraint.empty;
    }
    if (other is SemverOnlyExactConstraint) {
      return allows(other.base) ? this : VersionConstraint.empty;
    }
    return other.allows(base) ? this : VersionConstraint.empty;
  }

  @override
  VersionConstraint union(VersionConstraint other) {
    if (other.isEmpty) return this;
    if (allowsAll(other)) return this;
    if (other.allowsAll(this)) return other;
    throw UnsupportedError(
      'union() is not implemented for SemverOnlyExactConstraint '
      'against $other.',
    );
  }

  @override
  VersionConstraint difference(VersionConstraint other) {
    if (other.isEmpty) return this;
    return other.allows(base) ? VersionConstraint.empty : this;
  }

  @override
  bool operator ==(Object other) =>
      other is SemverOnlyExactConstraint &&
      base == other.base &&
      _intListEq.equals(buildNumber, other.buildNumber);

  @override
  int get hashCode => Object.hash(base, Object.hashAll(buildNumber));

  @override
  String toString() => base.toString();
}
