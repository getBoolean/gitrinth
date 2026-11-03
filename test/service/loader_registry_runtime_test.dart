import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/loader_client_installer.dart';
import 'package:gitrinth/src/service/server_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('Quilt client recipe uses its documented profile ID and CLI', () async {
    final root = Directory.systemTemp.createTempSync('quilt_client_recipe_');
    addTearDown(() => root.deleteSync(recursive: true));
    final output = Directory(p.join(root.path, 'client with spaces'));
    final installer = File(p.join(root.path, 'installer.jar'))
      ..writeAsStringSync('fixture');
    final calls = <List<String>>[];
    final service = LoaderClientInstaller(
      runProcess:
          (
            exe,
            args, {
            workingDirectory,
            runInShell = false,
            environment,
          }) async {
            calls.add(args);
            return 0;
          },
    );
    final id = await service.installClient(
      loader: LoaderId.quilt,
      mcVersion: '1.21.1',
      modLoaderVersion: '0.30.2',
      dotMinecraftDir: output,
      installerJar: installer,
      offline: false,
    );
    expect(id, 'quilt-loader-0.30.2-1.21.1');
    expect(calls.single, [
      '-jar',
      installer.path,
      'install',
      'client',
      '1.21.1',
      '0.30.2',
      '--install-dir="${output.path}"',
    ]);
  });
  for (final version in [
    '../escape',
    '--install-dir',
    'http://evil.test',
    '..',
    '1.0;echo',
  ]) {
    test(
      'runtime version $version fails before filesystem or process work',
      () async {
        final root = Directory.systemTemp.createTempSync('unsafe_recipe_');
        addTearDown(() => root.deleteSync(recursive: true));
        final output = Directory(p.join(root.path, 'untouched'));
        var calls = 0;
        final service = ServerInstaller(
          runProcess:
              (
                exe,
                args, {
                workingDirectory,
                runInShell = false,
                environment,
              }) async {
                calls++;
                return 0;
              },
        );
        await expectLater(
          service.installServer(
            loader: LoaderId.quilt,
            mcVersion: '1.21.1',
            modLoaderVersion: version,
            outputDir: output,
            installerOrServerJar: File('unused'),
            offline: false,
          ),
          throwsA(isA<ValidationError>()),
        );
        expect(calls, 0);
        expect(output.existsSync(), isFalse);
      },
    );
  }
  test(
    'metadata-only loader refuses installation before creating directories',
    () async {
      final root = Directory.systemTemp.createTempSync('loader_capability_');
      addTearDown(() => root.deleteSync(recursive: true));
      final output = Directory(p.join(root.path, 'untouched'));
      final installer = File(p.join(root.path, 'installer.jar'))
        ..writeAsStringSync('fixture');
      await expectLater(
        ServerInstaller().installServer(
          loader: LoaderId('future-loader'),
          mcVersion: '1.21.1',
          modLoaderVersion: '1.0.0',
          outputDir: output,
          installerOrServerJar: installer,
          offline: false,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(output.existsSync(), isFalse);
    },
  );

  test(
    'Quilt server recipe uses official CLI arguments and validates launcher output',
    () async {
      final root = Directory.systemTemp.createTempSync('quilt_recipe_');
      addTearDown(() => root.deleteSync(recursive: true));
      final output = Directory(p.join(root.path, 'server with spaces'));
      final installer = File(p.join(root.path, 'installer.jar'))
        ..writeAsStringSync('fixture');
      final calls = <List<String>>[];
      final service = ServerInstaller(
        runProcess:
            (
              exe,
              args, {
              workingDirectory,
              runInShell = false,
              environment,
            }) async {
              calls.add(args);
              File(
                p.join(output.path, 'quilt-server-launch.jar'),
              ).writeAsStringSync('launcher');
              File(
                p.join(output.path, 'server.jar'),
              ).writeAsStringSync('server');
              return 0;
            },
      );
      await service.installServer(
        loader: LoaderId.quilt,
        mcVersion: '1.21.1',
        modLoaderVersion: '0.30.2',
        outputDir: output,
        installerOrServerJar: installer,
        offline: false,
      );
      expect(calls.single, [
        '-jar',
        installer.path,
        'install',
        'server',
        '1.21.1',
        '0.30.2',
        '--install-dir="${output.path}"',
        '--download-server',
      ]);
    },
  );
}
