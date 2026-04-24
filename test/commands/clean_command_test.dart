import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';

void main() {
  late Directory tempRoot;
  late Directory packDir;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_clean_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  void writeFile(String relativePath, String contents) {
    final file = File(p.join(packDir.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  test('removes mods.lock when present', () async {
    writeFile('mods.lock', 'gitrinth-version: 0.1.0\n');

    final out = await runCli(['-C', packDir.path, 'clean']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isFalse);
    expect(out.stdout, contains('removed:'));
    expect(out.stdout, contains('mods.lock'));
  });

  test('removes the build directory tree when present', () async {
    writeFile(p.join('build', 'client', 'mods', 'example.jar'), 'jar-bytes');
    writeFile(p.join('build', 'server', 'mods', 'other.jar'), 'jar-bytes');

    final out = await runCli(['-C', packDir.path, 'clean']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(Directory(p.join(packDir.path, 'build')).existsSync(), isFalse);
    expect(out.stdout, contains('build'));
  });

  test('--output removes a custom directory instead of ./build', () async {
    writeFile(p.join('dist', 'client', 'mods', 'example.jar'), 'jar-bytes');
    // A ./build also exists and must be left alone.
    writeFile(p.join('build', 'stale.txt'), 'should survive');

    final out = await runCli([
      '-C',
      packDir.path,
      'clean',
      '--output',
      'dist',
    ]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(Directory(p.join(packDir.path, 'dist')).existsSync(), isFalse);
    expect(
      File(p.join(packDir.path, 'build', 'stale.txt')).existsSync(),
      isTrue,
      reason: '--output must not touch the default ./build path',
    );
  });

  test('prints "Nothing to clean." when both targets are absent', () async {
    final out = await runCli(['-C', packDir.path, 'clean']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('Nothing to clean.'));
  });

  test('unexpected positional arg exits 64 with UsageError', () async {
    final out = await runCli(['-C', packDir.path, 'clean', 'nope']);
    expect(out.exitCode, 64);
    expect(out.stderr, contains('Unexpected arguments'));
  });

  test('does not delete mods.yaml or mods_overrides.yaml', () async {
    writeFile('mods.yaml', 'slug: pack\n');
    writeFile('mods_overrides.yaml', 'overrides:\n');
    writeFile('mods.lock', 'gitrinth-version: 0.1.0\n');

    final out = await runCli(['-C', packDir.path, 'clean']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(File(p.join(packDir.path, 'mods.yaml')).existsSync(), isTrue);
    expect(
      File(p.join(packDir.path, 'mods_overrides.yaml')).existsSync(),
      isTrue,
    );
    expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isFalse);
  });

  test(
    'resolves targets relative to -C directory, not the CLI caller cwd',
    () async {
      // Lock + build under packDir; the caller CWD (tempRoot) must not be
      // scanned for matching names.
      writeFile('mods.lock', 'gitrinth-version: 0.1.0\n');
      writeFile(p.join('build', 'marker.txt'), 'x');
      final unrelatedLock = File(p.join(tempRoot.path, 'mods.lock'))
        ..writeAsStringSync('unrelated');

      final out = await runCli(['-C', packDir.path, 'clean']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(File(p.join(packDir.path, 'mods.lock')).existsSync(), isFalse);
      expect(
        unrelatedLock.existsSync(),
        isTrue,
        reason:
            'clean must resolve paths under the -C directory; the sibling '
            'mods.lock at tempRoot must be untouched.',
      );
    },
  );
}
