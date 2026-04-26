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
import '../service/console.dart';
import '../version.dart';
import 'exceptions.dart';
import 'exit_codes.dart';

class GitrinthRunner extends CommandRunner<int> {
  LogLevel level = LogLevel.normal;
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
      ..addOption(
        'verbosity',
        valueHelp: 'level',
        allowed: [
          'error',
          'warning',
          'normal',
          'io',
          'solver',
          'all',
        ],
        allowedHelp: {
          'error': 'Errors only.',
          'warning': 'Errors and warnings.',
          'normal': 'User-facing messages (default).',
          'io': 'Adds file writes, downloads, and lockfile ops.',
          'solver': 'Adds version-resolution steps.',
          'all': 'Adds internal tracing (stack traces, debug).',
        },
        help: 'Set the output verbosity floor.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Shorthand for --verbosity=all.',
      )
      ..addFlag(
        'quiet',
        abbr: 'q',
        negatable: false,
        help: 'Shorthand for --verbosity=warning. Mutually exclusive '
            'with --verbose.',
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
    final verbose = topLevelResults['verbose'] as bool;
    final quiet = topLevelResults['quiet'] as bool;
    final verbosityRaw = topLevelResults['verbosity'] as String?;

    if (verbose && quiet) {
      throw UsageException('Cannot combine --verbose and --quiet.', usage);
    }
    if (verbosityRaw != null && (verbose || quiet)) {
      throw UsageException(
        'Cannot combine --verbosity with --verbose or --quiet.',
        usage,
      );
    }

    if (verbosityRaw != null) {
      final parsed = parseLogLevel(verbosityRaw);
      if (parsed == null) {
        throw UsageException(
          'Unknown verbosity level "$verbosityRaw". '
          'Valid levels: error, warning, normal, io, solver, all.',
          usage,
        );
      }
      level = parsed;
    } else if (verbose) {
      level = LogLevel.all;
    } else if (quiet) {
      level = LogLevel.warning;
    } else {
      level = LogLevel.normal;
    }

    color = topLevelResults.wasParsed('color')
        ? topLevelResults['color'] as bool
        : null;
    configPath = topLevelResults['config'] as String?;

    container
        .read(runnerSettingsProvider.notifier)
        .set(
          RunnerSettings(
            level: level,
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
    if (runner.level == LogLevel.all) {
      stderr.writeln(stack);
    }
    return exitUserError;
  } finally {
    runner.container.dispose();
  }
}
