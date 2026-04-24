import 'package:gitrinth/src/model/resolver/exact_constraint.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  group('SemverOnlyExactConstraint.allows', () {
    test('matches a candidate with no build metadata', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      expect(c.allows(Version.parse('6.0.10')), isTrue);
    });

    test('matches a candidate with tag-style build metadata (+mc1.21.1)', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      expect(c.allows(Version.parse('6.0.10+mc1.21.1')), isTrue);
    });

    test('matches a candidate with numeric build metadata', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      expect(c.allows(Version.parse('6.0.10+340')), isTrue);
    });

    test('rejects a candidate with different major/minor/patch', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      expect(c.allows(Version.parse('6.0.11')), isFalse);
      expect(c.allows(Version.parse('6.1.0')), isFalse);
      expect(c.allows(Version.parse('7.0.0')), isFalse);
    });

    test('respects pre-release ordering (not equal across pre-release)', () {
      final c = SemverOnlyExactConstraint(Version.parse('1.0.0'));
      expect(c.allows(Version.parse('1.0.0-beta.1')), isFalse);
    });
  });

  group('SemverOnlyExactConstraint flags', () {
    test('isAny and isEmpty are both false', () {
      final c = SemverOnlyExactConstraint(Version.parse('1.0.0'));
      expect(c.isAny, isFalse);
      expect(c.isEmpty, isFalse);
    });

    test('toString is the base version string', () {
      final c = SemverOnlyExactConstraint(Version.parse('1.2.3'));
      expect(c.toString(), '1.2.3');
    });
  });

  group('SemverOnlyExactConstraint.intersect', () {
    test(
      'with Version whose build differs: intersection is the strict Version',
      () {
        final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
        final v = Version.parse('6.0.10+340');
        final result = c.intersect(v);
        expect(result, equals(v));
      },
    );

    test('with a non-matching Version: empty', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      final result = c.intersect(Version.parse('6.0.11'));
      expect(result.isEmpty, isTrue);
    });

    test('with a caret range that contains the base: self', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      final range = VersionConstraint.compatibleWith(Version.parse('6.0.0'));
      expect(c.intersect(range), same(c));
    });

    test('with a caret range that excludes the base: empty', () {
      final c = SemverOnlyExactConstraint(Version.parse('7.0.0'));
      final range = VersionConstraint.compatibleWith(Version.parse('6.0.0'));
      expect(c.intersect(range).isEmpty, isTrue);
    });

    test('with another SemverOnlyExactConstraint at same precedence: self', () {
      final a = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      final b = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      expect(a.intersect(b), same(a));
    });
  });

  group('SemverOnlyExactConstraint.allowsAll / allowsAny', () {
    test('allowsAll: self', () {
      final c = SemverOnlyExactConstraint(Version.parse('1.2.3'));
      expect(c.allowsAll(c), isTrue);
    });

    test('allowsAll: equivalent semver-pin', () {
      final a = SemverOnlyExactConstraint(Version.parse('1.2.3'));
      final b = SemverOnlyExactConstraint(Version.parse('1.2.3'));
      expect(a.allowsAll(b), isTrue);
    });

    test('allowsAll: version-inside-base returns true', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      expect(c.allowsAll(Version.parse('6.0.10+mc1.21.1')), isTrue);
    });

    test('allowsAll: range returns false', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      final range = VersionConstraint.compatibleWith(Version.parse('6.0.0'));
      expect(c.allowsAll(range), isFalse);
    });

    test('allowsAny: with range containing base', () {
      final c = SemverOnlyExactConstraint(Version.parse('6.0.10'));
      final range = VersionConstraint.compatibleWith(Version.parse('6.0.0'));
      expect(c.allowsAny(range), isTrue);
    });
  });

  group('SemverOnlyExactConstraint equality', () {
    test('equal when bases have same precedence', () {
      final a = SemverOnlyExactConstraint(Version.parse('1.2.3'));
      final b = SemverOnlyExactConstraint(Version.parse('1.2.3+mc'));
      expect(a == b, isTrue);
      expect(a.hashCode == b.hashCode, isTrue);
    });

    test('not equal to a plain Version', () {
      final c = SemverOnlyExactConstraint(Version.parse('1.2.3'));
      final Object v = Version.parse('1.2.3');
      expect(c == v, isFalse);
    });
  });
}
