import 'package:gitrinth/src/model/curseforge/cf_file_hash.dart';
import 'package:gitrinth/src/model/curseforge/cf_mod_file.dart';
import 'package:gitrinth/src/model/modrinth/version.dart' as modrinth;
import 'package:gitrinth/src/model/modrinth/version_file.dart';
import 'package:gitrinth/src/service/resolve/hash_scan.dart';
import 'package:test/test.dart';

modrinth.Version _mr({required String number, String? sha1}) =>
    modrinth.Version(
      id: 'mr-$number',
      projectId: 'p',
      versionNumber: number,
      files: [
        VersionFile(
          url: 'https://example.com/mr-$number.jar',
          filename: 'mr-$number.jar',
          hashes: sha1 == null ? const {} : {'sha1': sha1},
          size: 1,
          primary: true,
        ),
      ],
      dependencies: const [],
      loaders: const [],
      gameVersions: const [],
    );

ModFile _cf({required int id, String? sha1}) => ModFile(
  id: id,
  modId: 1,
  displayName: 'cf-$id',
  fileName: 'cf-$id.jar',
  releaseType: 1,
  fileDate: '2025-01-01T00:00:00Z',
  gameVersions: const [],
  hashes: sha1 == null ? const [] : [FileHash(value: sha1, algoCode: 1)],
  dependencies: const [],
  downloadUrl: 'https://example.com/cf-$id.jar',
);

void main() {
  group('scanForMatchingPair', () {
    test('newest pair SHA1 matches → HashMatched', () {
      final out = scanForMatchingPair(
        mrCandidates: [_mr(number: '1.0.0', sha1: 'aabb')],
        cfCandidates: [_cf(id: 1, sha1: 'aabb')],
        hashScanDepth: 0,
        allowHashMismatch: false,
      );
      expect(out, isA<HashMatched>());
      final m = out as HashMatched;
      expect(m.modrinthVersion.versionNumber, '1.0.0');
      expect(m.curseforgeFile.id, 1);
    });

    test('depth=0 mismatch with allow=false → HashExhausted', () {
      final out = scanForMatchingPair(
        mrCandidates: [_mr(number: '1.0.0', sha1: 'aabb')],
        cfCandidates: [_cf(id: 1, sha1: 'ccdd')],
        hashScanDepth: 0,
        allowHashMismatch: false,
      );
      expect(out, isA<HashExhausted>());
      final ex = out as HashExhausted;
      expect(ex.depthExamined, 0);
    });

    test('depth=0 mismatch with allow=true → HashAcceptedMismatch', () {
      final out = scanForMatchingPair(
        mrCandidates: [_mr(number: '1.0.0', sha1: 'aabb')],
        cfCandidates: [_cf(id: 1, sha1: 'ccdd')],
        hashScanDepth: 0,
        allowHashMismatch: true,
      );
      expect(out, isA<HashAcceptedMismatch>());
    });

    test(
      'an older matching pair takes precedence over accepting a mismatch',
      () {
        final out = scanForMatchingPair(
          mrCandidates: [
            _mr(number: '2.0.0', sha1: 'new-mr'),
            _mr(number: '1.0.0', sha1: 'same'),
          ],
          cfCandidates: [
            _cf(id: 2, sha1: 'new-cf'),
            _cf(id: 1, sha1: 'same'),
          ],
          hashScanDepth: 1,
          allowHashMismatch: true,
        );
        expect(out, isA<HashMatched>());
        expect((out as HashMatched).modrinthVersion.versionNumber, '1.0.0');
        expect(out.curseforgeFile.id, 1);
      },
    );

    test('depth=10 finds a match at index 3 → HashMatched', () {
      final mr = [
        for (var i = 0; i < 6; i++) _mr(number: '1.0.$i', sha1: 'mr$i'),
      ];
      final cf = [for (var i = 0; i < 6; i++) _cf(id: 100 + i, sha1: 'cf$i')];
      // Plant the match at the index-3 pair: mr3 SHA matches cf3 SHA.
      mr[3] = _mr(number: '1.0.3', sha1: 'matchHash');
      cf[3] = _cf(id: 103, sha1: 'matchHash');
      final out = scanForMatchingPair(
        mrCandidates: mr,
        cfCandidates: cf,
        hashScanDepth: 10,
        allowHashMismatch: false,
      );
      expect(out, isA<HashMatched>());
      final m = out as HashMatched;
      expect(m.modrinthVersion.versionNumber, '1.0.3');
      expect(m.curseforgeFile.id, 103);
    });

    test('depth=2 and match outside window → HashExhausted', () {
      final mr = [
        _mr(number: '1.0.0', sha1: 'a'),
        _mr(number: '1.0.1', sha1: 'b'),
        _mr(number: '1.0.2', sha1: 'c'),
        _mr(number: '1.0.3', sha1: 'matchHash'),
      ];
      final cf = [
        _cf(id: 100, sha1: 'x'),
        _cf(id: 101, sha1: 'y'),
        _cf(id: 102, sha1: 'z'),
        _cf(id: 103, sha1: 'matchHash'),
      ];
      final out = scanForMatchingPair(
        mrCandidates: mr,
        cfCandidates: cf,
        hashScanDepth: 2, // window = 3
        allowHashMismatch: false,
      );
      expect(out, isA<HashExhausted>());
    });

    test('asymmetric windows: short MR, long CF — no crash', () {
      final out = scanForMatchingPair(
        mrCandidates: [_mr(number: '1.0.0', sha1: 'aa')],
        cfCandidates: [
          _cf(id: 1, sha1: 'ff'),
          _cf(id: 2, sha1: 'ee'),
          _cf(id: 3, sha1: 'aa'),
        ],
        hashScanDepth: 5,
        allowHashMismatch: false,
      );
      expect(out, isA<HashMatched>());
      final m = out as HashMatched;
      expect(m.curseforgeFile.id, 3);
    });

    test('candidates with missing SHA1 are skipped, not crashed', () {
      final out = scanForMatchingPair(
        mrCandidates: [
          _mr(number: '1.0.0'), // no sha1
          _mr(number: '0.9.0', sha1: 'aabb'),
        ],
        cfCandidates: [
          _cf(id: 1), // no sha1
          _cf(id: 2, sha1: 'aabb'),
        ],
        hashScanDepth: 5,
        allowHashMismatch: false,
      );
      expect(out, isA<HashMatched>());
      final m = out as HashMatched;
      expect(m.modrinthVersion.versionNumber, '0.9.0');
      expect(m.curseforgeFile.id, 2);
    });

    test('one side empty → HashSingleSided', () {
      final out = scanForMatchingPair(
        mrCandidates: [_mr(number: '1.0.0', sha1: 'aa')],
        cfCandidates: const [],
        hashScanDepth: 5,
        allowHashMismatch: false,
      );
      expect(out, isA<HashSingleSided>());
    });

    test('case-insensitive SHA1 match (lowercase normalization)', () {
      final out = scanForMatchingPair(
        mrCandidates: [_mr(number: '1.0.0', sha1: 'AABB')],
        cfCandidates: [_cf(id: 1, sha1: 'aabb')],
        hashScanDepth: 0,
        allowHashMismatch: false,
      );
      expect(out, isA<HashMatched>());
    });
  });
}
