import 'package:test/test.dart';

import 'package:gitrinth/src/service/modrinth_project_url.dart';

void main() {
  group('parseModrinthProjectUrl', () {
    test('returns null for a plain slug', () {
      expect(parseModrinthProjectUrl('sodium'), isNull);
      expect(parseModrinthProjectUrl('faithful-32x'), isNull);
      expect(parseModrinthProjectUrl(''), isNull);
    });

    test('parses a standard https URL', () {
      final ref = parseModrinthProjectUrl('https://modrinth.com/mod/sodium');
      expect(ref, isNotNull);
      expect(ref!.slug, 'sodium');
      expect(ref.typeHint, 'mod');
    });

    test('parses http scheme', () {
      final ref = parseModrinthProjectUrl(
        'http://modrinth.com/datapack/terralith',
      );
      expect(ref!.slug, 'terralith');
      expect(ref.typeHint, 'datapack');
    });

    test('parses without scheme', () {
      final ref = parseModrinthProjectUrl(
        'modrinth.com/resourcepack/faithful-32x',
      );
      expect(ref!.slug, 'faithful-32x');
      expect(ref.typeHint, 'resourcepack');
    });

    test('parses www. host', () {
      final ref = parseModrinthProjectUrl(
        'https://www.modrinth.com/shader/complementary-reimagined',
      );
      expect(ref!.slug, 'complementary-reimagined');
      expect(ref.typeHint, 'shader');
    });

    test('tolerates trailing /version/<id>', () {
      final ref = parseModrinthProjectUrl(
        'https://modrinth.com/mod/sodium/version/abc123',
      );
      expect(ref!.slug, 'sodium');
      expect(ref.typeHint, 'mod');
    });

    test('tolerates /gallery, query, fragment', () {
      expect(
        parseModrinthProjectUrl(
          'https://modrinth.com/mod/sodium/gallery',
        )!.slug,
        'sodium',
      );
      expect(
        parseModrinthProjectUrl(
          'https://modrinth.com/mod/sodium?foo=bar',
        )!.slug,
        'sodium',
      );
      expect(
        parseModrinthProjectUrl('https://modrinth.com/mod/sodium#anchor')!.slug,
        'sodium',
      );
    });

    test('returns null for non-modrinth hosts', () {
      expect(parseModrinthProjectUrl('https://example.com/mod/sodium'), isNull);
      expect(
        parseModrinthProjectUrl('https://curseforge.com/mod/sodium'),
        isNull,
      );
    });

    test('returns null when the path has fewer than two segments', () {
      expect(parseModrinthProjectUrl('https://modrinth.com/mod'), isNull);
      expect(parseModrinthProjectUrl('https://modrinth.com/'), isNull);
      expect(parseModrinthProjectUrl('https://modrinth.com'), isNull);
    });

    test('lowercases the type hint but not the slug', () {
      final ref = parseModrinthProjectUrl(
        'https://modrinth.com/MOD/Faithful-32x',
      );
      expect(ref!.typeHint, 'mod');
      expect(ref.slug, 'Faithful-32x');
    });

    test('trims surrounding whitespace', () {
      final ref = parseModrinthProjectUrl(
        '  https://modrinth.com/mod/sodium  ',
      );
      expect(ref!.slug, 'sodium');
    });
  });
}
