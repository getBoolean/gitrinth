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

ModsLock _lock({
  ModLoader loader = ModLoader.fabric,
  String mcVersion = '1.21.1',
}) {
  return ModsLock(
    gitrinthVersion: '0.1.0',
    loader: LoaderConfig(mods: loader, modsVersion: '0.17.3'),
    mcVersion: mcVersion,
  );
}

/// Stub resolver with a fixed `java` path and major version.
class _FakeResolver implements JavaRuntimeResolver {
  final String javaPath;
  final int majorVersion;
  String? lastMcVersion;
  String? lastExplicitPath;
  bool? lastAllowManaged;
  bool? lastOffline;

  _FakeResolver({required this.javaPath, this.majorVersion = 21});

  @override
  Future<({File binary, int majorVersion})> resolve({
    required String mcVersion,
    String? explicitPath,
    bool allowManaged = true,
    bool offline = false,
  }) async {
    lastMcVersion = mcVersion;
    lastExplicitPath = explicitPath;
    lastAllowManaged = allowManaged;
    lastOffline = offline;
    return (binary: File(javaPath), majorVersion: majorVersion);
  }

  @override
  Future<int?> probeMajorVersion(String javaPath) async => null;
}

/// Captures `console.message(...)` for detach-mode assertions.
class _CapturingConsole implements Console {
  final List<String> messages = [];

  @override
  LogLevel get level => LogLevel.normal;

  @override
  bool get useAnsi => false;

  @override
  void message(String msg) => messages.add(msg);

  @override
  void error(String message) {}

  @override
  void warn(String message) {}

  @override
  void io(String msg) {}

  @override
  void solver(String msg) {}

  @override
  void trace(String msg) {}

  @override
  void raw(String message) {}

  @override
  String bold(String s) => s;

  @override
  String red(String s) => s;

  @override
  String gray(String s) => s;
}

class _FakeRunProcess {
  String? executable;
  List<String>? args;
  Directory? workingDirectory;
  bool? runInShell;
  Map<String, String>? environment;
  ProcessStartMode? mode;
  int exitCode = 0;
  int pid = 4242;

  _FakeRunProcess();

  Future<LaunchProcessResult> call(
    String exe,
    List<String> a, {
    Directory? workingDirectory,
    bool runInShell = false,
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.inheritStdio,
  }) async {
    executable = exe;
    args = a;
    this.workingDirectory = workingDirectory;
    this.runInShell = runInShell;
    this.environment = environment;
    this.mode = mode;
    return (
      pid: pid,
      exitCode: mode == ProcessStartMode.detached ? null : exitCode,
    );
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
      File(
        p.join(serverDir.path, 'fabric-server-launch.jar'),
      ).writeAsStringSync('FAB-LAUNCH');
      final fake = _FakeRunProcess();

      final code = await runLaunchServer(
        options: const LaunchServerOptions(
          acceptEula: true,
          autoBuild: false,
          memoryMax: '2G',
          memoryMin: '2G',
          offline: false,
          verbose: false,
          extraArgs: [],
          headless: false,
          detach: false,
          force: false,
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

    test(
      'Fabric launch invokes java -jar fabric-server-launch.jar without nogui '
      'by default',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        File(
          p.join(serverDir.path, 'fabric-server-launch.jar'),
        ).writeAsStringSync('FAB');
        final fake = _FakeRunProcess();

        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '4G',
            memoryMin: '4G',
            offline: false,
            verbose: false,
            extraArgs: ['--port', '25566'],
            headless: false,
            detach: false,
            force: false,
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
        // GC flags should come before heap flags.
        final gcIdx = fake.args!.indexOf('-XX:+UseZGC');
        final xmxIdx = fake.args!.indexOf('-Xmx4G');
        expect(
          gcIdx,
          isNonNegative,
          reason:
              'ZGC should be injected before heap flags',
        );
        expect(xmxIdx, greaterThan(gcIdx));
        expect(fake.args, contains('-Xms4G'));
        expect(fake.args, contains('-jar'));
        expect(fake.args, contains('fabric-server-launch.jar'));
        expect(
          fake.args,
          isNot(contains('nogui')),
          reason:
              'headless defaults to false; nogui must only appear when the '
              'user opts in via --headless',
        );
        expect(fake.args, containsAllInOrder(['--port', '25566']));
        expect(fake.workingDirectory?.path, serverDir.path);
      },
    );

    test(
      'Fabric launch with --headless appends nogui to the JVM args',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        File(
          p.join(serverDir.path, 'fabric-server-launch.jar'),
        ).writeAsStringSync('FAB');
        final fake = _FakeRunProcess();

        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '4G',
            memoryMin: '4G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: true,
            detach: false,
            force: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: fake.call,
          resolver: fakeResolver,
        );

        expect(fake.args, contains('nogui'));
      },
    );

    test('Fabric on JDK 17 injects Shenandoah', () async {
      writeLock(_lock(loader: ModLoader.fabric, mcVersion: '1.20.4'));
      File(
        p.join(serverDir.path, 'fabric-server-launch.jar'),
      ).writeAsStringSync('FAB');
      final j17Resolver = _FakeResolver(
        javaPath: p.join(tempRoot.path, 'fake17', 'bin', 'java'),
        majorVersion: 17,
      );
      final fake = _FakeRunProcess();

      await runLaunchServer(
        options: const LaunchServerOptions(
          acceptEula: false,
          autoBuild: false,
          memoryMax: '2G',
          memoryMin: '2G',
          offline: false,
          verbose: false,
          extraArgs: [],
          headless: false,
          detach: false,
          force: false,
        ),
        container: container,
        console: const Console(),
        io: io,
        runProcess: fake.call,
        resolver: j17Resolver,
      );

      expect(
        fake.args,
        contains('-XX:+UseShenandoahGC'),
        reason: 'JDK 17 should use Shenandoah',
      );
      expect(
        fake.args,
        isNot(contains('-XX:+UseZGC')),
        reason: 'ZGC is reserved for JDK 21+',
      );
      expect(
        fake.args,
        isNot(contains('-XX:+UnlockExperimentalVMOptions')),
        reason: 'Shenandoah does not need the unlock flag on JDK 15+',
      );
    });

    test('--java and --no-managed-java flow through to the resolver', () async {
      writeLock(_lock(loader: ModLoader.fabric));
      File(
        p.join(serverDir.path, 'fabric-server-launch.jar'),
      ).writeAsStringSync('FAB');
      await runLaunchServer(
        options: LaunchServerOptions(
          acceptEula: false,
          autoBuild: false,
          memoryMax: '2G',
          memoryMin: '2G',
          offline: false,
          verbose: false,
          extraArgs: const [],
          javaPath: '/some/explicit/java',
          allowManagedJava: false,
          headless: false,
          detach: false,
          force: false,
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

    test(
      'Fabric launch does not write eula.txt without --accept-eula',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        File(
          p.join(serverDir.path, 'fabric-server-launch.jar'),
        ).writeAsStringSync('FAB');
        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '2G',
            memoryMin: '2G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: false,
            detach: false,
            force: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: _FakeRunProcess().call,
          resolver: fakeResolver,
        );
        expect(File(p.join(serverDir.path, 'eula.txt')).existsSync(), isFalse);
      },
    );

    test(
      'autoBuild=true delegates to doBuild with env=server before launching',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        File(
          p.join(serverDir.path, 'fabric-server-launch.jar'),
        ).writeAsStringSync('FAB');

        BuildOptions? captured;
        final fake = _FakeRunProcess();

        final code = await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: true,
            memoryMax: '2G',
            memoryMin: '2G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: false,
            detach: false,
            force: false,
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

    test(
      'autoBuild failure short-circuits before spawning the server',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        var spawnCalled = false;
        final code = await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: true,
            memoryMax: '2G',
            memoryMin: '2G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: false,
            detach: false,
            force: false,
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
                spawnCalled = true;
                return (pid: 1, exitCode: 0);
              },
          doBuild: (_) async => 7,
        );
        expect(code, 7);
        expect(spawnCalled, isFalse);
      },
    );

    test(
      'mods.lock missing surfaces a UserError pointing to gitrinth get',
      () async {
        await expectLater(
          runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '2G',
              memoryMin: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: false,
              force: false,
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
      'missing build/server with --no-build throws UserError',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        serverDir.deleteSync(recursive: true);
        await expectLater(
          runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '2G',
              memoryMin: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: false,
              force: false,
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

    test(
      '--memory-max only sets Xmx; Xms falls back to --memory default',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        File(
          p.join(serverDir.path, 'fabric-server-launch.jar'),
        ).writeAsStringSync('FAB');
        final fake = _FakeRunProcess();
        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '6G',
            memoryMin: '2G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: false,
            detach: false,
            force: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: fake.call,
          resolver: fakeResolver,
        );
        expect(fake.args, contains('-Xmx6G'));
        expect(fake.args, contains('-Xms2G'));
      },
    );

    test(
      '--memory + --memory-max: max wins for Xmx, --memory wins for Xms',
      () async {
        writeLock(_lock(loader: ModLoader.fabric));
        File(
          p.join(serverDir.path, 'fabric-server-launch.jar'),
        ).writeAsStringSync('FAB');
        final fake = _FakeRunProcess();
        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '8G',
            memoryMin: '4G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: false,
            detach: false,
            force: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: fake.call,
          resolver: fakeResolver,
        );
        expect(fake.args, contains('-Xmx8G'));
        expect(fake.args, contains('-Xms4G'));
      },
    );

    group('Forge / NeoForge', () {
      test(
        'on POSIX, Forge launch shells out to bash run.sh',
        () async {
          writeLock(_lock(loader: ModLoader.forge));
          File(p.join(serverDir.path, 'run.sh'))
            ..writeAsStringSync('#!/bin/sh\n')
            ..renameSync(p.join(serverDir.path, 'run.sh'));

          final fake = _FakeRunProcess();
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '6G',
              memoryMin: '6G',
              offline: false,
              verbose: false,
              extraArgs: ['--port', '25566'],
              headless: false,
              detach: false,
              force: false,
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
          final userArgs = File(p.join(serverDir.path, 'user_jvm_args.txt'));
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
          writeLock(_lock(loader: ModLoader.forge));
          File(
            p.join(serverDir.path, 'run.bat'),
          ).writeAsStringSync('@echo off\n');
          final fake = _FakeRunProcess();
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '6G',
              memoryMin: '6G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: false,
              force: false,
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
          expect(fake.environment!['PATH'], startsWith(fakeJavaBinDir));
          expect(fake.environment!['JAVA_HOME'], p.dirname(fakeJavaBinDir));
        },
        skip: !Platform.isWindows ? 'Windows-only' : null,
      );

      test(
        'rewrites user_jvm_args.txt with managed GC and heap flags',
        () async {
          writeLock(_lock(loader: ModLoader.forge));
          // POSIX-only: Windows uses run.bat without preserving args
          if (Platform.isWindows) return;
          File(
            p.join(serverDir.path, 'run.sh'),
          ).writeAsStringSync('#!/bin/sh\n');
          File(
            p.join(serverDir.path, 'user_jvm_args.txt'),
          ).writeAsStringSync('-Xmx512M\n-XX:+UseG1GC\n# comment\n');
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '8G',
              memoryMin: '8G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: false,
              force: false,
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
          // Drop old GC flags.
          expect(body, isNot(contains('-XX:+UseG1GC')));
          expect(body, contains('-XX:+UseZGC'));
          // Keep unrelated lines.
          expect(body, contains('# comment'));
          expect(body, contains('-Xmx8G'));
          expect(body, isNot(contains('-Xmx512M')));
        },
        skip: Platform.isWindows ? 'POSIX-only' : null,
      );

      test(
        'JDK 17 modpack writes Shenandoah (no unlock) into user_jvm_args.txt',
        () async {
          writeLock(_lock(loader: ModLoader.forge, mcVersion: '1.20.4'));
          if (Platform.isWindows) {
            File(
              p.join(serverDir.path, 'run.bat'),
            ).writeAsStringSync('@echo off\n');
          } else {
            File(
              p.join(serverDir.path, 'run.sh'),
            ).writeAsStringSync('#!/bin/sh\n');
          }
          final j17Resolver = _FakeResolver(
            javaPath: p.join(tempRoot.path, 'fake17', 'bin', 'java'),
            majorVersion: 17,
          );
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '4G',
              memoryMin: '4G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: false,
              force: false,
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: _FakeRunProcess().call,
            resolver: j17Resolver,
          );
          final body = File(
            p.join(serverDir.path, 'user_jvm_args.txt'),
          ).readAsStringSync();
          expect(body, contains('-XX:+UseShenandoahGC'));
          expect(body, isNot(contains('-XX:+UseZGC')));
          expect(body, isNot(contains('-XX:+UnlockExperimentalVMOptions')));
        },
      );

      test('JDK 8-14 writes unlock + Shenandoah without duplicates', () async {
        writeLock(_lock(loader: ModLoader.forge, mcVersion: '1.16.5'));
        if (Platform.isWindows) {
          File(
            p.join(serverDir.path, 'run.bat'),
          ).writeAsStringSync('@echo off\n');
        } else {
          File(
            p.join(serverDir.path, 'run.sh'),
          ).writeAsStringSync('#!/bin/sh\n');
        }
        // Existing unlock token should be replaced, not duplicated.
        File(p.join(serverDir.path, 'user_jvm_args.txt')).writeAsStringSync(
          '-XX:+UnlockExperimentalVMOptions\n-Dlog4j2.formatMsgNoLookups=true\n',
        );
        final j11Resolver = _FakeResolver(
          javaPath: p.join(tempRoot.path, 'fake11', 'bin', 'java'),
          majorVersion: 11,
        );
        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '2G',
            memoryMin: '2G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: false,
            detach: false,
            force: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: _FakeRunProcess().call,
          resolver: j11Resolver,
        );
        final body = File(
          p.join(serverDir.path, 'user_jvm_args.txt'),
        ).readAsStringSync();
        expect(body, contains('-XX:+UnlockExperimentalVMOptions'));
        expect(body, contains('-XX:+UseShenandoahGC'));
        expect(body, contains('-Dlog4j2.formatMsgNoLookups=true'));
        // Keep a single unlock token.
        expect(
          '-XX:+UnlockExperimentalVMOptions'.allMatches(body).length,
          1,
          reason: 'no duplicate unlock line after rewrite',
        );
      });

      test('missing run.sh / run.bat throws UserError', () async {
        writeLock(_lock(loader: ModLoader.forge));
        await expectLater(
          runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '2G',
              memoryMin: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: false,
              force: false,
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
      });

      test(
        'mismatched memoryMax/memoryMin write through to user_jvm_args.txt',
        () async {
          writeLock(_lock(loader: ModLoader.forge));
          if (Platform.isWindows) {
            File(
              p.join(serverDir.path, 'run.bat'),
            ).writeAsStringSync('@echo off\n');
          } else {
            File(
              p.join(serverDir.path, 'run.sh'),
            ).writeAsStringSync('#!/bin/sh\n');
          }
          await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '8G',
              memoryMin: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: false,
              force: false,
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
          expect(body, contains('-Xmx8G'));
          expect(body, contains('-Xms2G'));
        },
      );

      test('--headless appends nogui after user-supplied trailing args on the '
          'run script', () async {
        writeLock(_lock(loader: ModLoader.forge));
        if (Platform.isWindows) {
          File(
            p.join(serverDir.path, 'run.bat'),
          ).writeAsStringSync('@echo off\n');
        } else {
          File(
            p.join(serverDir.path, 'run.sh'),
          ).writeAsStringSync('#!/bin/sh\n');
        }
        final fake = _FakeRunProcess();
        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '4G',
            memoryMin: '4G',
            offline: false,
            verbose: false,
            extraArgs: ['--port', '25566'],
            headless: true,
            detach: false,
            force: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: fake.call,
          resolver: fakeResolver,
        );
        // The args list forwarded to run.bat / run.sh — on POSIX the first
        // element is the script path passed to bash, so trim it.
        final scriptArgs = Platform.isWindows
            ? fake.args!
            : fake.args!.sublist(1);
        expect(scriptArgs, containsAllInOrder(['--port', '25566', 'nogui']));
      });
    });

    group('detach', () {
      test('default (detach: false) spawns with inheritStdio mode', () async {
        writeLock(_lock(loader: ModLoader.fabric));
        File(
          p.join(serverDir.path, 'fabric-server-launch.jar'),
        ).writeAsStringSync('FAB');
        final fake = _FakeRunProcess();
        await runLaunchServer(
          options: const LaunchServerOptions(
            acceptEula: false,
            autoBuild: false,
            memoryMax: '2G',
            memoryMin: '2G',
            offline: false,
            verbose: false,
            extraArgs: [],
            headless: false,
            detach: false,
            force: false,
          ),
          container: container,
          console: const Console(),
          io: io,
          runProcess: fake.call,
          resolver: fakeResolver,
        );
        expect(fake.mode, ProcessStartMode.inheritStdio);
      });

      test(
        '--detach without --headless spawns detached and prints the PID',
        () async {
          writeLock(_lock(loader: ModLoader.fabric));
          File(
            p.join(serverDir.path, 'fabric-server-launch.jar'),
          ).writeAsStringSync('FAB');
          final fake = _FakeRunProcess()..pid = 31415;
          final captureConsole = _CapturingConsole();
          final code = await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '2G',
              memoryMin: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: false,
              detach: true,
              force: false,
            ),
            container: container,
            console: captureConsole,
            io: io,
            runProcess: fake.call,
            resolver: fakeResolver,
          );
          expect(code, 0);
          expect(fake.mode, ProcessStartMode.detached);
          expect(
            captureConsole.messages.any((m) => m.contains('31415')),
            isTrue,
            reason:
                'detach output should report the PID so the user can kill the '
                'server manually',
          );
        },
      );

      test(
        'POSIX: --detach --headless without --force throws before spawn',
        () async {
          writeLock(_lock(loader: ModLoader.fabric));
          File(
            p.join(serverDir.path, 'fabric-server-launch.jar'),
          ).writeAsStringSync('FAB');
          final fake = _FakeRunProcess();
          await expectLater(
            runLaunchServer(
              options: const LaunchServerOptions(
                acceptEula: false,
                autoBuild: false,
                memoryMax: '2G',
                memoryMin: '2G',
                offline: false,
                verbose: false,
                extraArgs: [],
                headless: true,
                detach: true,
                force: false,
              ),
              container: container,
              console: const Console(),
              io: io,
              runProcess: fake.call,
              resolver: fakeResolver,
            ),
            throwsA(
              isA<UserError>().having(
                (e) => e.message,
                'message',
                contains('silences the server'),
              ),
            ),
          );
          expect(
            fake.mode,
            isNull,
            reason: 'validation must reject the combo before spawning',
          );
        },
        // Windows gets a separate JVM console.
        skip: Platform.isWindows ? 'POSIX-only gate' : null,
      );

      test(
        'Windows: --detach --headless without --force is allowed',
        () async {
          writeLock(_lock(loader: ModLoader.fabric));
          File(
            p.join(serverDir.path, 'fabric-server-launch.jar'),
          ).writeAsStringSync('FAB');
          final fake = _FakeRunProcess();
          final code = await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '2G',
              memoryMin: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: true,
              detach: true,
              force: false,
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: fake.call,
            resolver: fakeResolver,
          );
          expect(code, 0);
          expect(fake.mode, ProcessStartMode.detached);
          expect(fake.args, contains('nogui'));
        },
        skip: !Platform.isWindows ? 'Windows-only behavior' : null,
      );

      test(
        '--detach --headless --force spawns detached and bypasses validation',
        () async {
          writeLock(_lock(loader: ModLoader.fabric));
          File(
            p.join(serverDir.path, 'fabric-server-launch.jar'),
          ).writeAsStringSync('FAB');
          final fake = _FakeRunProcess();
          final code = await runLaunchServer(
            options: const LaunchServerOptions(
              acceptEula: false,
              autoBuild: false,
              memoryMax: '2G',
              memoryMin: '2G',
              offline: false,
              verbose: false,
              extraArgs: [],
              headless: true,
              detach: true,
              force: true,
            ),
            container: container,
            console: const Console(),
            io: io,
            runProcess: fake.call,
            resolver: fakeResolver,
          );
          expect(code, 0);
          expect(fake.mode, ProcessStartMode.detached);
          expect(fake.args, contains('nogui'));
        },
      );
    });
  });

  group('resolveJvmHeap', () {
    test('defaults to 2G/2G when nothing is set', () {
      final (xmx, xms) = resolveJvmHeap();
      expect(xmx, 2 * 1024 * 1024 * 1024);
      expect(xms, 2 * 1024 * 1024 * 1024);
    });

    test('--memory sets both sides', () {
      final (xmx, xms) = resolveJvmHeap(memory: '4G');
      expect(xmx, 4 * 1024 * 1024 * 1024);
      expect(xms, 4 * 1024 * 1024 * 1024);
    });

    test('--memory-max overrides Xmx; --memory remains the Xms fallback', () {
      final (xmx, xms) = resolveJvmHeap(memory: '4G', memoryMax: '8G');
      expect(xmx, 8 * 1024 * 1024 * 1024);
      expect(xms, 4 * 1024 * 1024 * 1024);
    });

    test('--memory-min > --memory-max throws UserError', () {
      expect(
        () => resolveJvmHeap(memoryMax: '2G', memoryMin: '4G'),
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            allOf(contains('2G'), contains('4G')),
          ),
        ),
      );
    });

    test('invalid size literal throws UserError', () {
      expect(() => resolveJvmHeap(memory: '1.5G'), throwsA(isA<UserError>()));
      expect(() => resolveJvmHeap(memory: '2GB'), throwsA(isA<UserError>()));
    });

    test('M/K/T suffixes parse correctly', () {
      expect(resolveJvmHeap(memory: '6144M').$1, 6144 * 1024 * 1024);
      expect(resolveJvmHeap(memory: '512K').$1, 512 * 1024);
      expect(resolveJvmHeap(memory: '1T').$1, 1024 * 1024 * 1024 * 1024);
    });
  });
}
