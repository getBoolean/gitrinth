import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/offline_flag.dart';
import 'build_orchestrator.dart';

class BuildCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'build';

  @override
  String get description =>
      'Assemble client and/or server distributions into build/.';

  @override
  String get invocation =>
      'gitrinth build [<client|server|both>] [arguments]';

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
        verbose: gitrinthRunner.verbose,
        javaPath: argResults!['java'] as String?,
        allowManagedJava: argResults!['managed-java'] as bool,
      ),
      container: container,
      console: console,
    );
  }
}
