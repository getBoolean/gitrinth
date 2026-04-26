import 'dart:io';

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
