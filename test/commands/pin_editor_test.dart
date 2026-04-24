import 'package:test/test.dart';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/pin_editor.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';

void main() {
  group('updateEntryConstraint', () {
    test('rewrites short-form scalar, preserves surrounding comments', () {
      final before = '''
# top comment
slug: pack
mods:
  # comment above jei
  jei: ^19.27.0.340 # inline JEI comment
  sodium: release
''';
      final after = updateEntryConstraint(
        before,
        section: Section.mods,
        slug: 'jei',
        newConstraint: '19.27.0.340',
      );
      expect(after, contains('# top comment'));
      expect(after, contains('# comment above jei'));
      expect(after, contains('# inline JEI comment'));
      expect(after, contains('jei: 19.27.0.340'));
      expect(after, contains('sodium: release'));
    });

    test('rewrites long-form `version:` leaf only', () {
      final before = '''
slug: pack
mods:
  iris:
    version: ^1.8.12
    environment: client
''';
      final after = updateEntryConstraint(
        before,
        section: Section.mods,
        slug: 'iris',
        newConstraint: '1.8.12',
      );
      expect(after, contains('version: 1.8.12'));
      expect(after, contains('environment: client'));
    });

    test('rejects long-form entries without `version:`', () {
      final before = '''
slug: pack
mods:
  custom:
    url: https://example.com/foo.jar
''';
      expect(
        () => updateEntryConstraint(
          before,
          section: Section.mods,
          slug: 'custom',
          newConstraint: '1.2.3',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('errors when slug is missing from the section', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
''';
      expect(
        () => updateEntryConstraint(
          before,
          section: Section.mods,
          slug: 'not-there',
          newConstraint: '1.0.0',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('errors when section is absent', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
''';
      expect(
        () => updateEntryConstraint(
          before,
          section: Section.shaders,
          slug: 'complementary',
          newConstraint: '1.0.0',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('errors when section is a null-scalar', () {
      final before = '''
slug: pack
mods:
shaders:
''';
      expect(
        () => updateEntryConstraint(
          before,
          section: Section.shaders,
          slug: 'complementary',
          newConstraint: '1.0.0',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('errors when root is not a mapping', () {
      expect(
        () => updateEntryConstraint(
          '- a\n- b\n',
          section: Section.mods,
          slug: 'x',
          newConstraint: '1.0.0',
        ),
        throwsA(isA<UserError>()),
      );
    });
  });
}
