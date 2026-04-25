import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import 'server_installer.dart' show ProcessRunner;

/// Ensures [linkPath] is a directory symlink (POSIX) or junction (Windows)
/// pointing at [target]. Idempotent: a no-op if the link already resolves
/// to [target]; replaces the link if the target differs.
///
/// Throws [UserError] if [linkPath] already exists as a real directory or
/// file (we never delete user content). [target] must already exist;
/// `mklink /J` on Windows fails if it does not, so callers should pre-create.
Future<void> ensureDirSymlink({
  required String linkPath,
  required String target,
  ProcessRunner? runProcess,
}) async {
  final normalizedTarget = p.normalize(p.absolute(target));

  final link = Link(linkPath);
  if (link.existsSync()) {
    final existing = p.normalize(p.absolute(link.targetSync()));
    if (existing == normalizedTarget) return;
    link.deleteSync();
  } else if (FileSystemEntity.typeSync(linkPath) !=
      FileSystemEntityType.notFound) {
    throw UserError(
      'refusing to overwrite real path at $linkPath '
      '(expected a symlink/junction). Remove it manually if you meant to '
      'replace it with a link to $normalizedTarget.',
    );
  }

  if (Platform.isWindows) {
    final runner = runProcess ?? _defaultRunProcess;
    final exit = await runner(
      'cmd',
      ['/c', 'mklink', '/J', linkPath, normalizedTarget],
    );
    if (exit != 0) {
      throw UserError(
        'mklink /J failed (exit $exit) while creating junction '
        '$linkPath -> $normalizedTarget.',
      );
    }
  } else {
    Link(linkPath).createSync(normalizedTarget, recursive: false);
  }
}

Future<int> _defaultRunProcess(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
  bool runInShell = false,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory?.path,
    runInShell: runInShell,
  );
  if (result.exitCode != 0) {
    final out = (result.stdout as Object?)?.toString() ?? '';
    final err = (result.stderr as Object?)?.toString() ?? '';
    final detail = [out, err].where((s) => s.isNotEmpty).join('\n').trim();
    if (detail.isNotEmpty) {
      stderr.writeln(detail);
    }
  }
  return result.exitCode;
}
