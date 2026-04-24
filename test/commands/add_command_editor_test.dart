import 'package:test/test.dart';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/add_command_editor.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';

void main() {
  group('injectEntry', () {
    test('appends shorthand entry to an existing mods section, preserves comments', () {
      final before = '''
# top comment
slug: pack
mods:
  jei: ^19.27.0.340 # the JEI comment
  sodium: release
resource_packs:
  faithful-32x: ^1.21
''';
      final after = injectEntry(
        before,
        section: Section.mods,
        slug: 'ferrite-core',
        shorthandValue: 'release',
      );
      expect(after, contains('# top comment'));
      expect(after, contains('# the JEI comment'));
      expect(after, contains('ferrite-core: release'));
      expect(after, contains('jei: ^19.27.0.340'));
    });

    test('creates a missing section', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
''';
      final after = injectEntry(
        before,
        section: Section.resourcePacks,
        slug: 'faithful-32x',
        shorthandValue: '^1.21',
      );
      expect(after, contains('resource_packs:'));
      expect(after, contains('faithful-32x: ^1.21'));
    });

    test('creates an entry under a null-scalar section (`plugins:` empty)', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
data_packs:
''';
      final after = injectEntry(
        before,
        section: Section.dataPacks,
        slug: 'terralith',
        shorthandValue: '^2.5.8',
      );
      expect(after, contains('terralith: ^2.5.8'));
    });

    test('emits long-form with version + environment when longForm is set', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
''';
      final after = injectEntry(
        before,
        section: Section.mods,
        slug: 'iris',
        longForm: const {
          'version': '^1.8.12',
          'environment': 'client',
        },
      );
      expect(after, contains('iris:'));
      expect(after, contains('version: ^1.8.12'));
      expect(after, contains('environment: client'));
    });

    test('emits long-form with only `url:` (no version key)', () {
      final before = '''
slug: pack
mods:
  jei: ^1.0.0
''';
      final after = injectEntry(
        before,
        section: Section.mods,
        slug: 'custom',
        longForm: const {'url': 'https://example.com/foo.jar'},
      );
      expect(after, contains('custom:'));
      expect(after, contains('url: https://example.com/foo.jar'));
      expect(after, isNot(contains('version:')));
    });

    test('throws UserError when slug already exists in the section', () {
      final before = '''
slug: pack
mods:
  sodium: release
''';
      expect(
        () => injectEntry(
          before,
          section: Section.mods,
          slug: 'sodium',
          shorthandValue: 'release',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('requires exactly one of shorthandValue / longForm', () {
      const before = 'slug: pack\nmods: {}\n';
      expect(
        () => injectEntry(before, section: Section.mods, slug: 's'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => injectEntry(
          before,
          section: Section.mods,
          slug: 's',
          shorthandValue: 'release',
          longForm: const {'version': 'x'},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws UserError when mods.yaml root is not a mapping', () {
      expect(
        () => injectEntry(
          '- a\n- b\n',
          section: Section.mods,
          slug: 's',
          shorthandValue: 'release',
        ),
        throwsA(isA<UserError>()),
      );
    });

    test('throws UserError when section exists but is a scalar', () {
      final before = '''
slug: pack
mods: nope
''';
      expect(
        () => injectEntry(
          before,
          section: Section.mods,
          slug: 's',
          shorthandValue: 'release',
        ),
        throwsA(isA<UserError>()),
      );
    });
  });
}
