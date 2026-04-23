import '../cli/base_command.dart';
import '../cli/exceptions.dart';

class AddCommand extends GitrinthCommand {
  @override
  String get name => 'add';

  @override
  String get description => 'Add an entry to a section.';

  @override
  String get invocation =>
      'gitrinth add <slug>[@<constraint>] [arguments]';

  AddCommand() {
    argParser
      ..addOption(
        'env',
        allowed: ['client', 'server', 'both'],
        valueHelp: 'client|server|both',
        help: 'Restrict the entry to a side.',
      )
      ..addOption(
        'url',
        valueHelp: 'url',
        help:
            'Use a url: source. Marks the pack non-publishable when added to mods.',
      )
      ..addOption(
        'path',
        valueHelp: 'path',
        help: 'Use a path: source.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the edit without writing.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError('add requires a slug: gitrinth add <slug>[@<constraint>]');
    }
    if (rest.length > 1) {
      throw UsageError('Unexpected arguments after slug: ${rest.skip(1).join(' ')}');
    }

    final url = argResults!['url'] as String?;
    final path = argResults!['path'] as String?;
    if (url != null && path != null) {
      throw const UsageError('--url and --path are mutually exclusive.');
    }

    // TODO(mvp): parse mods.yaml, infer target section, write entry.
    throw const UserError('add: not yet implemented.');
  }
}
