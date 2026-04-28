import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/loader_client_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LoaderClientInstaller', () {
    late Directory tempRoot;
    late Directory dotMc;
    late File installer;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_lci_');
      dotMc = Directory(p.join(tempRoot.path, '.minecraft'))..createSync();
      installer = File(p.join(tempRoot.path, 'installer.jar'))
        ..writeAsStringSync('FAKE');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test(
      'Fabric runs the installer in client mode and returns its profile id',
      () async {
        final calls = <List<String>>[];
        final ci = LoaderClientInstaller(
          runProcess:
              (
                exe,
                args, {
                workingDirectory,
                runInShell = false,
                environment,
              }) async {
                calls.add([exe, ...args]);
                return 0;
              },
        );

        final id = await ci.installClient(
          loader: ModLoader.fabric,
          mcVersion: '1.21.1',
          modLoaderVersion: '0.17.3',
          dotMinecraftDir: dotMc,
          installerJar: installer,
          offline: false,
        );

        expect(id, 'fabric-loader-0.17.3-1.21.1');
        expect(calls, hasLength(1));
        final call = calls.single;
        expect(call.first.toLowerCase(), contains('java'));
        expect(call, contains('-jar'));
        expect(call, contains(installer.path));
        expect(call, contains('client'));
        expect(call, contains('-dir'));
        expect(call, contains(dotMc.path));
        expect(call, contains('-mcversion'));
        expect(call, contains('1.21.1'));
        expect(call, contains('-loader'));
        expect(call, contains('0.17.3'));
        expect(
          call,
          isNot(contains('-noprofile')),
          reason:
              'Fabric installer must auto-inject a profile into '
              'launcher_profiles.json so we can rename it to '
              '"gitrinth: <slug>" later.',
        );
      },
    );

    test('Forge runs --installClient and returns its profile id', () async {
      final calls = <List<String>>[];
      final ci = LoaderClientInstaller(
        runProcess:
            (
              exe,
              args, {
              workingDirectory,
              runInShell = false,
              environment,
            }) async {
              calls.add([exe, ...args]);
              return 0;
            },
      );

      final id = await ci.installClient(
        loader: ModLoader.forge,
        mcVersion: '1.21.1',
        modLoaderVersion: '52.1.5',
        dotMinecraftDir: dotMc,
        installerJar: installer,
        offline: false,
      );

      expect(id, '1.21.1-forge-52.1.5');
      expect(calls.single, contains('--installClient'));
      expect(calls.single, contains(dotMc.path));
    });

    test(
      'NeoForge runs --installClient and returns the neoforge-<v> profile id',
      () async {
        final ci = LoaderClientInstaller(
          runProcess:
              (
                exe,
                args, {
                workingDirectory,
                runInShell = false,
                environment,
              }) async => 0,
        );
        final id = await ci.installClient(
          loader: ModLoader.neoforge,
          mcVersion: '1.21.1',
          modLoaderVersion: '21.1.50',
          dotMinecraftDir: dotMc,
          installerJar: installer,
          offline: false,
        );
        expect(id, 'neoforge-21.1.50');
      },
    );

    test('skip when versions/<id>/<id>.json already exists', () async {
      // Pre-populate as if a prior install seeded the version JSON.
      final versionDir = Directory(
        p.join(dotMc.path, 'versions', 'fabric-loader-0.17.3-1.21.1'),
      )..createSync(recursive: true);
      File(
        p.join(versionDir.path, 'fabric-loader-0.17.3-1.21.1.json'),
      ).writeAsStringSync('{}');

      var called = false;
      final ci = LoaderClientInstaller(
        runProcess:
            (
              exe,
              args, {
              workingDirectory,
              runInShell = false,
              environment,
            }) async {
              called = true;
              return 0;
            },
      );

      final id = await ci.installClient(
        loader: ModLoader.fabric,
        mcVersion: '1.21.1',
        modLoaderVersion: '0.17.3',
        dotMinecraftDir: dotMc,
        installerJar: installer,
        offline: false,
      );
      expect(id, 'fabric-loader-0.17.3-1.21.1');
      expect(called, isFalse);
    });

    test('non-zero installer exit becomes UserError', () async {
      final ci = LoaderClientInstaller(
        runProcess:
            (
              exe,
              args, {
              workingDirectory,
              runInShell = false,
              environment,
            }) async => 2,
      );
      await expectLater(
        ci.installClient(
          loader: ModLoader.fabric,
          mcVersion: '1.21.1',
          modLoaderVersion: '0.17.3',
          dotMinecraftDir: dotMc,
          installerJar: installer,
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
    });

    test(
      'offline + missing version JSON refuses to run the installer',
      () async {
        var called = false;
        final ci = LoaderClientInstaller(
          runProcess:
              (
                exe,
                args, {
                workingDirectory,
                runInShell = false,
                environment,
              }) async {
                called = true;
                return 0;
              },
        );
        await expectLater(
          ci.installClient(
            loader: ModLoader.fabric,
            mcVersion: '1.21.1',
            modLoaderVersion: '0.17.3',
            dotMinecraftDir: dotMc,
            installerJar: installer,
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
      },
    );
  });
}
