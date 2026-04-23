import '../cli/base_command.dart';
import '../cli/exceptions.dart';

class BuildCommand extends GitrinthCommand {
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
      );
  }

  @override
  Future<int> run() async {
    // TODO(mvp): partition by environment, emit build/client & build/server,
    // fetch server binary.
    throw const UserError('build: not yet implemented.');
  }
}
