import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/build_orchestrator.dart';
import 'package:gitrinth/src/commands/launch_command.dart';
import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/java_runtime_resolver.dart';
import 'package:gitrinth/src/service/manifest_io.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

ModsLock _lock({Loader loader = Loader.fabric, String mcVersion = '1.21.1'}) {
  return ModsLock(
    gitrinthVersion: '0.1.0',
    loader: LoaderConfig(mods: loader, modsVersion: '0.17.3'),
    mcVersion: mcVersion,
  );
}

/// Stub resolver that returns a fixed `java` path without probing the host.
/// All launch-server tests use this so they don't depend on the real JDK
/// installed on the CI machine.
class _FakeResolver implements JavaRuntimeResolver {
  final String javaPath;
  String? lastMcVersion;
  String? lastExplicitPath;
  bool? lastAllowManaged;
  bool? lastOffline;

  _FakeResolver({required this.javaPath});

  @override
  Future<File> resolve({
    required String mcVersion,
    String? explicitPath,
    bool allowManaged = true,
    bool offline = false,
  }) async {
    lastMcVersion = mcVersion;
    lastExplicitPath = explicitPath;
    lastAllowManaged = allowManaged;
    lastOffline = offline;
    return File(javaPath);
  }

  @override
  Future<int?> probeMajorVersion(String javaPath) async => null;
}

class _FakeRunProcess {
  String? executable;
  List<String>? args;
  Directory? workingDirectory;
  bool? runInShell;
  Map<String, String>? environment;
  int exitCode = 0;

  _FakeRunProcess();

  Future<int> call(
    String exe,
    List<String> a, {
    Directory? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
  }) async {
    executable = exe;
    args = a;
    this.workingDirectory = workingDirectory;
    this.runInShell = runInShell;
    this.environment = environment;
    return exitCode;
  }
}

void main() {
  group('runLaunchServer', () {
    late Directory tempRoot;
    late Directory packDir;
    late Directory buildDir;
    late Directory serverDir;
    late ManifestIo io;
    late ProviderContainer container;
    late _FakeResolver fakeResolver;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_launch_');
      packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
      buildDir = Directory(p.join(packDir.path, 'build'))..createSync();
      serverDir = Directory(p.join(buildDir.path, 'server'))..createSync();
      io = ManifestIo(directory: packDir);
      container = ProviderContainer();
      fakeResolver = _FakeResolver(
        javaPath: p.join(tempRoot.path, 'fake', 'bin', 'java'),
      );
    });

    tearDown(() {
      container.dispose();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    void writeLock(ModsLock lock) {
      File(io.modsLockPath).writeAsStringSync(emitModsLock(lock));
    }

    test('--accept-eula writes eula.txt with eula=true', () async {
      writeLock(_lock());
      File(p.join(serverDir.path, 'fabric-server-launch.jar'))
          .writeAsStringSync('FAB-LAUNCH');
      final fake = _FakeRunProcess();

      final code = await runLaunchServer(
        options: const LaunchServerOptions(
          acceptEula: true,
          autoBuild: false,
          memory: '2G',
          offline: false,
          verbose: false,
          extraArgs: [],
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess: fake.call,
        resolver: fakeResolver,
      );

      expect(code, 0);
      final eula = File(p.join(serverDir.path, 'eula.txt'));
      expect(eula.existsSync(), isTrue);
      expect(eula.readAsStringSync(), 'eula=true\n');
    });

    test('Fabric launch invokes java -jar fabric-server-launch.jar nogui',
        () async {
      writeLock(_lock(loader: Loader.fabric));
      File(p.join(serverDir.path, 'fabric-server-launch.jar'))
          .writeAsStringSync('FAB');
      final fake = _FakeRunProcess();

      await runLaunchServer(
        options: const LaunchServerOptions(
          acceptEula: false,
          autoBuild: false,
          memory: '4G',
          offline: false,
          verbose: false,
          extraArgs: ['--port', '25566'],
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess: fake.call,
        resolver: fakeResolver,
      );

      expect(fake.executable, isNotNull);
      // Fabric runs the resolved JDK directly (not run.sh / run.bat).
      expect(fake.executable, fakeResolver.javaPath);
      expect(fake.args, contains('-Xmx4G'));
      expect(fake.args, contains('-Xms4G'));
      expect(fake.args, contains('-jar'));
      expect(fake.args, contains('fabric-server-launch.jar'));
      expect(fake.args, contains('nogui'));
      expect(fake.args, containsAllInOrder(['--port', '25566']));
      expect(fake.workingDirectory?.path, serverDir.path);
    });

    test('--java and --no-managed-java flow through to the resolver',
        () async {
      writeLock(_lock(loader: Loader.fabric));
      File(p.join(serverDir.path, 'fabric-server-launch.jar'))
          .writeAsStringSync('FAB');
      await runLaunchServer(
        options: LaunchServerOptions(
          acceptEula: false,
          autoBuild: false,
          memory: '2G',
          offline: false,
          verbose: false,
          extraArgs: const [],
          javaPath: '/some/explicit/java',
          allowManagedJava: false,
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess: _FakeRunProcess().call,
        resolver: fakeResolver,
      );
      expect(fakeResolver.lastExplicitPath, '/some/explicit/java');
      expect(fakeResolver.lastAllowManaged, isFalse);
      expect(fakeResolver.lastMcVersion, '1.21.1');
    });

    test('Fabric launch does not write eula.txt without --accept-eula',
        () async {
      writeLock(_lock(loader: Loader.fabric));
      File(p.join(serverDir.path, 'fabric-server-launch.jar'))
          .writeAsStringSync('FAB');
      await runLaunchServer(
        options: const LaunchServerOptions(
          acceptEula: false,
          autoBuild: false,
          memory: '2G',
          offline: false,
          verbose: false,
          extraArgs: [],
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess: _FakeRunProcess().call,
        resolver: fakeResolver,
      );
      expect(File(p.join(serverDir.path, 'eula.txt')).existsSync(), isFalse);
    });

    test(
      'autoBuild=true delegates to doBuild with env=server before launching',
      () async {
        writeLock(_lock(loader: Loader.fabric));
        File(p.join(serverDir.path, 'fabric-server-launch.jar'))
            .writeAsStringSync('FAB');

        BuildOptions? captured;
        final fake = _FakeRunProcess();

        final code = await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: true,
            memory: '2G',
            offline: false,
            verbose: false,
            extraArgs: [],
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: fake.call,
        resolver: fakeResolver,
          doBuild: (opts) async {
            captured = opts;
            return 0;
          },
        );

        expect(code, 0);
        expect(captured, isNotNull);
        expect(captured!.envFlag, 'server');
      },
    );

    test('autoBuild failure short-circuits before spawning the server',
        () async {
      writeLock(_lock(loader: Loader.fabric));
      var spawnCalled = false;
      final code = await runLaunchServer(
        options: const LaunchServerOptions(
          acceptEula: false,
          autoBuild: true,
          memory: '2G',
          offline: false,
          verbose: false,
          extraArgs: [],
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
          spawnCalled = true;
          return 0;
        },
        doBuild: (_) async => 7,
      );
      expect(code, 7);
      expect(spawnCalled, isFalse);
    });

    test(
      'mods.lock missing surfaces a UserError pointing to gitrinth get',
      () async {
        await expectLater(
          runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memory: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: _FakeRunProcess().call,
        resolver: fakeResolver,
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('mods.lock'),
            ),
          ),
        );
      },
    );

    test(
      'missing build/server when --no-build surfaces a clear UserError',
      () async {
        writeLock(_lock(loader: Loader.fabric));
        serverDir.deleteSync(recursive: true);
        await expectLater(
          runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memory: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: _FakeRunProcess().call,
        resolver: fakeResolver,
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('server distribution not found'),
            ),
          ),
        );
      },
    );

    group('Forge / NeoForge', () {
      test(
        'on POSIX, Forge launch shells out to bash run.sh',
        () async {
          writeLock(_lock(loader: Loader.forge));
          File(p.join(serverDir.path, 'run.sh'))
            ..writeAsStringSync('#!/bin/sh\n')
            ..renameSync(p.join(serverDir.path, 'run.sh'));

          final fake = _FakeRunProcess();
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memory: '6G',
              offline: false,
              verbose: false,
              extraArgs: ['--port', '25566'],
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: fake.call,
        resolver: fakeResolver,
          );

          if (Platform.isWindows) {
            // On Windows, the command picks run.bat — skip this branch.
            return;
          }
          expect(fake.executable, 'bash');
          expect(fake.args!.first, endsWith('run.sh'));
          expect(fake.args, containsAllInOrder(['--port', '25566']));
          // Memory is written into user_jvm_args.txt rather than CLI flags.
          final userArgs = File(
            p.join(serverDir.path, 'user_jvm_args.txt'),
          );
          expect(userArgs.existsSync(), isTrue);
          expect(userArgs.readAsStringSync(), contains('-Xmx6G'));
          expect(userArgs.readAsStringSync(), contains('-Xms6G'));
        },
        // Skip on Windows; Windows path is exercised by the next test.
        skip: Platform.isWindows ? 'POSIX-only' : null,
      );

      test(
        'on Windows, Forge launch shells out to run.bat',
        () async {
          writeLock(_lock(loader: Loader.forge));
          File(p.join(serverDir.path, 'run.bat'))
              .writeAsStringSync('@echo off\n');
          final fake = _FakeRunProcess();
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memory: '6G',
              offline: false,
              verbose: false,
              extraArgs: [],
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: fake.call,
        resolver: fakeResolver,
          );
          expect(fake.executable, endsWith('run.bat'));
          expect(fake.runInShell, isTrue);
          // The chosen JDK's bin/ is prepended to PATH and JAVA_HOME
          // points at its parent so the unmodified run.bat picks it up.
          expect(fake.environment, isNotNull);
          final fakeJavaBinDir = p.dirname(fakeResolver.javaPath);
          expect(
            fake.environment!['PATH'],
            startsWith(fakeJavaBinDir),
          );
          expect(
            fake.environment!['JAVA_HOME'],
            p.dirname(fakeJavaBinDir),
          );
        },
        skip: !Platform.isWindows ? 'Windows-only' : null,
      );

      test(
        'preserves non-Xmx lines in user_jvm_args.txt',
        () async {
          writeLock(_lock(loader: Loader.forge));
          // POSIX-only: Windows uses run.bat without preserving args
          if (Platform.isWindows) return;
          File(p.join(serverDir.path, 'run.sh'))
              .writeAsStringSync('#!/bin/sh\n');
          File(p.join(serverDir.path, 'user_jvm_args.txt'))
              .writeAsStringSync('-Xmx512M\n-XX:+UseG1GC\n# comment\n');
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memory: '8G',
              offline: false,
              verbose: false,
              extraArgs: [],
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: _FakeRunProcess().call,
        resolver: fakeResolver,
          );
          final body = File(
            p.join(serverDir.path, 'user_jvm_args.txt'),
          ).readAsStringSync();
          expect(body, contains('-XX:+UseG1GC'));
          expect(body, contains('# comment'));
          expect(body, contains('-Xmx8G'));
          expect(body, isNot(contains('-Xmx512M')));
        },
        skip: Platform.isWindows ? 'POSIX-only' : null,
      );

      test(
        'missing run.sh / run.bat surfaces a clear UserError',
        () async {
          writeLock(_lock(loader: Loader.forge));
          await expectLater(
            runLaunchServer(
              options: const LaunchServerOptions(
                acceptEula: false,
                autoBuild: false,
                memory: '2G',
                offline: false,
                verbose: false,
                extraArgs: [],
              ),
              container: container,
              console: const Console(),
              io: io,
              runProcess: _FakeRunProcess().call,
        resolver: fakeResolver,
            ),
            throwsA(
              isA<UserError>().having(
                (e) => e.message,
                'message',
                contains('server scripts not found'),
              ),
            ),
          );
        },
      );
    });
  });
}
