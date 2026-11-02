import 'dart:io';

import 'package:crypto/crypto.dart';

import '../cli/exceptions.dart';

/// Hashes a file without retaining its contents in memory.
Future<String> fileDigest(File file, Hash algorithm) async =>
    (await algorithm.bind(file.openRead()).first).toString();

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
