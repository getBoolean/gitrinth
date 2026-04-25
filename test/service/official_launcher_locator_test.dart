import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/official_launcher_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('OfficialLauncherLocator', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_oll_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('GITRINTH_DOT_MINECRAFT overrides the default .minecraft path', () {
      final overrideDir = Directory(p.join(tempRoot.path, 'mc'))
        ..createSync(recursive: true);
      final fakeLauncher = File(p.join(tempRoot.path, 'launcher.exe'))
        ..writeAsStringSync('STUB');

      final locator = OfficialLauncherLocator(
        environment: {
          'GITRINTH_DOT_MINECRAFT': overrideDir.path,
          'GITRINTH_LAUNCHER': fakeLauncher.path,
        },
      );

      expect(locator.dotMinecraftDir.path, overrideDir.path);
      expect(locator.launcherExecutable.path, fakeLauncher.path);
    });

    test('GITRINTH_LAUNCHER pointing at a missing file errors clearly', () {
      final overrideDir = Directory(p.join(tempRoot.path, 'mc'))
        ..createSync(recursive: true);

      final locator = OfficialLauncherLocator(
        environment: {
          'GITRINTH_DOT_MINECRAFT': overrideDir.path,
          'GITRINTH_LAUNCHER': p.join(tempRoot.path, 'does-not-exist.exe'),
        },
      );

      expect(
        () => locator.launcherExecutable,
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            contains('Minecraft Launcher'),
          ),
        ),
      );
    });

    test('missing launcher with no override surfaces an install hint', () {
      final overrideDir = Directory(p.join(tempRoot.path, 'mc'))
        ..createSync(recursive: true);
      // Point every well-known launcher path at a nonexistent location by
      // setting an empty environment. The locator should walk the OS-specific
      // candidates, find none, and throw a UserError with a hint.
      final locator = OfficialLauncherLocator(
        environment: {
          'GITRINTH_DOT_MINECRAFT': overrideDir.path,
          // Clear the OS-specific search paths so we hit the "not found" path
          // even when the test machine actually has the launcher installed.
          'GITRINTH_LAUNCHER_SEARCH_PATHS': '',
        },
      );

      expect(
        () => locator.launcherExecutable,
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            contains('minecraft.net'),
          ),
        ),
      );
    });

    test(
      'GITRINTH_LAUNCHER_SEARCH_PATHS picks the first existing candidate',
      () {
        final overrideDir = Directory(p.join(tempRoot.path, 'mc'))
          ..createSync(recursive: true);
        final c1 = p.join(tempRoot.path, 'absent.exe');
        final c2Path = p.join(tempRoot.path, 'present.exe');
        File(c2Path).writeAsStringSync('STUB');
        final c3 = p.join(tempRoot.path, 'shadowed.exe');
        File(c3).writeAsStringSync('STUB-SHADOWED');

        final locator = OfficialLauncherLocator(
          environment: {
            'GITRINTH_DOT_MINECRAFT': overrideDir.path,
            'GITRINTH_LAUNCHER_SEARCH_PATHS': [c1, c2Path, c3].join(
              Platform.pathSeparator == '\\' ? ';' : ':',
            ),
          },
        );

        expect(locator.launcherExecutable.path, c2Path);
      },
    );
  });
}
