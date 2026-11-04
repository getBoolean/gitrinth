import 'dart:io';

import 'package:gitrinth/src/service/cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late GitrinthCache cache;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_cf_cache_');
    cache = GitrinthCache(root: tempRoot.path);
    cache.ensureRoot();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('curseforgeRoot is `<root>/curseforge`', () {
    expect(cache.curseforgeRoot, p.join(tempRoot.path, 'curseforge'));
  });

  test('curseforgePath uses curseforge/<projectId>/<fileId>/<filename>', () {
    final path = cache.curseforgePath(
      projectId: 238222,
      fileId: 4567,
      filename: 'jei-1.0.0.jar',
    );
    expect(
      path,
      p.join(tempRoot.path, 'curseforge', '238222', '4567', 'jei-1.0.0.jar'),
    );
  });

  test('curseforge cache layout is disjoint from modrinth layout', () {
    const host = 'https://api.modrinth.com/v2';
    final mPath = cache.modrinthPath(
      host: host,
      projectId: 'P1',
      versionId: 'V1',
      filename: 'a.jar',
    );
    final cfPath = cache.curseforgePath(
      projectId: 1,
      fileId: 2,
      filename: 'a.jar',
    );
    expect(p.split(mPath), contains('modrinth'));
    expect(p.split(cfPath), contains('curseforge'));
    expect(
      p.split(cfPath).any((s) => s == 'modrinth'),
      isFalse,
      reason: 'curseforge layout must not include the modrinth segment',
    );
  });
}
