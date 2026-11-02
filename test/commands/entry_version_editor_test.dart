import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/add_command_editor.dart';
import 'package:gitrinth/src/commands/migrate_editor.dart';
import 'package:gitrinth/src/commands/pin_editor.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';

void main() {
  final rewrites = <String, String Function(String, Section, String)>{
    'pin': (text, section, version) => updateEntryConstraint(
      text,
      section: section,
      slug: 'entry',
      newConstraint: version,
    ),
    'migrate': (text, section, version) => setEntryVersion(
      text,
      section: section,
      slug: 'entry',
      newVersion: version,
    ),
  };
  for (final operation in rewrites.entries) {
    for (final section in Section.values) {
      test(
        '${operation.key} preserves long-form metadata in ${section.name}',
        () {
          final before =
              '''
# retained header
${sectionKeyFor(section)}:
  entry:
    version: null # retained version comment
    sources: curseforge
    curseforge: remote-entry
    client: unsupported
''';
          expect(
            operation.value(before, section, 'gitrinth:not-found'),
            before.replaceFirst('version: null', 'version: gitrinth:not-found'),
          );
        },
      );
    }
    test('${operation.key} retains its no-version diagnostic', () {
      final expectedAction = operation.key == 'pin'
          ? 'cannot (un)pin.'
          : 'cannot rewrite version.';
      expect(
        () => operation.value(
          'mods:\n  entry: {url: https://example.test/a.jar}\n',
          Section.mods,
          '1.0.0',
        ),
        throwsA(
          isA<UserError>().having(
            (error) => error.message,
            'message',
            "'entry' has no `version:` field — likely a url/path source; $expectedAction",
          ),
        ),
      );
    });
    test('${operation.key} preserves shorthand null comments', () {
      const before = 'mods:\n  entry: null # retained\n  other: release\n';
      expect(
        operation.value(before, Section.mods, '^2.0.0'),
        before.replaceFirst('entry: null', 'entry: ^2.0.0'),
      );
    });
  }
}
