import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:riverpod/riverpod.dart';

import '../app/container.dart';
import '../commands/add_command.dart';
import '../commands/build_command.dart';
import '../commands/clean_command.dart';
import '../commands/completion_command.dart';
import '../commands/create_command.dart';
import '../commands/get_command.dart';
import '../commands/pack_command.dart';
import '../commands/remove_command.dart';
import '../version.dart';
import 'exceptions.dart';
import 'exit_codes.dart';

class GitrinthRunner extends CommandRunner<int> {
  bool verbose = false;
  final ProviderContainer container;

  GitrinthRunner({ProviderContainer? container})
    : container = container ?? buildContainer(),
      super('gitrinth', 'Manage Modrinth modpacks declared in mods.yaml.') {
    argParser
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the gitrinth version and exit.',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        valueHelp: 'path',
        help: 'Run as if invoked from <path>.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Emit resolution detail.',
      );

    addCommand(CreateCommand());
    addCommand(GetCommand());
    addCommand(AddCommand());
    addCommand(RemoveCommand());
    addCommand(BuildCommand());
    addCommand(CleanCommand());
    addCommand(PackCommand());
    addCommand(CompletionCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    final result = await super.run(args);
    return result ?? exitOk;
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    verbose = topLevelResults['verbose'] as bool;

    if (topLevelResults['version'] as bool) {
      stdout.writeln('gitrinth $packageVersion');
      return exitOk;
    }

    final directory = topLevelResults['directory'] as String?;
    if (directory != null) {
      final dir = Directory(directory);
      if (!dir.existsSync()) {
        throw UserError('Directory not found: $directory');
      }
      Directory.current = dir;
    }

    return await super.runCommand(topLevelResults);
  }
}

Future<int> runGitrinth(
  List<String> arguments, {
  ProviderContainer? container,
}) async {
  final runner = GitrinthRunner(container: container);
  try {
    return await runner.run(arguments);
  } on GitrinthException catch (e) {
    stderr.writeln('error: ${e.message}');
    return e.exitCode;
  } on UsageException catch (e) {
    stderr.writeln(e.toString());
    return exitUsageError;
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    return exitUsageError;
  } catch (e, stack) {
    stderr.writeln('error: $e');
    if (runner.verbose) {
      stderr.writeln(stack);
    }
    return exitUserError;
  } finally {
    runner.container.dispose();
  }
}
