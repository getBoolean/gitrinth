import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import 'cache.dart';

class Downloader {
  final Dio dio;
  final GitrinthCache cache;

  Downloader({required this.dio, required this.cache});

  /// Downloads [url], verifies each supplied hash, then atomically renames
  /// the temporary file into [destinationPath]. Cached files are verified too.
  /// Returns the downloaded [File]. If the file already exists at the
  /// destination and satisfies the supplied hashes, no download is performed.
  Future<File> downloadTo({
    required String url,
    required String destinationPath,
    String? expectedSha512,
    String? expectedSha1,
  }) async {
    Future<void> verify(File file) async {
      if (expectedSha512 != null) {
        await GitrinthCache.verifyFileSha512(file, expectedSha512);
      }
      if (expectedSha1 != null) {
        await GitrinthCache.verifyFileSha1(file, expectedSha1);
      }
    }

    cache.ensureRoot();
    final destFile = File(destinationPath);
    if (destFile.existsSync()) {
      if (expectedSha512 != null || expectedSha1 != null) {
        try {
          await verify(destFile);
        } on UserError {
          destFile.deleteSync();
          // fall through and re-download
        }
        if (destFile.existsSync()) return destFile;
      } else {
        return destFile;
      }
    }

    Directory(p.dirname(destinationPath)).createSync(recursive: true);
    final tmpName =
        'dl_${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 32)}.part';
    final tmpPath = p.join(cache.tmpRoot, tmpName);
    final tmpFile = File(tmpPath);
    try {
      await dio.download(
        url,
        tmpPath,
        options: Options(responseType: ResponseType.bytes),
      );
      await verify(tmpFile);
      if (destFile.existsSync()) destFile.deleteSync();
      tmpFile.renameSync(destinationPath);
      return File(destinationPath);
    } catch (e) {
      if (tmpFile.existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
      if (e is GitrinthException) rethrow;
      if (e is DioException && e.error is GitrinthException) {
        throw e.error as GitrinthException;
      }
      throw UserError('download failed for $url: $e');
    }
  }
}
