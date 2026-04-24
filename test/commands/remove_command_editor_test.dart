import 'package:test/test.dart';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/remove_command_editor.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';

void main() {
  group('removeEntry', () {
    test('removes a shorthand entry, preserves surrounding comments', () {
      final before = '''
# top comment
slug: pack
mods:
  # comment above jei
  jei: ^19.27.0.340 # the JEI comment
  sodium: release
resource_packs:
  faithful-32x: ^1.21
''';
      final after = removeEntry(before, section: Section.mods, slug: 'sodium');
      expect(after, contains('# top comment'));
      expect(after, contains('# comment above jei'));
      expect(after, contains('# the JEI comment'));
      expect(after, contains('jei: ^19.27.0.340'));
      expect(after, isNot(contains('sodium: release')));
      expect(after, isNot(contains('sodium:')));
    });

    test('removes a long-form (mapping) entry cleanly', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
  iris:
    version: ^1.8.12
    environment: client
''';
      final after = removeEntry(before, section: Section.mods, slug: 'iris');
      expect(after, contains('jei: ^1.0.0'));
      expect(after, isNot(contains('iris')));
      expect(after, isNot(contains('environment: client')));
      expect(after, isNot(contains('version: ^1.8.12')));
    });

    test('removes the only entry in a section (empty section stays)', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
resource_packs:
  faithful-32x: ^1.21
''';
      final after = removeEntry(
        before,
        section: Section.resourcePacks,
        slug: 'faithful-32x',
      );
      expect(after, contains('resource_packs'));
      expect(after, isNot(contains('faithful-32x')));
      expect(after, contains('jei: ^1.0.0'));
    });

    test('preserves blank-line separator between sections', () {
      final before = '''
mods:
  jei: ^1.0.0
  appleskin: ^3.0.9

resource_packs:
  faithful-32x: ^1.21
''';
      final after = removeEntry(
        before,
        section: Section.mods,
        slug: 'appleskin',
      );
      expect(
        after,
        contains('^1.0.0\n\nresource_packs:'),
        reason: 'the blank line between mods and resource_packs must survive',
      );
    });

    test(
      'preserves blank line inside a section when removing a middle entry',
      () {
        final before = '''
mods:
  jei: ^1.0.0

  appleskin: ^3.0.9
  sodium: release
''';
        final after = removeEntry(
          before,
          section: Section.mods,
          slug: 'appleskin',
        );
        expect(after, contains('^1.0.0\n\n  sodium: release'));
        expect(after, isNot(contains('appleskin')));
      },
    );

    test('throws UserError when slug is not present in the section', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
''';
      expect(
        () => removeEntry(before, section: Section.mods, slug: 'sodium'),
        throwsA(isA<UserError>()),
      );
    });

    test('throws UserError when the section is missing entirely', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
''';
      expect(
        () => removeEntry(
          before,
          section: Section.resourcePacks,
          slug: 'faithful-32x',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('throws UserError when mods.yaml root is not a mapping', () {
      expect(
        () => removeEntry('- a\n- b\n', section: Section.mods, slug: 'sodium'),
        throwsA(isA<UserError>()),
      );
    });

    test('throws UserError for invalid YAML', () {
      expect(
        () => removeEntry(
          'mods: [unterminated',
          section: Section.mods,
          slug: 'sodium',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('throws UserError when the section exists as a scalar', () {
      final before = '''
slug: pack
mods: nope
''';
      expect(
        () => removeEntry(before, section: Section.mods, slug: 'nope'),
        throwsA(isA<UserError>()),
      );
    });
  });
}
