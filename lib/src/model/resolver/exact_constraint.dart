import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';

/// Returns the leading run of numeric build segments in [build].
/// Shared by `parseConstraint`, `bareVersionForPin`, and
/// [SemverOnlyExactConstraint].
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
/// Matching uses `(major, minor, patch, preRelease, numericBuildPrefix)`.
/// Non-numeric build metadata is ignored.
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
