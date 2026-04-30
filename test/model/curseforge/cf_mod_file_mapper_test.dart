import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/model/curseforge/cf_file_hash.dart';
import 'package:gitrinth/src/model/curseforge/cf_file_relation.dart';
import 'package:gitrinth/src/model/curseforge/cf_mod.dart';
import 'package:gitrinth/src/model/curseforge/cf_mod_file.dart';
import 'package:gitrinth/src/model/curseforge/cf_search_response.dart';
import 'package:test/test.dart';

const String _filesFixturePath =
    'test/fixtures/curseforge/mod_files_response.json';
const String _searchFixturePath =
    'test/fixtures/curseforge/mod_search_response.json';
const String _disabledFixturePath =
    'test/fixtures/curseforge/mod_distribution_disabled.json';

Map<String, dynamic> _readJson(String path) {
  final raw = File(path).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('ModFile round-trip', () {
    test('fixture deserializes and re-serializes without loss', () {
      final raw = _readJson(_filesFixturePath);
      final response = ModFileSearchResponseMapper.fromMap(raw);
      expect(response.data, hasLength(5));

      final encoded = response.toMap();
      // Round-trip should preserve the data array shape.
      expect(encoded['data'], isA<List>());
      expect((encoded['data'] as List), hasLength(5));

      // Re-decode and re-encode to verify stability of the mapping.
      final reparsed = ModFileSearchResponseMapper.fromMap(encoded);
      expect(reparsed.data.first.id, response.data.first.id);
      expect(reparsed.data.first.fileName, response.data.first.fileName);
      expect(
        reparsed.data.first.dependencies.length,
        response.data.first.dependencies.length,
      );
    });
  });

  group('ModFile.sha1Hash', () {
    test('returns the lowercased sha1 hash from the hashes array', () {
      final raw = _readJson(_filesFixturePath);
      final response = ModFileSearchResponseMapper.fromMap(raw);
      final firstFile = response.data.first;
      expect(firstFile.sha1Hash, 'abcd1234abcd1234abcd1234abcd1234abcd1234');
    });

    test('returns null when no sha1 entry is present', () {
      const file = ModFile(
        id: 1,
        modId: 1,
        displayName: 'x',
        fileName: 'x',
        releaseType: 1,
        fileDate: '2025-01-01T00:00:00Z',
        gameVersions: [],
        hashes: [FileHash(value: 'aaa', algoCode: 2)],
        dependencies: [],
      );
      expect(file.sha1Hash, isNull);
    });

    test('lowercases mixed-case digests', () {
      const file = ModFile(
        id: 1,
        modId: 1,
        displayName: 'x',
        fileName: 'x',
        releaseType: 1,
        fileDate: '2025-01-01T00:00:00Z',
        gameVersions: [],
        hashes: [FileHash(value: 'ABCDEF', algoCode: 1)],
        dependencies: [],
      );
      expect(file.sha1Hash, 'abcdef');
    });
  });

  group('ModFile.requiredDependencies', () {
    test('filters dependencies to relationType == requiredDependency', () {
      final raw = _readJson(_filesFixturePath);
      final response = ModFileSearchResponseMapper.fromMap(raw);
      final firstFile = response.data.first;
      final required = firstFile.requiredDependencies.toList();
      expect(required, hasLength(1));
      expect(required.single.modId, 306612);
      expect(required.single.relationType, RelationType.requiredDependency);
    });

    test('relationType decodes unknown codes as RelationType.unknown', () {
      const rel = FileRelation(modId: 1, relationTypeCode: 99);
      expect(rel.relationType, RelationType.unknown);
    });
  });

  group('Mod / ModSearchResponse', () {
    test('search-response fixture deserializes one Mod', () {
      final raw = _readJson(_searchFixturePath);
      final response = ModSearchResponseMapper.fromMap(raw);
      expect(response.data, hasLength(1));
      final mod = response.data.single;
      expect(mod.id, 238222);
      expect(mod.slug, 'jei');
      expect(mod.classId, 6);
      expect(mod.allowModDistribution, isTrue);
    });

    test('parses allowModDistribution: false', () {
      final raw = _readJson(_disabledFixturePath);
      final response = ModSearchResponseMapper.fromMap(raw);
      expect(response.data.single.allowModDistribution, isFalse);
      expect(response.data.single.latestFiles.single.downloadUrl, isNull);
    });

    test('defaults allowModDistribution to true when the field is missing', () {
      final mod = ModMapper.fromMap(<String, dynamic>{
        'id': 1,
        'gameId': 432,
        'name': 'No-distribution-flag mod',
        'slug': 'noflag',
        'classId': 6,
      });
      expect(mod.allowModDistribution, isTrue);
    });
  });

  group('HashAlgo decoding', () {
    test('algoCode 1 → sha1', () {
      const hash = FileHash(value: 'abc', algoCode: 1);
      expect(hash.algo, HashAlgo.sha1);
    });

    test('algoCode 2 → md5', () {
      const hash = FileHash(value: 'abc', algoCode: 2);
      expect(hash.algo, HashAlgo.md5);
    });

    test('unknown algoCode → unknown', () {
      const hash = FileHash(value: 'abc', algoCode: 99);
      expect(hash.algo, HashAlgo.unknown);
    });
  });
}
