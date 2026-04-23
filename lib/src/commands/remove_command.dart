import '../cli/base_command.dart';
import '../cli/exceptions.dart';

class RemoveCommand extends GitrinthCommand {
  @override
  String get name => 'remove';

  @override
  String get description => 'Remove an entry from mods.yaml.';

  @override
  String get invocation => 'gitrinth remove <slug> [arguments]';

  RemoveCommand() {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Print the edit without writing.',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError('remove requires a slug: gitrinth remove <slug>');
    }
    if (rest.length > 1) {
      throw UsageError('Unexpected arguments after slug: ${rest.skip(1).join(' ')}');
    }

    // TODO(mvp): parse mods.yaml, locate slug across sections, remove entry.
    throw const UserError('remove: not yet implemented.');
  }
}
