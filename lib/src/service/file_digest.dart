import 'dart:io';

import 'package:crypto/crypto.dart';

import '../cli/exceptions.dart';

/// Hashes a file without retaining its contents in memory.
Future<String> fileDigest(File file, Hash algorithm) async =>
    (await algorithm.bind(file.openRead()).first).toString();

/// Computes digests in algorithm order from a single file stream.
Future<List<String>> fileDigests(File file, List<Hash> algorithms) {
  final stream = file.openRead().asBroadcastStream();
  return Future.wait([
    for (final algorithm in algorithms)
      algorithm.bind(stream).first.then((digest) => digest.toString()),
  ]);
}

Future<void> verifyFileDigest(
  File file,
  Hash algorithm,
  String expected,
) async {
  final actual = await fileDigest(file, algorithm);
  if (actual.toLowerCase() != expected.toLowerCase()) {
    throw UserError('checksum mismatch: expected $expected, got $actual');
  }
}
