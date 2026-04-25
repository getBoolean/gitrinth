import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/symlink_util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ensureDirSymlink', () {
    late Directory tempRoot;
    late Directory targetA;
    late Directory targetB;
    late String linkPath;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_symlink_');
      targetA = Directory(p.join(tempRoot.path, 'a'))..createSync();
      targetB = Directory(p.join(tempRoot.path, 'b'))..createSync();
      linkPath = p.join(tempRoot.path, 'link');
    });

    tearDown(() {
      // Best-effort cleanup; on Windows a stale junction sometimes blocks
      // recursive delete, so unlink it first.
      final link = Link(linkPath);
      if (link.existsSync()) {
        try {
          link.deleteSync();
        } catch (_) {}
      }
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('creates a directory link pointing at the target', () async {
      await ensureDirSymlink(linkPath: linkPath, target: targetA.path);

      final link = Link(linkPath);
      expect(link.existsSync(), isTrue);
      expect(
        p.normalize(p.absolute(link.targetSync())),
        p.normalize(p.absolute(targetA.path)),
      );
      // Files written into the target are visible via the link.
      File(p.join(targetA.path, 'marker.txt')).writeAsStringSync('hi');
      expect(File(p.join(linkPath, 'marker.txt')).existsSync(), isTrue);
    });

    test('is idempotent when the link already points at the target', () async {
      await ensureDirSymlink(linkPath: linkPath, target: targetA.path);
      await ensureDirSymlink(linkPath: linkPath, target: targetA.path);

      final link = Link(linkPath);
      expect(link.existsSync(), isTrue);
      expect(
        p.normalize(p.absolute(link.targetSync())),
        p.normalize(p.absolute(targetA.path)),
      );
    });

    test('replaces the link when the target changes', () async {
      await ensureDirSymlink(linkPath: linkPath, target: targetA.path);
      await ensureDirSymlink(linkPath: linkPath, target: targetB.path);

      final link = Link(linkPath);
      expect(link.existsSync(), isTrue);
      expect(
        p.normalize(p.absolute(link.targetSync())),
        p.normalize(p.absolute(targetB.path)),
      );
    });

    test('refuses to overwrite a real directory at the link path', () async {
      Directory(linkPath).createSync();
      await expectLater(
        ensureDirSymlink(linkPath: linkPath, target: targetA.path),
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            contains('refusing to overwrite'),
          ),
        ),
      );
      // The real directory is intact.
      expect(Directory(linkPath).existsSync(), isTrue);
      expect(Link(linkPath).existsSync(), isFalse);
    });

    test('refuses to overwrite a real file at the link path', () async {
      File(linkPath).writeAsStringSync('not a link');
      await expectLater(
        ensureDirSymlink(linkPath: linkPath, target: targetA.path),
        throwsA(isA<UserError>()),
      );
      expect(File(linkPath).readAsStringSync(), 'not a link');
    });
  });
}
