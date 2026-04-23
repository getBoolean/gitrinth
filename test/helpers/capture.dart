import 'dart:io';

import 'package:path/path.dart' as p;

class CapturedOutput {
  final int exitCode;
  final String stdout;
  final String stderr;

  CapturedOutput(this.exitCode, this.stdout, this.stderr);
}

// `dart test` runs from the package root, so a cwd-relative path is reliable.
String _binPath() =>
    p.normalize(p.join(Directory.current.path, 'bin', 'gitrinth.dart'));

Future<CapturedOutput> runCli(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['run', _binPath(), ...args],
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: false,
  );
  return CapturedOutput(
    result.exitCode,
    result.stdout.toString(),
    result.stderr.toString(),
  );
}
