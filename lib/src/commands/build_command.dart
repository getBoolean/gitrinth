/// `gitrinth build` is split across three sibling files for separation of
/// concerns. The orchestrator is the entry point — assembler and pruner
/// each own one phase and are not used independently.
///
///   - `build_command.dart`  — flag parsing + thin shell that delegates to
///     [runBuildOrchestrator].
///   - `build_orchestrator.dart` — drives the full build: kicks off
///     `resolveAndSync`, loads the prior ledger, calls the assembler for
///     each env, then hands off to the pruner.
///   - `build_assembler.dart` — pure file-copy + per-section / per-side
///     routing. Knows how to materialize a single `LockedEntry` into the
///     output tree but nothing about prior state.
///   - `build_pruner.dart`   — ledger reader/writer plus deletion logic.
///     Compares the prior ledger to the current build's manifest and
///     prunes files the new build no longer produces.
///
/// Ordering contract: orchestrator MUST call assembler before pruner so
/// the pruner sees the ledger entries the new build added before it
/// decides what to delete from the old ledger.
library;

import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/offline_flag.dart';
import '../service/console.dart';
import 'build_orchestrator.dart';

class BuildCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'build';

  @override
  String get description =>
      'Assemble client and/or server distributions into build/.';

  @override
  String get invocation => 'gitrinth build [<client|server|both>] [arguments]';

  BuildCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        valueHelp: 'path',
        help: 'Override the output directory. Defaults to ./build.',
      )
      ..addFlag(
        'clean',
        negatable: false,
        help: 'Remove the output directory before building.',
      )
      ..addFlag(
        'skip-download',
        negatable: false,
        help: 'Fail rather than fetch missing artifacts.',
      )
      ..addFlag(
        'no-prune',
        negatable: false,
        help:
            'Skip deleting obsolete files left over from a previous build. '
            'The new state ledger is still written. Useful for debugging '
            'prune behavior.',
      )
      ..addOption(
        'java',
        valueHelp: 'path',
        help:
            'Path to a `java` binary OR a JDK home directory used to run '
            'the Forge/NeoForge server installer. Overrides JAVA_HOME and '
            'the auto-managed JDK.',
      )
      ..addFlag(
        'managed-java',
        defaultsTo: true,
        help:
            'Auto-download a matching Eclipse Temurin JDK into the gitrinth '
            'cache when no system JDK satisfies the modpack. Use '
            '--no-managed-java to refuse and require --java/JAVA_HOME.',
      );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    String? envArg;
    if (rest.length > 1) {
      throw UsageError(
        'Expected at most one positional argument (client|server|both); '
        'got: ${rest.join(' ')}',
      );
    }
    if (rest.length == 1) {
      final value = rest.single;
      if (value != 'client' && value != 'server' && value != 'both') {
        throw UsageError(
          'Invalid environment "$value"; expected client, server, or both.',
        );
      }
      envArg = value;
    }

    return runBuild(
      options: BuildOptions(
        envFlag: envArg,
        outputPath: argResults!['output'] as String?,
        clean: argResults!['clean'] as bool,
        skipDownload: argResults!['skip-download'] as bool,
        noPrune: argResults!['no-prune'] as bool,
        offline: readOfflineFlag(),
        verbose: gitrinthRunner.level.index >= LogLevel.io.index,
        javaPath: argResults!['java'] as String?,
        allowManagedJava: argResults!['managed-java'] as bool,
      ),
      container: container,
      console: console,
    );
  }
}
