import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late GitrinthCache cache;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_cache_');
    cache = GitrinthCache(root: tempRoot.path);
    cache.ensureRoot();
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('layout uses modrinth/<projectId>/<versionId>/<filename>', () {
    final path = cache.modrinthPath(
      projectId: 'P1',
      versionId: 'V1',
      filename: 'a.jar',
    );
    expect(path, p.join(tempRoot.path, 'modrinth', 'P1', 'V1', 'a.jar'));
  });

  test('verifySha512 accepts a matching hash and rejects a wrong one', () {
    final bytes = [1, 2, 3, 4];
    final hex = sha512.convert(bytes).toString();
    expect(() => GitrinthCache.verifySha512(bytes, hex), returnsNormally);
    expect(
      () => GitrinthCache.verifySha512(bytes, '0' * 128),
      throwsA(isA<UserError>()),
    );
  });

  test('verifySha512 is case-insensitive', () {
    final bytes = [9, 8, 7];
    final hex = sha512.convert(bytes).toString();
    expect(
      () => GitrinthCache.verifySha512(bytes, hex.toUpperCase()),
      returnsNormally,
    );
  });
}
