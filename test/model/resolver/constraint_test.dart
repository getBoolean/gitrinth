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

    test('unparseable raises ValidationError', () {
      expect(
        () => parseConstraint('not-a-version'),
        throwsA(isA<ValidationError>()),
      );
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

    test('returns null for non-channel tokens (falls through to constraint)', () {
      expect(parseChannelToken('^1.0.0'), isNull);
      expect(parseChannelToken('1.2.3'), isNull);
      expect(parseChannelToken(''), isNull);
      expect(parseChannelToken(null), isNull);
    });

    test('rejects unknown channel-shaped tokens', () {
      // Unknown tokens return null; the caller (parser) raises ValidationError
      // when it required a channel.
      expect(parseChannelToken('nightly'), isNull);
      expect(parseChannelToken('stable'), isNull);
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
