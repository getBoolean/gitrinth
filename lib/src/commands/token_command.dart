import '../cli/base_command.dart';
import '../cli/exit_codes.dart';
import 'modrinth_command.dart';

/// Shared credentials namespace; legacy `modrinth token` remains supported.
class TokenCommand extends GitrinthCommand {
  TokenCommand() {
    addSubcommand(ModrinthTokenAddCommand());
    addSubcommand(ModrinthTokenListCommand());
    addSubcommand(ModrinthTokenRemoveCommand());
  }
  @override
  String get name => 'token';
  @override
  String get description =>
      'Manage Modrinth host and CurseForge publish tokens.';
  @override
  Future<int> run() async {
    printUsage();
    return exitOk;
  }
}
