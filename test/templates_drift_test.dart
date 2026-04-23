import 'dart:io';

import 'package:gitrinth/src/io/templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('inline templates mirror assets/template/', () {
    final cases = <String, String>{
      'mods.yaml': modsYamlTemplate,
      'README.md': readmeTemplate,
      '.gitignore': gitignoreTemplate,
      '.modrinth_ignore': modrinthIgnoreTemplate,
    };

    for (final entry in cases.entries) {
      test('${entry.key} matches assets/template/${entry.key}', () {
        final onDisk = File(p.join('assets', 'template', entry.key))
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
        final inline = entry.value.replaceAll('\r\n', '\n');
        expect(
          inline,
          equals(onDisk),
          reason:
              'Inline template for ${entry.key} has drifted from '
              'assets/template/${entry.key}. Update one so they match.',
        );
      });
    }
  });
}
