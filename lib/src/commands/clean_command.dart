import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../service/manifest_io.dart';

class CleanCommand extends GitrinthCommand {
  @override
  String get name => 'clean';

  @override
  String get description =>
      'Delete files gitrinth generated: mods.lock and the build directory.';

  @override
  String get invocation => 'gitrinth clean [arguments]';

  CleanCommand() {
    argParser.addOption(
      'output',
      abbr: 'o',
      valueHelp: 'path',
      help: 'Build directory to remove. Defaults to ./build.',
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }

    final outputOpt = argResults!['output'] as String?;
    final io = ManifestIo();

    final removed = <String>[];

    final lockFile = File(io.modsLockPath);
    if (lockFile.existsSync()) {
      lockFile.deleteSync();
      removed.add(io.modsLockPath);
    }

    final buildDir = Directory(p.normalize(p.absolute(outputOpt ?? 'build')));
    if (buildDir.existsSync()) {
      buildDir.deleteSync(recursive: true);
      removed.add(buildDir.path);
    }

    if (removed.isEmpty) {
      console.message('Nothing to clean.');
    } else {
      for (final path in removed) {
        console.message('removed: $path');
      }
    }

    return exitOk;
  }
}
