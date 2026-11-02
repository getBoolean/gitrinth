import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/file_digest.dart';
import 'package:test/test.dart';

// Only stream reads are available, so a regression to buffering fails directly.
class _StreamOnlyFile implements File {
  final File source;
  _StreamOnlyFile(this.source);

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      source.openRead(start, end);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  test(
    'all cache file hashes stream, accept uppercase, and retain mismatch text',
    () async {
      final dir = Directory.systemTemp.createTempSync('file-digest-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bytes = List.generate(200000, (index) => index % 251);
      final file = _StreamOnlyFile(
        File('${dir.path}/artifact')..writeAsBytesSync(bytes),
      );
      for (final (algorithm, verify) in [
        (sha1, GitrinthCache.verifyFileSha1),
        (sha256, GitrinthCache.verifyFileSha256),
        (sha512, GitrinthCache.verifyFileSha512),
      ]) {
        final expected = algorithm.convert(bytes).toString();
        expect(await fileDigest(file, algorithm), expected);
        await verify(file, expected.toUpperCase());
        await expectLater(
          verify(file, 'INVALID'),
          throwsA(
            isA<UserError>().having(
              (error) => error.message,
              'message',
              'checksum mismatch: expected INVALID, got $expected',
            ),
          ),
        );
      }
    },
  );
}
