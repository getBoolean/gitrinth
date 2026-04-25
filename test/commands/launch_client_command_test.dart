import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/build_orchestrator.dart';
import 'package:gitrinth/src/commands/launch_command.dart';
import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
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
  String? lastJavaPath;
  bool? lastAllowManagedJava;

  _FakeClientInstaller(this.returnId);

  @override
  Future<String> installClient({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
    required Directory dotMinecraftDir,
    required File installerJar,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
  }) async {
    called = true;
    lastDotMinecraftDir = dotMinecraftDir;
    lastJavaPath = javaPath;
    lastAllowManagedJava = allowManagedJava;
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
    late Directory cacheRoot;
    late GitrinthCache cache;
    late File launcherExe;
    late File installerJar;
    late ManifestIo io;
    late ProviderContainer container;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_launchcli_');
      packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
      clientDir = Directory(p.join(packDir.path, 'build', 'client'))
        ..createSync(recursive: true);
      cacheRoot = Directory(p.join(tempRoot.path, 'cache'))..createSync();
      cache = GitrinthCache(root: cacheRoot.path);
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
      'happy path: installs into cache workdir and symlinks artifact dirs '
      'back to build/client',
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
          Map<String, String>? environment,
          }) async {
            spawnCalls.add([exe, ...args]);
            return 0;
          },
          fetcher: fakeFetcher,
          clientInstaller: fakeInstaller,
          locator: locator,
          cache: cache,
        );

        final expectedWorkDir = p.join(cacheRoot.path, 'launchers', 'pack');

        expect(code, 0);
        expect(fakeFetcher.called, isTrue);
        expect(fakeInstaller.called, isTrue);
        expect(
          fakeInstaller.lastDotMinecraftDir?.path,
          expectedWorkDir,
          reason: 'loader installer must target the cache workdir',
        );

        expect(spawnCalls, hasLength(1));
        final call = spawnCalls.single;
        expect(call.first, launcherExe.path);
        expect(call, contains('--workDir'));
        expect(call.last, Directory(expectedWorkDir).absolute.path);

        for (final relPath in const [
          'mods',
          'config',
          'shaderpacks',
          'global_packs/required_data',
          'global_packs/optional_data',
          'global_packs/required_resources',
          'global_packs/optional_resources',
        ]) {
          final linkPath = p.join(expectedWorkDir, relPath);
          final link = Link(linkPath);
          expect(
            link.existsSync(),
            isTrue,
            reason: 'expected symlink at $linkPath',
          );
          expect(
            p.normalize(p.absolute(link.targetSync())),
            p.normalize(p.absolute(p.join(clientDir.path, relPath))),
          );
        }
      },
    );

    test(
      're-running is idempotent: existing symlinks are kept, no errors',
      () async {
        Future<int> runOnce() => runLaunchClient(
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
          Map<String, String>? environment,
              }) async => 0,
              fetcher: _FakeFetcher(installerJar),
              clientInstaller: _FakeClientInstaller(
                'fabric-loader-0.17.3-1.21.1',
              ),
              locator: _FakeLocator(launcherExecutable: launcherExe),
              cache: cache,
            );

        expect(await runOnce(), 0);
        expect(await runOnce(), 0);

        final modsLink = Link(
          p.join(cacheRoot.path, 'launchers', 'pack', 'mods'),
        );
        expect(modsLink.existsSync(), isTrue);
        expect(
          p.normalize(p.absolute(modsLink.targetSync())),
          p.normalize(p.absolute(p.join(clientDir.path, 'mods'))),
        );
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
          Map<String, String>? environment,
          }) async => 0,
          fetcher: _FakeFetcher(installerJar),
          clientInstaller: _FakeClientInstaller('fabric-loader-0.17.3-1.21.1'),
          locator: _FakeLocator(launcherExecutable: launcherExe),
          cache: cache,
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
          Map<String, String>? environment,
        }) async => 0,
        fetcher: _CountingFetcher(installerJar, () => fetched = true),
        clientInstaller: _FakeClientInstaller('id'),
        locator: _FakeLocator(launcherExecutable: launcherExe),
        cache: cache,
        doBuild: (_) async => 9,
      );
      expect(code, 9);
      expect(fetched, isFalse);
    });

    test(
      'missing build/client when --no-build surfaces a clear UserError '
      'and leaves cache workdir untouched',
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
          Map<String, String>? environment,
            }) async => 0,
            fetcher: _FakeFetcher(installerJar),
            clientInstaller: _FakeClientInstaller('id'),
            locator: _FakeLocator(launcherExecutable: launcherExe),
            cache: cache,
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('client distribution not found'),
            ),
          ),
        );
        expect(
          Directory(p.join(cacheRoot.path, 'launchers', 'pack')).existsSync(),
          isFalse,
          reason:
              'cache workdir should not be created if build/client is missing',
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
