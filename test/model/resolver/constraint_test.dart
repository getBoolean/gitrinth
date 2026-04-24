import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/resolver/constraint.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  group('parseConstraint', () {
    test('null/empty -> any', () {
      expect(parseConstraint(null), VersionConstraint.any);
      expect(parseConstraint(''), VersionConstraint.any);
    });

    test('caret on 1.x.y -> compatibleWith same major', () {
      final c = parseConstraint('^6.0.10');
      expect(c.allows(Version.parse('6.0.10')), isTrue);
      expect(c.allows(Version.parse('6.0.11')), isTrue);
      expect(c.allows(Version.parse('6.5.0')), isTrue);
      expect(c.allows(Version.parse('7.0.0')), isFalse);
      expect(c.allows(Version.parse('5.9.0')), isFalse);
    });

    test('caret on 0.x.y -> compatibleWith same minor', () {
      final c = parseConstraint('^0.5.2');
      expect(c.allows(Version.parse('0.5.2')), isTrue);
      expect(c.allows(Version.parse('0.5.9')), isTrue);
      expect(c.allows(Version.parse('0.6.0')), isFalse);
    });

    test('exact match', () {
      final c = parseConstraint('1.2.3');
      expect(c.allows(Version.parse('1.2.3')), isTrue);
      expect(c.allows(Version.parse('1.2.4')), isFalse);
    });

    test('semver pin (no build metadata) matches a +mc-tagged candidate', () {
      // `6.0.10` with no build metadata is a semver-only exact constraint
      // — tag metadata on the candidate is ignored.
      final c = parseConstraint('6.0.10');
      expect(c.allows(Version.parse('6.0.10+mc1.21.1')), isTrue);
      expect(c.allows(Version.parse('6.0.10+340')), isTrue);
      expect(c.allows(Version.parse('6.0.11')), isFalse);
    });

    test(
      'semver pin with tag metadata (+mc...) still matches bare candidate',
      () {
        // `+mc1.21.1` contains non-numeric segments → treated as tag
        // metadata → constraint is semver-only exact.
        final c = parseConstraint('6.0.10+mc1.21.1');
        expect(c.allows(Version.parse('6.0.10')), isTrue);
        expect(c.allows(Version.parse('6.0.10+mc1.21.1')), isTrue);
        expect(c.allows(Version.parse('6.0.10+mc1.21.2')), isTrue);
        expect(c.allows(Version.parse('6.0.11')), isFalse);
      },
    );

    test('build-number pin (+340) rejects candidates with different build', () {
      // All-numeric build segments indicate a real build number → strict
      // exact match (behaviour of pub_semver's Version equality).
      final c = parseConstraint('19.27.0+340');
      expect(c.allows(parseModrinthVersion('19.27.0.340')), isTrue);
      expect(c.allows(Version.parse('19.27.0+341')), isFalse);
      expect(c.allows(Version.parse('19.27.0')), isFalse);
    });

    test('4-segment input is classified as a build-number pin', () {
      final c = parseConstraint('19.27.0.340');
      expect(c.allows(parseModrinthVersion('19.27.0.340')), isTrue);
      expect(c.allows(Version.parse('19.27.0')), isFalse);
    });

    test('unparseable raises ValidationError', () {
      expect(
        () => parseConstraint('not-a-version'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('caret on r-prefixed shader version (Complementary-style)', () {
      final c = parseConstraint('^r5.7.1');
      expect(c.allows(parseModrinthVersion('r5.7.1')), isTrue);
      expect(c.allows(parseModrinthVersion('r5.8.0')), isTrue);
      expect(c.allows(parseModrinthVersion('r6.0.0')), isFalse);
      expect(c.allows(parseModrinthVersion('r5.7.0')), isFalse);
    });

    test('caret on four-segment numeric version', () {
      final c = parseConstraint('^19.27.0.340');
      expect(c.allows(parseModrinthVersion('19.27.0.340')), isTrue);
      expect(c.allows(parseModrinthVersion('19.99.0.0')), isTrue);
      expect(c.allows(parseModrinthVersion('20.0.0.0')), isFalse);
    });
  });

  group('parseModrinthVersion', () {
    test('plain semver', () {
      final v = parseModrinthVersion('1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
    });

    test('semver with build metadata is accepted', () {
      final v = parseModrinthVersion('6.0.10+mc1.21.1');
      expect(v.major, 6);
      expect(v.build.first, 'mc1');
    });

    test('four-segment numeric version is normalised to build metadata', () {
      final v = parseModrinthVersion('19.27.0.340');
      expect(v.major, 19);
      expect(v.minor, 27);
      expect(v.patch, 0);
      expect(v.build, isNotEmpty);
    });

    test('strips leading `r` prefix (shader-pack versioning)', () {
      final v = parseModrinthVersion('r5.7.1');
      expect(v.major, 5);
      expect(v.minor, 7);
      expect(v.patch, 1);
    });

    test('strips leading `v` prefix', () {
      final v = parseModrinthVersion('v1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
    });

    test('strips multi-character alphabetic prefix', () {
      final v = parseModrinthVersion('alpha1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
    });

    test('strips prefix with separator', () {
      final v = parseModrinthVersion('release-1.0.0');
      expect(v.major, 1);
      expect(v.minor, 0);
      expect(v.patch, 0);
    });

    test('throws on truly unparseable strings', () {
      expect(() => parseModrinthVersion('abc'), throwsFormatException);
    });
  });

  group('parseChannelToken', () {
    test('round-trips each channel', () {
      expect(parseChannelToken('release'), Channel.release);
      expect(parseChannelToken('beta'), Channel.beta);
      expect(parseChannelToken('alpha'), Channel.alpha);
    });

    test('is case-insensitive and whitespace-tolerant', () {
      expect(parseChannelToken('  BETA '), Channel.beta);
      expect(parseChannelToken('Alpha'), Channel.alpha);
      expect(parseChannelToken('RELEASE'), Channel.release);
    });

    test(
      'returns null for non-channel tokens (falls through to constraint)',
      () {
        expect(parseChannelToken('^1.0.0'), isNull);
        expect(parseChannelToken('1.2.3'), isNull);
        expect(parseChannelToken(''), isNull);
        expect(parseChannelToken(null), isNull);
      },
    );

    test('rejects unknown channel-shaped tokens', () {
      // Unknown tokens return null; the caller (parser) raises ValidationError
      // when it required a channel.
      expect(parseChannelToken('nightly'), isNull);
      expect(parseChannelToken('stable'), isNull);
    });
  });

  // Covers every mod-version-string shape mentioned in docs/mods-yaml.md, in
  // both exact and caret forms. The doc promises all of these "just work"
  // because `gitrinth` "doesn't constrain the format" — these tests pin that
  // promise so a future parser change can't silently break one of them.
  group('version variants documented in docs/mods-yaml.md', () {
    group('exact form (parseModrinthVersion)', () {
      test('plain three-segment semver', () {
        final v = parseModrinthVersion('6.0.10');
        expect(v, Version(6, 0, 10));
      });

      test('semver with mc-suffixed build metadata', () {
        final v = parseModrinthVersion('6.0.10+mc1.21.1');
        expect(v.major, 6);
        expect(v.minor, 0);
        expect(v.patch, 10);
        expect(v.build, isNotEmpty);
      });

      test('semver with loader-suffixed build metadata (hyphen inside)', () {
        final v = parseModrinthVersion('1.8.12+1.21.1-neoforge');
        expect(v.major, 1);
        expect(v.minor, 8);
        expect(v.patch, 12);
        expect(v.build, isNotEmpty);
      });

      test('semver with loader-prefixed build metadata', () {
        final v = parseModrinthVersion('21.1.1+neoforge-1.21.1');
        expect(v.major, 21);
        expect(v.minor, 1);
        expect(v.patch, 1);
        expect(v.build, isNotEmpty);
      });

      test('four-segment numeric version', () {
        final v = parseModrinthVersion('19.27.0.340');
        expect(v.major, 19);
        expect(v.minor, 27);
        expect(v.patch, 0);
        expect(v.build, isNotEmpty);
      });

      test('r-prefixed shader version', () {
        final v = parseModrinthVersion('r5.7.1');
        expect(v.major, 5);
        expect(v.minor, 7);
        expect(v.patch, 1);
      });

      test('semver with hyphenated pre-release label', () {
        // Used in example/mods.yaml for faithful-32x.
        final v = parseModrinthVersion('1.21.1-december-2025');
        expect(v.major, 1);
        expect(v.minor, 21);
        expect(v.patch, 1);
        expect(v.preRelease, isNotEmpty);
      });

      test('Distant Horizons beta pre-release (3.0.1-b-1.21.1)', () {
        // Beta releases for Distant Horizons use a `-b-<mc>` pre-release
        // label.
        final v = parseModrinthVersion('3.0.1-b-1.21.1');
        expect(v.major, 3);
        expect(v.minor, 0);
        expect(v.patch, 1);
        expect(v.preRelease, isNotEmpty);
        expect(v.build, isEmpty);
      });
    });

    group('caret form (parseConstraint)', () {
      test('caret on plain semver', () {
        final c = parseConstraint('^6.0.10');
        expect(c.allows(parseModrinthVersion('6.0.10')), isTrue);
        expect(c.allows(parseModrinthVersion('6.5.0')), isTrue);
        expect(c.allows(parseModrinthVersion('7.0.0')), isFalse);
      });

      test('caret on semver with mc-suffixed build metadata', () {
        final c = parseConstraint('^6.0.10+mc1.21.1');
        expect(c.allows(parseModrinthVersion('6.0.10+mc1.21.1')), isTrue);
        expect(c.allows(parseModrinthVersion('6.5.0+mc1.21.1')), isTrue);
        expect(c.allows(parseModrinthVersion('7.0.0+mc1.21.1')), isFalse);
      });

      test('caret on semver with loader-suffixed build metadata', () {
        final c = parseConstraint('^1.8.12+1.21.1-neoforge');
        expect(
          c.allows(parseModrinthVersion('1.8.12+1.21.1-neoforge')),
          isTrue,
        );
        expect(c.allows(parseModrinthVersion('1.9.0+1.21.1-neoforge')), isTrue);
        expect(
          c.allows(parseModrinthVersion('2.0.0+1.21.1-neoforge')),
          isFalse,
        );
      });

      test('caret on semver with loader-prefixed build metadata', () {
        final c = parseConstraint('^21.1.1+neoforge-1.21.1');
        expect(
          c.allows(parseModrinthVersion('21.1.1+neoforge-1.21.1')),
          isTrue,
        );
        expect(
          c.allows(parseModrinthVersion('21.5.0+neoforge-1.21.1')),
          isTrue,
        );
        expect(
          c.allows(parseModrinthVersion('22.0.0+neoforge-1.21.1')),
          isFalse,
        );
      });

      test('caret on four-segment numeric version', () {
        final c = parseConstraint('^19.27.0.340');
        expect(c.allows(parseModrinthVersion('19.27.0.340')), isTrue);
        expect(c.allows(parseModrinthVersion('19.99.0.0')), isTrue);
        expect(c.allows(parseModrinthVersion('20.0.0.0')), isFalse);
      });

      test('caret on r-prefixed shader version', () {
        final c = parseConstraint('^r5.7.1');
        expect(c.allows(parseModrinthVersion('r5.7.1')), isTrue);
        expect(c.allows(parseModrinthVersion('r5.8.0')), isTrue);
        expect(c.allows(parseModrinthVersion('r6.0.0')), isFalse);
      });

      test('caret on semver with hyphenated pre-release label', () {
        final c = parseConstraint('^1.21.1-december-2025');
        expect(c.allows(parseModrinthVersion('1.21.1-december-2025')), isTrue);
        expect(c.allows(parseModrinthVersion('2.0.0')), isFalse);
      });

      test('caret on Distant Horizons beta pre-release (^3.0.1-b-1.21.1)', () {
        final c = parseConstraint('^3.0.1-b-1.21.1');
        expect(c.allows(parseModrinthVersion('3.0.1-b-1.21.1')), isTrue);
        expect(c.allows(parseModrinthVersion('3.0.1')), isTrue);
        expect(c.allows(parseModrinthVersion('4.0.0')), isFalse);
      });
    });

    test('blank constraint admits every version', () {
      final c = parseConstraint('');
      expect(c, VersionConstraint.any);
      expect(c.allows(parseModrinthVersion('6.0.10+mc1.21.1')), isTrue);
      expect(c.allows(parseModrinthVersion('r5.7.1')), isTrue);
      expect(c.allows(parseModrinthVersion('19.27.0.340')), isTrue);
    });
  });

  group('allowedVersionTypes', () {
    test('release admits release only', () {
      expect(allowedVersionTypes(Channel.release), {'release'});
    });

    test('beta admits release and beta', () {
      expect(allowedVersionTypes(Channel.beta), {'release', 'beta'});
    });

    test('alpha admits all channels', () {
      expect(allowedVersionTypes(Channel.alpha), {'release', 'beta', 'alpha'});
    });
  });
}
