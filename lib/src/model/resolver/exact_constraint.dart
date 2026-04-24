import 'package:pub_semver/pub_semver.dart';

/// A single-point [VersionConstraint] that treats build metadata as
/// *informational*, not distinguishing.
///
/// Whereas `Version` used as a `VersionConstraint` checks strict `==`
/// (which includes build metadata), this class uses
/// [Version.compareTo] — pub_semver's precedence comparison, which
/// ignores build metadata. The result is that a constraint built from
/// `6.0.10` matches both `6.0.10` and `6.0.10+mc1.21.1`.
///
/// Used by [parseConstraint] when the input has no build metadata or
/// only Modrinth-style tag metadata (non-numeric build segments like
/// `+mc1.21.1`). Constraints whose build metadata is all-numeric
/// (build numbers, e.g. `+340` from 4-segment versions) stay as the
/// pub_semver [Version] class so they preserve strict-match semantics.
class SemverOnlyExactConstraint implements VersionConstraint {
  final Version base;

  const SemverOnlyExactConstraint(this.base);

  @override
  bool allows(Version other) =>
      base.major == other.major &&
      base.minor == other.minor &&
      base.patch == other.patch &&
      _preReleaseEqual(base.preRelease, other.preRelease);

  static bool _preReleaseEqual(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool get isAny => false;

  @override
  bool get isEmpty => false;

  @override
  bool allowsAll(VersionConstraint other) {
    if (other.isEmpty) return true;
    if (other is Version) return allows(other);
    if (other is SemverOnlyExactConstraint) return allows(other.base);
    // A single-point constraint can only contain another single-point
    // constraint — ranges are strictly larger.
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
      // Strict-match constraint over a specific build. If its point
      // shares our base's precedence (metadata ignored), the strict
      // constraint is the narrower result.
      return allows(other) ? other : VersionConstraint.empty;
    }
    if (other is SemverOnlyExactConstraint) {
      return allows(other.base) ? this : VersionConstraint.empty;
    }
    // Ranges and unions: our semver-point is either inside or outside.
    return other.allows(base) ? this : VersionConstraint.empty;
  }

  @override
  VersionConstraint union(VersionConstraint other) {
    if (other.isEmpty) return this;
    if (allowsAll(other)) return this;
    if (other.allowsAll(this)) return other;
    // No clean representation for `{this} ∪ other` without a concrete
    // disjoint union type in pub_semver's surface. The resolver does
    // not call `union` today; throwing surfaces a regression loudly
    // if that ever changes.
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
      other is SemverOnlyExactConstraint && allows(other.base);

  @override
  int get hashCode => Object.hash(
    base.major,
    base.minor,
    base.patch,
    base.preRelease.join('.'),
  );

  @override
  String toString() => base.toString();
}
