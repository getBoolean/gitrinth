import 'dart:convert';
import 'dart:io';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../service/cache_inspector.dart';

class CacheCommand extends GitrinthCommand {
  @override
  String get name => 'cache';

  @override
  String get description =>
      'Inspect, clean, or repair the local artifact cache.';

  @override
  String get invocation => 'gitrinth cache <subcommand>';

  CacheCommand() {
    addSubcommand(CacheListCommand());
    addSubcommand(CacheCleanCommand());
    addSubcommand(CacheRepairCommand());
  }

  @override
  Future<int> run() async {
    // The args framework prints the subcommand list when no subcommand
    // is provided; reaching this point means the user passed something
    // unexpected.
    printUsage();
    return exitOk;
  }
}

class CacheListCommand extends GitrinthCommand {
  @override
  String get name => 'list';

  @override
  String get description => 'Print all cached artifacts as JSON.';

  @override
  String get invocation => 'gitrinth cache list';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
    final cache = read(cacheProvider);
    final inspector = CacheInspector(cache);
    final artifacts = inspector.walkArtifacts().toList();
    final body = <String, Object?>{
      'root': cache.root,
      'artifacts': [for (final a in artifacts) a.toJson()],
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(body));
    return exitOk;
  }
}

class CacheCleanCommand extends GitrinthCommand {
  @override
  String get name => 'clean';

  @override
  String get description =>
      'Delete every cached artifact. Prompts for confirmation '
      'unless --force is given.';

  @override
  String get invocation => 'gitrinth cache clean [--force]';

  CacheCleanCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Skip the confirmation prompt and wipe immediately.',
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }

    final force = argResults!['force'] as bool;
    final cache = read(cacheProvider);
    final inspector = CacheInspector(cache);

    if (!Directory(cache.root).existsSync()) {
      console.message('Cache is already empty (no cache root at ${cache.root}).');
      return exitOk;
    }

    final artifacts = inspector.walkArtifacts().toList();
    final size = inspector.totalSize(artifacts);

    if (!force) {
      if (!stdin.hasTerminal) {
        throw const UsageError(
          'cache clean: refusing to wipe without --force when stdin is '
          'not a terminal. Re-run with -f / --force.',
        );
      }
      stdout.write(
        'This will delete ${artifacts.length} cached '
        '${artifacts.length == 1 ? "artifact" : "artifacts"} '
        '(${_formatBytes(size)}) at ${cache.root}. '
        'Continue? [y/N] ',
      );
      final answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
      if (answer != 'y' && answer != 'yes') {
        console.message('Aborted.');
        return exitOk;
      }
    }

    final freed = await inspector.wipe();
    console.message(
      'Cleared ${artifacts.length} '
      '${artifacts.length == 1 ? "artifact" : "artifacts"} '
      '(${_formatBytes(freed)}) from ${cache.root}.',
    );
    return exitOk;
  }
}

class CacheRepairCommand extends GitrinthCommand {
  @override
  String get name => 'repair';

  @override
  String get description =>
      'Re-verify every cached file against its expected hash; '
      're-download corrupt Modrinth entries; delete corrupt url-sourced '
      'entries.';

  @override
  String get invocation => 'gitrinth cache repair';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }

    final cache = read(cacheProvider);
    final downloader = read(downloaderProvider);
    final inspector = CacheInspector(cache);

    if (!Directory(cache.root).existsSync()) {
      console.message('Cache is empty; nothing to repair.');
      return exitOk;
    }

    final outcome = await inspector.repair(downloader, console: console);

    final parts = <String>[
      '${outcome.verified} verified',
      if (outcome.redownloaded > 0) '${outcome.redownloaded} re-downloaded',
      if (outcome.deleted > 0) '${outcome.deleted} deleted',
      if (outcome.skippedOrphans.isNotEmpty)
        '${outcome.skippedOrphans.length} skipped',
    ];
    console.message('Cache repair: ${parts.join(", ")}.');
    return exitOk;
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes ${units[unit]}';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
