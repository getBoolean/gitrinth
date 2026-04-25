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

    test(
      'caret on bare MMP admits <mmp>-<label> Modrinth release tags',
      () {
        // Modrinth uses `<mmp>-<label>` as a release label (Faithful 32x:
        // `1.21.1-december-2025`). Standard semver puts pre-release
        // versions BELOW their base, which would make `^1.21.1` skip
        // every `1.21.1-*` and pick a higher-MMP candidate even when its
        // publish date is older. The Modrinth-aware caret admits these.
        final c = parseConstraint('^1.21.1');
        expect(c.allows(parseModrinthVersion('1.21.1')), isTrue);
        expect(c.allows(parseModrinthVersion('1.21.1-april-2025')), isTrue);
        expect(c.allows(parseModrinthVersion('1.21.1-december-2025')), isTrue);
        // Higher-MMP labels still admitted (under the caret ceiling).
        expect(c.allows(parseModrinthVersion('1.21.3-june-2025')), isTrue);
        expect(c.allows(parseModrinthVersion('1.22.0')), isTrue);
        // Major bump still excluded.
        expect(c.allows(parseModrinthVersion('2.0.0')), isFalse);
        expect(c.allows(parseModrinthVersion('2.0.0-pre')), isFalse);
        // Earlier major still excluded.
        expect(c.allows(parseModrinthVersion('1.20.4')), isFalse);
      },
    );

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

    test('semver pin (no build metadata) matches tag-only candidates', () {
      // `6.0.10` has empty numeric-build-prefix. It matches candidates
      // whose numeric prefix is also empty — bare `6.0.10` and
      // tag-only variants like `6.0.10+mc1.21.1`. A candidate carrying
      // a real build number (e.g. `+340`) has a distinct numeric
      // prefix and does NOT match.
      final c = parseConstraint('6.0.10');
      expect(c.allows(Version.parse('6.0.10+mc1.21.1')), isTrue);
      expect(c.allows(Version.parse('6.0.10+340')), isFalse);
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

    test(
      'semver pin `3.0.1-b` matches any `3.0.1-b-<mc>` Modrinth variant',
      () {
        // Key user-visible behaviour: pinning to the pre-release label (no
        // MC tail) should match every `-b-<mc>` file Modrinth ships in
        // that beta family. Tag metadata on the candidate is informational.
        final c = parseConstraint('3.0.1-b');
        expect(c.allows(parseModrinthVersion('3.0.1-b-1.21.1')), isTrue);
        expect(c.allows(parseModrinthVersion('3.0.1-b-1.21.2')), isTrue);
        expect(c.allows(parseModrinthVersion('3.0.1-b-1.20.4')), isTrue);
        // But different pre-release labels (or no pre-release) stay out.
        expect(c.allows(parseModrinthVersion('3.0.1')), isFalse);
        expect(c.allows(parseModrinthVersion('3.0.1-a-1.21.1')), isFalse);
      },
    );

    test(
      'exact pin on an arbitrary string works (matches itself)',
      () {
        // Some Modrinth mods publish non-semver version strings. An
        // exact pin has a well-defined meaning against them — match
        // iff the raw string is the same. No ValidationError.
        final c = parseConstraint('completely-arbitrary-name');
        expect(
          c.allows(parseModrinthVersionBestEffort('completely-arbitrary-name')),
          isTrue,
        );
        expect(
          c.allows(parseModrinthVersionBestEffort('different-name')),
          isFalse,
        );
      },
    );

    test('caret on an unparseable base raises ValidationError', () {
      // Carets derive their upper bound by bumping major — that's
      // meaningless for arbitrary-string versions. Reject at parse time.
      expect(
        () => parseConstraint('^not-a-version'),
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

  group('parseModrinthVersionBestEffort', () {
    test('delegates to parseModrinthVersion on success', () {
      final v = parseModrinthVersionBestEffort('6.0.10+mc1.21.1');
      expect(v.major, 6);
      expect(v.build, ['mc1', 21, 1]);
    });

    test(
      'falls back to `0.0.0-<sanitised>` on failure; same raw → same Version',
      () {
        final a = parseModrinthVersionBestEffort('totally-weird@#\$string');
        final b = parseModrinthVersionBestEffort('totally-weird@#\$string');
        expect(a, b);
        expect(a.major, 0);
        expect(a.minor, 0);
        expect(a.patch, 0);
        expect(a.preRelease.isNotEmpty, isTrue);
      },
    );

    test('distinct unparseable raws yield distinct Versions', () {
      final a = parseModrinthVersionBestEffort('weird-one');
      final b = parseModrinthVersionBestEffort('weird-two');
      expect(a == b, isFalse);
    });

    test('throws only when sanitisation leaves nothing (pure-symbol input)',
        () {
      expect(
        () => parseModrinthVersionBestEffort('!!!'),
        throwsFormatException,
      );
      expect(
        () => parseModrinthVersionBestEffort(''),
        throwsFormatException,
      );
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
        // Beta releases for Distant Horizons use a `-b-<mc>` convention.
        // The parser splits out the MC-version tail into build metadata
        // so the pre-release is just `[b]` — not `[b-1, 21, 1]` — which
        // lets semver pins of the form `3.0.1-b` match any `3.0.1-b-<mc>`
        // variant the author ships.
        final v = parseModrinthVersion('3.0.1-b-1.21.1');
        expect(v.major, 3);
        expect(v.minor, 0);
        expect(v.patch, 1);
        expect(v.preRelease, ['b']);
        expect(v.build, ['mc', 1, 21, 1]);
      });

      test('Modrinth `-<label>-<mc>` tail ignored when label-tail is single '
          'numeric (not an MC version)', () {
        // `1.21.1-december-2025` looks superficially similar but `2025` is
        // a single number, not an MC version. Parser must NOT split it.
        final v = parseModrinthVersion('1.21.1-december-2025');
        expect(v.preRelease, ['december-2025']);
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
        expect(c.allows(parseModrinthVersion('19.27.0.340-b-1.21.1')), isTrue);
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
        // The `+mc.1.21.1` tail is tag metadata, so `parseConstraint`
        // strips it from the caret bound: `^3.0.1-b-1.21.1` resolves to
        // `compatibleWith(3.0.1-b)`, matching the whole beta family
        // (with or without MC tag) plus any later stable 3.x release.
        final c = parseConstraint('^3.0.1-b-1.21.1');
        expect(c.allows(parseModrinthVersion('3.0.1-b-1.21.1')), isTrue);
        expect(c.allows(parseModrinthVersion('3.0.1-b')), isTrue);
        expect(c.allows(parseModrinthVersion('3.0.1')), isTrue);
        expect(c.allows(parseModrinthVersion('4.0.0')), isFalse);
      });

      test('caret on truncated pre-release (^3.0.1-b) matches richer betas '
          'like 3.0.1-b-1.21.1', () {
        // Under our parser both `3.0.1-b` and `3.0.1-b-1.21.1` have
        // preRelease `[b]`; the latter just adds build metadata. That
        // makes `^3.0.1-b` a useful shorthand: its lower bound is the
        // bare pre-release and the caret range reaches up to the next
        // major, so every `3.0.1-b-<mc>` variant and every later stable
        // 3.x release falls inside.
        final c = parseConstraint('^3.0.1-b');
        expect(c.allows(parseModrinthVersion('3.0.1-b')), isTrue);
        expect(c.allows(parseModrinthVersion('3.0.1-b-1.21.1')), isTrue);
        expect(c.allows(parseModrinthVersion('3.0.1-b-1.21.2')), isTrue);
        expect(c.allows(parseModrinthVersion('3.5.0')), isTrue);
        expect(c.allows(parseModrinthVersion('4.0.0')), isFalse);
        expect(c.allows(parseModrinthVersion('3.0.0')), isFalse);
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
