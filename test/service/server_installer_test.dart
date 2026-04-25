import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/server_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ServerInstaller', () {
    late Directory tempRoot;
    late Directory outputDir;
    late File fakeInstaller;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_si_');
      outputDir = Directory(p.join(tempRoot.path, 'server'));
      fakeInstaller = File(p.join(tempRoot.path, 'installer.jar'))
        ..writeAsStringSync('FAKE-JAR');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('Fabric installs by copying the launch JAR into outputDir', () async {
      final calls = <List<String>>[];
      final installer = ServerInstaller(
        runProcess: (exe, args, {workingDirectory, runInShell = false, environment}) async {
          calls.add([exe, ...args]);
          return 0;
        },
      );
      await installer.installServer(
        loader: Loader.fabric,
        mcVersion: '1.21.1',
        loaderVersion: '0.17.3',
        outputDir: outputDir,
        installerOrServerJar: fakeInstaller,
        offline: false,
      );

      final dest = File(p.join(outputDir.path, 'fabric-server-launch.jar'));
      expect(dest.existsSync(), isTrue);
      expect(dest.readAsStringSync(), 'FAKE-JAR');
      expect(calls, isEmpty, reason: 'fabric path must not invoke java');
    });

    test('Forge invokes java with --installServer pointing at outputDir',
        () async {
      final calls = <List<String>>[];
      final installer = ServerInstaller(
        runProcess: (exe, args, {workingDirectory, runInShell = false, environment}) async {
          calls.add([exe, ...args]);
          return 0;
        },
      );
      await installer.installServer(
        loader: Loader.forge,
        mcVersion: '1.21.1',
        loaderVersion: '52.1.5',
        outputDir: outputDir,
        installerOrServerJar: fakeInstaller,
        offline: false,
      );

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.first.toLowerCase(), contains('java'));
      expect(call, contains('-jar'));
      expect(call, contains(fakeInstaller.path));
      expect(call, contains('--installServer'));
      expect(call, contains(outputDir.path));
    });

    test('NeoForge invokes java with --installServer', () async {
      final calls = <List<String>>[];
      final installer = ServerInstaller(
        runProcess: (exe, args, {workingDirectory, runInShell = false, environment}) async {
          calls.add([exe, ...args]);
          return 0;
        },
      );
      await installer.installServer(
        loader: Loader.neoforge,
        mcVersion: '1.21.1',
        loaderVersion: '21.1.50',
        outputDir: outputDir,
        installerOrServerJar: fakeInstaller,
        offline: false,
      );
      expect(calls, hasLength(1));
      expect(calls.single, contains('--installServer'));
    });

    test('writes a sentinel marker so the second call is a no-op', () async {
      var callCount = 0;
      final installer = ServerInstaller(
        runProcess: (exe, args, {workingDirectory, runInShell = false, environment}) async {
          callCount++;
          return 0;
        },
      );
      await installer.installServer(
        loader: Loader.forge,
        mcVersion: '1.21.1',
        loaderVersion: '52.1.5',
        outputDir: outputDir,
        installerOrServerJar: fakeInstaller,
        offline: false,
      );
      expect(callCount, 1);
      await installer.installServer(
        loader: Loader.forge,
        mcVersion: '1.21.1',
        loaderVersion: '52.1.5',
        outputDir: outputDir,
        installerOrServerJar: fakeInstaller,
        offline: false,
      );
      expect(callCount, 1, reason: 'second call should be a no-op');
    });

    test('non-zero installer exit code is surfaced as UserError', () async {
      final installer = ServerInstaller(
        runProcess: (exe, args, {workingDirectory, runInShell = false, environment}) async =>
            1,
      );
      await expectLater(
        installer.installServer(
          loader: Loader.forge,
          mcVersion: '1.21.1',
          loaderVersion: '52.1.5',
          outputDir: outputDir,
          installerOrServerJar: fakeInstaller,
          offline: false,
        ),
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            contains('exit'),
          ),
        ),
      );
      final marker = File(
        p.join(outputDir.path, '.gitrinth-installed-forge-52.1.5'),
      );
      expect(
        marker.existsSync(),
        isFalse,
        reason: 'failed install must not write a sentinel',
      );
    });

    test('offline + no marker refuses to run the installer', () async {
      var called = false;
      final installer = ServerInstaller(
        runProcess: (exe, args, {workingDirectory, runInShell = false, environment}) async {
          called = true;
          return 0;
        },
      );
      await expectLater(
        installer.installServer(
          loader: Loader.forge,
          mcVersion: '1.21.1',
          loaderVersion: '52.1.5',
          outputDir: outputDir,
          installerOrServerJar: fakeInstaller,
          offline: true,
        ),
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            contains('offline'),
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('offline + existing marker is a no-op', () async {
      // Pre-write the marker as if a prior online install succeeded.
      outputDir.createSync(recursive: true);
      File(p.join(outputDir.path, '.gitrinth-installed-forge-52.1.5'))
          .writeAsStringSync('prior');
      var called = false;
      final installer = ServerInstaller(
        runProcess: (exe, args, {workingDirectory, runInShell = false, environment}) async {
          called = true;
          return 0;
        },
      );
      await installer.installServer(
        loader: Loader.forge,
        mcVersion: '1.21.1',
        loaderVersion: '52.1.5',
        outputDir: outputDir,
        installerOrServerJar: fakeInstaller,
        offline: true,
      );
      expect(called, isFalse);
    });
  });
}
