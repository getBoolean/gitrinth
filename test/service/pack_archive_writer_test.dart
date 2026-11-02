import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:gitrinth/src/service/pack_archive_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pack-writer-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'encoding failure preserves the destination and removes temporary output',
    () {
      final output = File('${dir.path}/pack.zip')
        ..writeAsStringSync('original');
      final source = File('${dir.path}/source')..writeAsStringSync('contents');
      Iterable<({String path, File source})> entries() sync* {
        yield (path: 'overrides/source', source: source);
        throw StateError('source discovery failed');
      }

      expect(
        () => writeArchive(
          output,
          manifestName: 'manifest.json',
          manifest: utf8.encode('{}'),
          entries: entries(),
        ),
        throwsStateError,
      );
      expect(output.readAsStringSync(), 'original');
      expect(
        dir.listSync().map((file) => p.basename(file.path)),
        unorderedEquals(['pack.zip', 'source']),
      );
    },
  );

  test(
    'streams entries in order with existing compression and mode defaults',
    () {
      final output = File('${dir.path}/pack.zip')
        ..writeAsStringSync('previous');
      final source = File('${dir.path}/source')..writeAsStringSync('contents');
      writeArchive(
        output,
        manifestName: 'manifest.json',
        manifest: utf8.encode('{}'),
        entries: [(path: 'overrides/source', source: source)],
      );
      final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
      expect(archive.map((entry) => entry.name), [
        'manifest.json',
        'overrides/source',
      ]);
      expect(utf8.decode(archive.first.content), '{}');
      expect(utf8.decode(archive.last.content), 'contents');
      expect(archive.map((entry) => entry.mode & 0x1ff), everyElement(0x1a4));
      expect(
        archive.map((entry) => entry.compression),
        everyElement(CompressionType.deflate),
      );
      // ZIP stores local wall time; archive decodes those fields as UTC.
      final now = DateTime.now();
      expect(
        archive.map((entry) => entry.lastModDateTime.millisecondsSinceEpoch),
        everyElement(
          closeTo(now.add(now.timeZoneOffset).millisecondsSinceEpoch, 5000),
        ),
      );
    },
  );

  test('failed destination replacement removes temporary output', () {
    final existing = Directory('${dir.path}/pack.zip')..createSync();
    File('${existing.path}/keep').writeAsStringSync('original');
    expect(
      () => writeArchive(
        File(existing.path),
        manifestName: 'manifest.json',
        manifest: utf8.encode('{}'),
        entries: [],
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('${existing.path}/keep').readAsStringSync(), 'original');
    expect(dir.listSync().map((entry) => p.basename(entry.path)), ['pack.zip']);
  });
}
