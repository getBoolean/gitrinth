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
  String get invocation => 'gitrinth build [arguments]';

  BuildCommand() {
    argParser
      ..addOption(
        'env',
        allowed: ['client', 'server', 'both'],
        valueHelp: 'client|server|both',
        help: 'Build only the named environment.',
      )
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
      );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }

    return runBuild(
      options: BuildOptions(
        envFlag: argResults!['env'] as String?,
        outputPath: argResults!['output'] as String?,
        clean: argResults!['clean'] as bool,
        skipDownload: argResults!['skip-download'] as bool,
        noPrune: argResults!['no-prune'] as bool,
        offline: readOfflineFlag(),
        verbose: gitrinthRunner.verbose,
      ),
      container: container,
      console: console,
    );
  }
}
