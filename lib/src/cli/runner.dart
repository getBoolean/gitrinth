import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:riverpod/riverpod.dart';

import '../app/container.dart';
import '../app/env.dart';
import '../app/runner_settings.dart';
import '../commands/add_command.dart';
import '../commands/build_command.dart';
import '../commands/cache_command.dart';
import '../commands/clean_command.dart';
import '../commands/completion_command.dart';
import '../commands/create_command.dart';
import '../commands/deps_command.dart';
import '../commands/downgrade_command.dart';
import '../commands/get_command.dart';
import '../commands/launch_command.dart';
import '../commands/migrate_command.dart';
import '../commands/outdated_command.dart';
import '../commands/override_command.dart';
import '../commands/pack_command.dart';
import '../commands/pin_command.dart';
import '../commands/remove_command.dart';
import '../commands/unpin_command.dart';
import '../commands/upgrade_command.dart';
import '../version.dart';
import 'exceptions.dart';
import 'exit_codes.dart';

class GitrinthRunner extends CommandRunner<int> {
  bool verbose = false;
  bool quiet = false;
  bool? color;
  String? configPath;
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
      )
      ..addFlag(
        'quiet',
        abbr: 'q',
        negatable: false,
        help: 'Suppress informational output; errors still print. '
            'Mutually exclusive with --verbose.',
      )
      ..addFlag(
        'color',
        help: 'Force ANSI colour on (--color) or off (--no-color). '
            'Defaults to auto-detection (honours NO_COLOR).',
      )
      ..addOption(
        'config',
        valueHelp: 'path',
        help: 'Use an alternate user config file. '
            'Overrides GITRINTH_CONFIG and the platform default.',
      );

    addCommand(CreateCommand());
    addCommand(GetCommand());
    addCommand(UpgradeCommand());
    addCommand(DowngradeCommand());
    addCommand(OutdatedCommand());
    addCommand(DepsCommand());
    addCommand(AddCommand());
    addCommand(RemoveCommand());
    addCommand(OverrideCommand());
    addCommand(PinCommand());
    addCommand(UnpinCommand());
    addCommand(BuildCommand());
    addCommand(CleanCommand());
    addCommand(PackCommand());
    addCommand(LaunchCommand());
    addCommand(MigrateCommand());
    addCommand(CacheCommand());
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
    quiet = topLevelResults['quiet'] as bool;
    color = topLevelResults.wasParsed('color')
        ? topLevelResults['color'] as bool
        : null;
    configPath = topLevelResults['config'] as String?;

    if (verbose && quiet) {
      throw UsageException(
        'Cannot combine --verbose and --quiet.',
        usage,
      );
    }

    container
        .read(runnerSettingsProvider.notifier)
        .set(
          RunnerSettings(
            verbose: verbose,
            quiet: quiet,
            color: color,
            configPath: configPath,
          ),
        );

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
  Map<String, String>? environment,
}) async {
  final effectiveContainer =
      container ??
      buildContainer(
        overrides: [
          if (environment != null)
            environmentProvider.overrideWithValue(environment),
        ],
      );
  final runner = GitrinthRunner(container: effectiveContainer);
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
