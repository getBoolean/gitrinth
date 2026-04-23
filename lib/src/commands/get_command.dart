import '../cli/base_command.dart';
import '../cli/exceptions.dart';

class GetCommand extends GitrinthCommand {
  @override
  String get name => 'get';

  @override
  String get description =>
      'Resolve mods.yaml, write mods.lock, download artifacts.';

  @override
  String get invocation => 'gitrinth get [arguments]';

  GetCommand() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Resolve without writing. Exits non-zero if the lockfile would change.',
      )
      ..addFlag(
        'enforce-lockfile',
        negatable: false,
        help:
            'Fail if mods.lock would change. Also forbids missing lockfile entries.',
      );
  }

  @override
  Future<int> run() async {
    // TODO(mvp): implement get — resolver + mods.lock + artifact cache.
    throw const UserError('get: not yet implemented.');
  }
}
