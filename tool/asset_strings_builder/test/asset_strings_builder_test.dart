import 'dart:convert';

import 'package:asset_strings_builder/builder.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('assetStringsBuilder', () {
    test('produces expected output for a two-asset configuration', () async {
      final builder = assetStringsBuilder(
        BuilderOptions(const {
          'assets': {
            'helloTemplate': 'assets/hello.txt',
            'worldTemplate': 'assets/world.txt',
          },
        }),
      );

      final helloB64 = base64.encode(utf8.encode('Hello, world!\n'));
      final worldB64 = base64.encode(utf8.encode('second\n'));

      await testBuilder(
        builder,
        const {
          'consumer|assets/hello.txt': 'Hello, world!\n',
          'consumer|assets/world.txt': 'second\n',
        },
        outputs: {
          'consumer|lib/src/asset_strings.g.dart': decodedMatches(
            allOf(
              contains('// GENERATED CODE - DO NOT MODIFY BY HAND'),
              contains("import 'dart:convert';"),
              contains(
                "final String helloTemplate = "
                "utf8.decode(base64.decode('$helloB64'));",
              ),
              contains(
                "final String worldTemplate = "
                "utf8.decode(base64.decode('$worldB64'));",
              ),
              // Sorted: helloTemplate must precede worldTemplate.
              matches(
                RegExp(r'helloTemplate[\s\S]*worldTemplate', multiLine: true),
              ),
            ),
          ),
        },
      );
    });

    test('round-trips tricky bytes (binary-safe via base64)', () async {
      // A mix of: tricky text, raw non-UTF-8 bytes, and a 4-byte unicode glyph.
      final bytes = <int>[
        ...utf8.encode("triple ''' \\back \$var and unicode ☃\n"),
        0x00, 0xff, 0xfe, 0xfd, // raw non-text bytes
        ...utf8.encode('🎉'), // 4-byte UTF-8
      ];
      final expectedB64 = base64.encode(bytes);

      final builder = assetStringsBuilder(
        BuilderOptions(const {
          'assets': {'trickyTemplate': 'assets/tricky.bin'},
        }),
      );

      await testBuilder(
        builder,
        {'consumer|assets/tricky.bin': bytes},
        outputs: {
          'consumer|lib/src/asset_strings.g.dart': decodedMatches(
            contains(
              "final String trickyTemplate = "
              "utf8.decode(base64.decode('$expectedB64'));",
            ),
          ),
        },
      );
    });

    test('missing asset surfaces a clear error', () async {
      final builder = assetStringsBuilder(
        BuilderOptions(const {
          'assets': {'missingTemplate': 'assets/does_not_exist.txt'},
        }),
      );

      final logs = <LogRecord>[];
      await testBuilder(
        builder,
        const {'consumer|lib/anchor.dart': ''},
        outputs: const {},
        onLog: logs.add,
      );
      expect(
        logs.where(
          (r) =>
              r.level >= Level.SEVERE &&
              (r.error is AssetNotFoundException ||
                  r.message.contains('does_not_exist.txt')),
        ),
        isNotEmpty,
        reason: 'expected a SEVERE log mentioning the missing asset',
      );
    });

    test('empty assets map produces no output and logs a warning', () async {
      final builder = assetStringsBuilder(BuilderOptions.empty);

      final logs = <LogRecord>[];
      await testBuilder(
        builder,
        const {'consumer|lib/anchor.dart': ''},
        outputs: const {},
        onLog: logs.add,
      );
      expect(
        logs.where(
          (r) =>
              r.level == Level.WARNING && r.message.contains('no assets'),
        ),
        isNotEmpty,
      );
    });
  });
}
