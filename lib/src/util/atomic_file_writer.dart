import 'dart:io';
import 'dart:math';

/// Replaces a string file through a unique sibling, preserving the destination
/// until rename and keeping concurrent writers' staging files independent.
/// A persistent `$path.lock` sibling serializes Windows destination replacement.
File atomicReplaceString(String path, String contents) {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final temporary = File('$path.tmp-$suffix');
  try {
    File(path).parent.createSync(recursive: true);
    final lock = File('$path.lock').openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.blockingExclusive);
      try {
        temporary.writeAsStringSync(contents, flush: true);
        return temporary.renameSync(path);
      } finally {
        lock.unlockSync();
      }
    } finally {
      lock.closeSync();
    }
  } finally {
    if (temporary.existsSync()) {
      try {
        temporary.deleteSync();
      } on FileSystemException {
        // Cleanup must not replace the original write/rename failure.
      }
    }
  }
}

/// Writes [bytes] atomically to [path] by writing to `<path>.tmp` and renaming.
/// On failure, removes the orphan temp file.
Future<File> atomicWrite(String path, List<int> bytes) async {
  final tempFile = File('$path.tmp');
  try {
    await tempFile.writeAsBytes(bytes, flush: true);
    final dest = File(path);
    if (dest.existsSync()) dest.deleteSync();
    return tempFile.renameSync(path);
  } catch (_) {
    if (tempFile.existsSync()) {
      try {
        tempFile.deleteSync();
      } catch (_) {}
    }
    rethrow;
  }
}

/// Synchronous string variant. See [atomicWrite].
File atomicWriteString(String path, String contents) {
  final tempFile = File('$path.tmp');
  try {
    tempFile.writeAsStringSync(contents, flush: true);
    final dest = File(path);
    if (dest.existsSync()) dest.deleteSync();
    return tempFile.renameSync(path);
  } catch (_) {
    if (tempFile.existsSync()) {
      try {
        tempFile.deleteSync();
      } catch (_) {}
    }
    rethrow;
  }
}
