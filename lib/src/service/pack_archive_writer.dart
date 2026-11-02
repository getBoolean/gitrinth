import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';

/// Writes manifest bytes followed by the supplied files, in iteration order.
void writeArchive(
  File output, {
  required String manifestName,
  required List<int> manifest,
  required Iterable<({String path, File source})> entries,
}) {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final temporary = File('${output.path}.tmp-$suffix');
  OutputFileStream? stream;
  try {
    stream = OutputFileStream(temporary.path);
    final encoder = ZipEncoder()..startEncode(stream);
    encoder.add(ArchiveFile(manifestName, manifest.length, manifest));
    for (final entry in entries) {
      final input = InputFileStream(entry.source.path);
      try {
        encoder.add(ArchiveFile.stream(entry.path, input), autoClose: false);
      } finally {
        input.closeSync();
      }
    }
    encoder.endEncode();
    stream.closeSync();
    stream = null;
    temporary.renameSync(output.path);
  } finally {
    try {
      stream?.closeSync();
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}
