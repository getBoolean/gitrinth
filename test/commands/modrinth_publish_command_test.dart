import 'dart:io';

import 'package:gitrinth/src/cli/exit_codes.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  late Directory tempRoot;
  late Directory packDir;
  late Directory configDir;
  late FakeModrinth fake;
  late Map<String, String> env;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_publish_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
    configDir = Directory(p.join(tempRoot.path, 'cfg'))..createSync();
    fake = FakeModrinth();
    await fake.start();
    env = {
      'GITRINTH_CONFIG': p.join(configDir.path, 'config.yaml'),
      'GITRINTH_MODRINTH_URL': fake.baseUrl,
    };
  });

  tearDown(() async {
    await fake.stop();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  void writeManifest({String version = '1.0.0', String? publishTo}) {
    final body = StringBuffer()
      ..writeln('slug: testpack')
      ..writeln('name: Test Pack')
      ..writeln('version: $version')
      ..writeln('description: x')
      ..writeln('mc-version: 1.21.1')
      ..writeln('loader:')
      ..writeln('  mods: neoforge')
      ..writeln('mods: {}');
    if (publishTo != null) body.writeln('publish_to: $publishTo');
    File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync(body.toString());
  }

  void writePack({String version = '1.0.0'}) {
    final out = Directory(p.join(packDir.path, 'build'))..createSync();
    File(p.join(out.path, 'testpack-$version.mrpack'))
        .writeAsBytesSync(List<int>.filled(64, 0xab));
  }

  group('gitrinth modrinth publish', () {
    test('--dry-run prints payload without uploading', () async {
      writeManifest();
      writePack();
      final result = await runCli(
        ['-C', packDir.path, 'modrinth', 'publish', '--dry-run'],
        environment: {...env, 'GITRINTH_TOKEN': 'mrp_x'},
      );
      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('Dry run'));
      expect(result.stdout, contains('"version_number": "1.0.0"'));
      expect(result.stdout, contains('"version_type": "release"'));
    });

    test('--dry-run picks beta for pre-release version suffix', () async {
      writeManifest(version: '1.0.0-beta.2');
      writePack(version: '1.0.0-beta.2');
      final result = await runCli(
        ['-C', packDir.path, 'modrinth', 'publish', '--dry-run'],
        environment: {...env, 'GITRINTH_TOKEN': 'mrp_x'},
      );
      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('"version_type": "beta"'));
    });

    test('errors with auth-failure exit when no token is configured',
        () async {
      writeManifest();
      writePack();
      final result = await runCli(
        ['-C', packDir.path, 'modrinth', 'publish', '--dry-run'],
        environment: env,
      );
      expect(result.exitCode, equals(exitAuthenticationFailure));
      expect(result.stderr, contains('No token configured'));
    });

    test('errors when pack artifact is missing', () async {
      writeManifest();
      final result = await runCli(
        ['-C', packDir.path, 'modrinth', 'publish', '--dry-run'],
        environment: {...env, 'GITRINTH_TOKEN': 'mrp_x'},
      );
      expect(result.exitCode, equals(exitUserError));
      expect(result.stderr, contains('Pack artifact not found'));
    });

    test("errors when publish_to is 'none'", () async {
      writeManifest(publishTo: 'none');
      writePack();
      final result = await runCli(
        ['-C', packDir.path, 'modrinth', 'publish', '--dry-run'],
        environment: {...env, 'GITRINTH_TOKEN': 'mrp_x'},
      );
      expect(result.exitCode, equals(exitUserError));
      expect(result.stderr, contains('publishing is disabled'));
    });
  });
}
