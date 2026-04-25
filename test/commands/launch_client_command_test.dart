import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/build_orchestrator.dart';
import 'package:gitrinth/src/commands/launch_command.dart';
import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/loader_binary_fetcher.dart';
import 'package:gitrinth/src/service/loader_client_installer.dart';
import 'package:gitrinth/src/service/manifest_io.dart';
import 'package:gitrinth/src/service/minecraft_launcher_locator.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

ModsLock _lock({Loader loader = Loader.fabric}) => ModsLock(
      gitrinthVersion: '0.1.0',
      loader: LoaderConfig(mods: loader, modsVersion: '0.17.3'),
      mcVersion: '1.21.1',
    );

class _FakeFetcher implements LoaderBinaryFetcher {
  final File jar;
  bool called = false;
  Loader? loader;
  String? mc;
  String? lv;

  _FakeFetcher(this.jar);

  @override
  Future<File> fetchClientInstaller({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    called = true;
    this.loader = loader;
    mc = mcVersion;
    lv = loaderVersion;
    return jar;
  }

  @override
  Future<File> fetchServerArtifact({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    throw UnimplementedError();
  }
}

class _FakeClientInstaller implements LoaderClientInstaller {
  final String returnId;
  bool called = false;
  Directory? lastDotMinecraftDir;

  _FakeClientInstaller(this.returnId);

  @override
  Future<String> installClient({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
    required Directory dotMinecraftDir,
    required File installerJar,
    required bool offline,
  }) async {
    called = true;
    lastDotMinecraftDir = dotMinecraftDir;
    return returnId;
  }
}

class _FakeLocator implements MinecraftLauncherLocator {
  @override
  final File launcherExecutable;

  _FakeLocator({required this.launcherExecutable});
}

void main() {
  group('runLaunchClient', () {
    late Directory tempRoot;
    late Directory packDir;
    late Directory clientDir;
    late File launcherExe;
    late File installerJar;
    late ManifestIo io;
    late ProviderContainer container;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_launchcli_');
      packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
      clientDir = Directory(p.join(packDir.path, 'build', 'client'))
        ..createSync(recursive: true);
      launcherExe = File(p.join(tempRoot.path, 'launcher.exe'))
        ..writeAsStringSync('STUB');
      installerJar = File(p.join(tempRoot.path, 'installer.jar'))
        ..writeAsStringSync('FAKE');
      io = ManifestIo(directory: packDir);
      container = ProviderContainer();

      File(io.modsYamlPath).writeAsStringSync(
        'slug: pack\n'
        'name: Pack\n'
        'version: 0.1.0\n'
        'description: a pack\n'
        'mc-version: 1.21.1\n'
        'loader:\n'
        '  mods: fabric:0.17.3\n',
      );
      File(io.modsLockPath).writeAsStringSync(emitModsLock(_lock()));
    });

    tearDown(() {
      container.dispose();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test(
      '--offline up front refuses to launch (network needed on first run)',
      () async {
        await expectLater(
          runLaunchClient(
            options: const LaunchClientOptions(
              autoBuild: false,
              offline: true,
              verbose: false,
            ),
            container: container,
            console: const Console(),
            io: io,
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('offline'),
            ),
          ),
        );
      },
    );

    test(
      'happy path: installs into clientDir and spawns launcher with --workDir',
      () async {
        final spawnCalls = <List<String>>[];
        final fakeFetcher = _FakeFetcher(installerJar);
        final fakeInstaller = _FakeClientInstaller(
          'fabric-loader-0.17.3-1.21.1',
        );
        final locator = _FakeLocator(launcherExecutable: launcherExe);

        final code = await runLaunchClient(
          options: const LaunchClientOptions(
            autoBuild: false,
            offline: false,
            verbose: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: (
            exe,
            args, {
            Directory? workingDirectory,
            bool runInShell = false,
          }) async {
            spawnCalls.add([exe, ...args]);
            return 0;
          },
          fetcher: fakeFetcher,
          clientInstaller: fakeInstaller,
          locator: locator,
        );

        expect(code, 0);
        expect(fakeFetcher.called, isTrue);
        expect(fakeInstaller.called, isTrue);
        expect(
          fakeInstaller.lastDotMinecraftDir?.path,
          clientDir.path,
          reason: 'loader installer must target build/client/, not <dotMc>',
        );

        expect(spawnCalls, hasLength(1));
        final call = spawnCalls.single;
        expect(call.first, launcherExe.path);
        expect(call, contains('--workDir'));
        expect(call.last, clientDir.absolute.path);
      },
    );

    test(
      'autoBuild=true delegates to doBuild with env=client before launching',
      () async {
        BuildOptions? captured;
        final code = await runLaunchClient(
          options: const LaunchClientOptions(
            autoBuild: true,
            offline: false,
            verbose: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: (
            exe,
            args, {
            Directory? workingDirectory,
            bool runInShell = false,
          }) async => 0,
          fetcher: _FakeFetcher(installerJar),
          clientInstaller: _FakeClientInstaller('fabric-loader-0.17.3-1.21.1'),
          locator: _FakeLocator(launcherExecutable: launcherExe),
          doBuild: (opts) async {
            captured = opts;
            return 0;
          },
        );
        expect(code, 0);
        expect(captured?.envFlag, 'client');
      },
    );

    test('autoBuild failure short-circuits before fetching the installer',
        () async {
      var fetched = false;
      final code = await runLaunchClient(
        options: const LaunchClientOptions(
          autoBuild: true,
          offline: false,
          verbose: false,
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess: (
          exe,
          args, {
          Directory? workingDirectory,
          bool runInShell = false,
        }) async => 0,
        fetcher: _CountingFetcher(installerJar, () => fetched = true),
        clientInstaller: _FakeClientInstaller('id'),
        locator: _FakeLocator(launcherExecutable: launcherExe),
        doBuild: (_) async => 9,
      );
      expect(code, 9);
      expect(fetched, isFalse);
    });

    test(
      'missing build/client when --no-build surfaces a clear UserError',
      () async {
        clientDir.deleteSync(recursive: true);
        await expectLater(
          runLaunchClient(
            options: const LaunchClientOptions(
              autoBuild: false,
              offline: false,
              verbose: false,
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: (
              exe,
              args, {
              Directory? workingDirectory,
              bool runInShell = false,
            }) async => 0,
            fetcher: _FakeFetcher(installerJar),
            clientInstaller: _FakeClientInstaller('id'),
            locator: _FakeLocator(launcherExecutable: launcherExe),
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('client distribution not found'),
            ),
          ),
        );
      },
    );
  });
}

class _CountingFetcher implements LoaderBinaryFetcher {
  final File jar;
  final void Function() onFetch;
  _CountingFetcher(this.jar, this.onFetch);

  @override
  Future<File> fetchClientInstaller({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    onFetch();
    return jar;
  }

  @override
  Future<File> fetchServerArtifact({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    throw UnimplementedError();
  }
}
