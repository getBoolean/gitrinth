import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';

class GitrinthCache {
  final String root;

  GitrinthCache({required this.root});

  String get modrinthRoot => p.join(root, 'modrinth');
  String get urlRoot => p.join(root, 'url');
  String get tmpRoot => p.join(root, 'tmp');

  /// Path where a Modrinth-sourced artifact should live.
  String modrinthPath({
    required String projectId,
    required String versionId,
    required String filename,
  }) {
    return p.join(modrinthRoot, projectId, versionId, filename);
  }

  /// Path where a url:-sourced artifact should live, keyed by sha512.
  String urlPath({required String sha512, required String filename}) {
    final lower = sha512.toLowerCase();
    if (lower.length < 2) {
      throw ArgumentError.value(sha512, 'sha512', 'must be at least 2 chars');
    }
    final prefix = lower.substring(0, 2);
    return p.join(urlRoot, prefix, lower, filename);
  }

  void ensureRoot() {
    Directory(root).createSync(recursive: true);
    Directory(tmpRoot).createSync(recursive: true);
  }

  /// Verifies [bytes] against [expectedSha512] (case-insensitive). Throws
  /// [UserError] on mismatch.
  static void verifySha512(List<int> bytes, String expectedSha512) {
    final actual = sha512.convert(bytes).toString();
    if (actual.toLowerCase() != expectedSha512.toLowerCase()) {
      throw UserError(
        'checksum mismatch: expected $expectedSha512, got $actual',
      );
    }
  }

  /// Verifies the contents of [file] against [expectedSha512].
  static Future<void> verifyFileSha512(File file, String expectedSha512) async {
    final bytes = await file.readAsBytes();
    verifySha512(Uint8List.fromList(bytes), expectedSha512);
  }
}
