import '../cli/base_command.dart';
import '../cli/exceptions.dart';

class PackCommand extends GitrinthCommand {
  @override
  String get name => 'pack';

  @override
  String get description => 'Produce a Modrinth .mrpack artifact.';

  @override
  String get invocation => 'gitrinth pack [arguments]';

  PackCommand() {
    argParser.addOption(
      'output',
      abbr: 'o',
      valueHelp: 'path',
      help: 'Override the output path. Defaults to ./<slug>-<version>.mrpack.',
    );
  }

  @override
  Future<int> run() async {
    // TODO(mvp): zip into .mrpack per Modrinth spec; refuse url/path mods.
    throw const UserError('pack: not yet implemented.');
  }
}
