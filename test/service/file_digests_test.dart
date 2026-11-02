import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/service/file_digest.dart';
import 'package:test/test.dart';

class _SingleReadFile implements File {
  final List<int> bytes;
  var reads = 0;
  _SingleReadFile(this.bytes);

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    if (++reads > 1) throw StateError('File was read twice');
    return Stream.fromIterable([bytes.sublist(0, 100), bytes.sublist(100)]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  test(
    'multiple digests preserve algorithm order with one stream read',
    () async {
      final bytes = List.generate(200000, (index) => index % 251);
      final file = _SingleReadFile(bytes);
      expect(await fileDigests(file, [sha1, sha512]), [
        sha1.convert(bytes).toString(),
        sha512.convert(bytes).toString(),
      ]);
      expect(file.reads, 1);
    },
  );
}
