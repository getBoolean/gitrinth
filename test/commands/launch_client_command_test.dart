import 'dart:convert';
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

ModsLock _lock({ModLoader loader = ModLoader.fabric}) => ModsLock(
  gitrinthVersion: '0.1.0',
  loader: LoaderConfig(mods: loader, modsLoaderVersion: '0.17.3'),
  mcVersion: '1.21.1',
);

class _FakeFetcher implements LoaderBinaryFetcher {
  final File jar;
  bool called = false;
  ModLoader? loader;
  String? mc;
  String? lv;

  _FakeFetcher(this.jar);

  @override
  Future<File> fetchClientInstaller({
    required ModLoader loader,
    required String mcVersion,
    required String modsLoaderVersion,
  }) async {
    called = true;
    this.loader = loader;
    mc = mcVersion;
    lv = modsLoaderVersion;
    return jar;
  }

  @override
  Future<File> fetchServerArtifact({
    required ModLoader loader,
    required String mcVersion,
    required String modsLoaderVersion,
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
    required ModLoader loader,
    required String mcVersion,
    required String modsLoaderVersion,
    required Directory dotMinecraftDir,
    required File installerJar,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
    bool verbose = false,
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

    test('--offline refuses to launch up front', () async {
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
    });

    test(
      'installs into the cache workdir and symlinks artifact dirs',
      () async {
        final spawnCalls = <List<String>>[];
        final spawnModes = <ProcessStartMode>[];
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
          runProcess:
              (
                exe,
                args, {
                Directory? workingDirectory,
                bool runInShell = false,
                Map<String, String>? environment,
                ProcessStartMode mode = ProcessStartMode.inheritStdio,
              }) async {
                spawnCalls.add([exe, ...args]);
                spawnModes.add(mode);
                return (pid: 9001, exitCode: null);
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
        expect(
          spawnModes.single,
          ProcessStartMode.detached,
          reason: 'launcher should be detached',
        );

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
          runProcess:
              (
                exe,
                args, {
                Directory? workingDirectory,
                bool runInShell = false,
                Map<String, String>? environment,
                ProcessStartMode mode = ProcessStartMode.inheritStdio,
              }) async => (pid: 1, exitCode: 0),
          fetcher: _FakeFetcher(installerJar),
          clientInstaller: _FakeClientInstaller('fabric-loader-0.17.3-1.21.1'),
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
          runProcess:
              (
                exe,
                args, {
                Directory? workingDirectory,
                bool runInShell = false,
                Map<String, String>? environment,
                ProcessStartMode mode = ProcessStartMode.inheritStdio,
              }) async => (pid: 1, exitCode: 0),
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

    test(
      'autoBuild failure short-circuits before fetching the installer',
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
          runProcess:
              (
                exe,
                args, {
                Directory? workingDirectory,
                bool runInShell = false,
                Map<String, String>? environment,
                ProcessStartMode mode = ProcessStartMode.inheritStdio,
              }) async => (pid: 1, exitCode: 0),
          fetcher: _CountingFetcher(installerJar, () => fetched = true),
          clientInstaller: _FakeClientInstaller('id'),
          locator: _FakeLocator(launcherExecutable: launcherExe),
          cache: cache,
          doBuild: (_) async => 9,
        );
        expect(code, 9);
        expect(fetched, isFalse);
      },
    );

    test('--memory writes managed GC + -Xmx/-Xms into the profile', () async {
      final installer = _ProfileWritingClientInstaller(
        'fabric-loader-0.17.3-1.21.1',
      );
      final code = await runLaunchClient(
        options: const LaunchClientOptions(
          autoBuild: false,
          offline: false,
          verbose: false,
          memoryMax: '4G',
          memoryMin: '4G',
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess:
            (
              exe,
              args, {
              Directory? workingDirectory,
              bool runInShell = false,
              Map<String, String>? environment,
              ProcessStartMode mode = ProcessStartMode.inheritStdio,
            }) async => (pid: 1, exitCode: 0),
        fetcher: _FakeFetcher(installerJar),
        clientInstaller: installer,
        locator: _FakeLocator(launcherExecutable: launcherExe),
        cache: cache,
      );
      expect(code, 0);

      final profilesFile = File(
        p.join(cacheRoot.path, 'launchers', 'pack', 'launcher_profiles.json'),
      );
      final root = jsonDecode(profilesFile.readAsStringSync()) as Map;
      final profile =
          (root['profiles'] as Map).values.first as Map<String, dynamic>;
      expect(profile['javaArgs'], '-XX:+UseZGC -Xmx4G -Xms4G');
      expect(
        profile['name'],
        'gitrinth: pack',
        reason: 'memory + GC injection must not regress the rename',
      );
    });

    test('no --memory still injects managed GC over preexisting G1', () async {
      final installer = _ProfileWritingClientInstaller(
        'fabric-loader-0.17.3-1.21.1',
        presetJavaArgs: '-XX:+UseG1GC',
      );
      await runLaunchClient(
        options: const LaunchClientOptions(
          autoBuild: false,
          offline: false,
          verbose: false,
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess:
            (
              exe,
              args, {
              Directory? workingDirectory,
              bool runInShell = false,
              Map<String, String>? environment,
              ProcessStartMode mode = ProcessStartMode.inheritStdio,
            }) async => (pid: 1, exitCode: 0),
        fetcher: _FakeFetcher(installerJar),
        clientInstaller: installer,
        locator: _FakeLocator(launcherExecutable: launcherExe),
        cache: cache,
      );

      final profilesFile = File(
        p.join(cacheRoot.path, 'launchers', 'pack', 'launcher_profiles.json'),
      );
      final root = jsonDecode(profilesFile.readAsStringSync()) as Map;
      final profile =
          (root['profiles'] as Map).values.first as Map<String, dynamic>;
      expect(
        profile['javaArgs'],
        '-XX:+UseZGC',
        reason: 'GC injection should not depend on --memory',
      );
    });

    test(
      '--memory rewrites GC + heap tokens and keeps unrelated tokens',
      () async {
        final installer = _ProfileWritingClientInstaller(
          'fabric-loader-0.17.3-1.21.1',
          presetJavaArgs:
              '-Xmx512M -XX:+UseG1GC -Xms256M -Dlog4j2.formatMsgNoLookups=true',
        );
        await runLaunchClient(
          options: const LaunchClientOptions(
            autoBuild: false,
            offline: false,
            verbose: false,
            memoryMax: '8G',
            memoryMin: '8G',
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess:
              (
                exe,
                args, {
                Directory? workingDirectory,
                bool runInShell = false,
                Map<String, String>? environment,
                ProcessStartMode mode = ProcessStartMode.inheritStdio,
              }) async => (pid: 1, exitCode: 0),
          fetcher: _FakeFetcher(installerJar),
          clientInstaller: installer,
          locator: _FakeLocator(launcherExecutable: launcherExe),
          cache: cache,
        );

        final profilesFile = File(
          p.join(cacheRoot.path, 'launchers', 'pack', 'launcher_profiles.json'),
        );
        final root = jsonDecode(profilesFile.readAsStringSync()) as Map;
        final profile =
            (root['profiles'] as Map).values.first as Map<String, dynamic>;
        expect(
          profile['javaArgs'],
          '-Dlog4j2.formatMsgNoLookups=true -XX:+UseZGC -Xmx8G -Xms8G',
        );
      },
    );

    test(
      'missing build/client with --no-build throws and leaves cache untouched',
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
            runProcess:
                (
                  exe,
                  args, {
                  Directory? workingDirectory,
                  bool runInShell = false,
                  Map<String, String>? environment,
                  ProcessStartMode mode = ProcessStartMode.inheritStdio,
                }) async => (pid: 1, exitCode: 0),
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
          reason: 'cache workdir should not be created',
        );
      },
    );
  });
}

/// Test installer that pre-writes `launcher_profiles.json`.
class _ProfileWritingClientInstaller implements LoaderClientInstaller {
  final String returnId;
  final String? presetJavaArgs;

  _ProfileWritingClientInstaller(this.returnId, {this.presetJavaArgs});

  @override
  Future<String> installClient({
    required ModLoader loader,
    required String mcVersion,
    required String modsLoaderVersion,
    required Directory dotMinecraftDir,
    required File installerJar,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
    bool verbose = false,
  }) async {
    final profile = <String, dynamic>{
      'lastVersionId': returnId,
      'name': 'NeoForge',
    };
    if (presetJavaArgs != null) profile['javaArgs'] = presetJavaArgs;
    final file = File(p.join(dotMinecraftDir.path, 'launcher_profiles.json'));
    file.writeAsStringSync(
      jsonEncode({
        'profiles': {'auto': profile},
      }),
    );
    return returnId;
  }
}

class _CountingFetcher implements LoaderBinaryFetcher {
  final File jar;
  final void Function() onFetch;
  _CountingFetcher(this.jar, this.onFetch);

  @override
  Future<File> fetchClientInstaller({
    required ModLoader loader,
    required String mcVersion,
    required String modsLoaderVersion,
  }) async {
    onFetch();
    return jar;
  }

  @override
  Future<File> fetchServerArtifact({
    required ModLoader loader,
    required String mcVersion,
    required String modsLoaderVersion,
  }) async {
    throw UnimplementedError();
  }
}
