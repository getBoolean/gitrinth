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

  /// Downloads [url] into the cache at [destinationPath], verifies sha512
  /// (when provided), then atomically renames the temp file into place.
  /// Returns the downloaded [File]. If the file already exists at the
  /// destination, no download is performed; if [expectedSha512] is given the
  /// existing file is verified.
  Future<File> downloadTo({
    required String url,
    required String destinationPath,
    String? expectedSha512,
  }) async {
    cache.ensureRoot();
    final destFile = File(destinationPath);
    if (destFile.existsSync()) {
      if (expectedSha512 != null) {
        try {
          await GitrinthCache.verifyFileSha512(destFile, expectedSha512);
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
      if (expectedSha512 != null) {
        await GitrinthCache.verifyFileSha512(tmpFile, expectedSha512);
      }
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
