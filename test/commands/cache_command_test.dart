import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';

void main() {
  late Directory tempRoot;
  late Directory cacheRoot;
  late Map<String, String> env;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_cache_');
    cacheRoot = Directory(p.join(tempRoot.path, 'cache'));
    env = {
      ...Platform.environment,
      'GITRINTH_CACHE': cacheRoot.path,
    };
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  String sha512Hex(List<int> bytes) => sha512.convert(bytes).toString();

  void seedModrinthArtifact({
    required String projectId,
    required String versionId,
    required String filename,
    required String body,
    String? url,
  }) {
    final dir = Directory(p.join(cacheRoot.path, 'modrinth', projectId, versionId));
    dir.createSync(recursive: true);
    final jarBytes = utf8.encode(body);
    File(p.join(dir.path, filename)).writeAsBytesSync(jarBytes);
    final version = <String, Object?>{
      'id': versionId,
      'project_id': projectId,
      'version_number': '1.0.0',
      'files': [
        {
          'url': url ?? 'https://example.invalid/$filename',
          'filename': filename,
          'hashes': {
            'sha1': '0' * 40,
            'sha512': sha512Hex(jarBytes),
          },
          'size': jarBytes.length,
          'primary': true,
        },
      ],
      'dependencies': <Object?>[],
      'loaders': <String>['fabric'],
      'game_versions': <String>['1.21.1'],
    };
    File(p.join(dir.path, 'version.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(version),
    );
  }

  /// Seeds an url-cached file. The directory name encodes the *expected*
  /// sha512; the file body's *actual* sha512 may match or mismatch.
  void seedUrlArtifact({
    required String expectedSha512,
    required String filename,
    required String body,
  }) {
    final dir = Directory(p.join(
      cacheRoot.path,
      'url',
      expectedSha512.substring(0, 2),
      expectedSha512,
    ));
    dir.createSync(recursive: true);
    File(p.join(dir.path, filename)).writeAsBytesSync(utf8.encode(body));
  }

  test('cache list on missing cache root prints empty JSON', () async {
    final out = await runCli(['cache', 'list'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final body = jsonDecode(out.stdout) as Map<String, dynamic>;
    expect(body['root'], cacheRoot.path);
    expect(body['artifacts'], isEmpty);
  });

  test('cache list emits parseable JSON with seeded modrinth + url artifacts',
      () async {
    seedModrinthArtifact(
      projectId: 'PROJ1',
      versionId: 'VER1',
      filename: 'mod-a.jar',
      body: 'modrinth-payload',
    );
    final urlBody = 'url-payload';
    final urlSha = sha512Hex(utf8.encode(urlBody));
    seedUrlArtifact(
      expectedSha512: urlSha,
      filename: 'mod-b.jar',
      body: urlBody,
    );

    final out = await runCli(['cache', 'list'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final body = jsonDecode(out.stdout) as Map<String, dynamic>;
    final artifacts =
        (body['artifacts'] as List).cast<Map<String, dynamic>>();
    expect(artifacts, hasLength(2));

    final modrinth = artifacts.firstWhere((a) => a['source'] == 'modrinth');
    expect(modrinth['projectId'], 'PROJ1');
    expect(modrinth['versionId'], 'VER1');
    expect(modrinth['filename'], 'mod-a.jar');
    expect(modrinth['size'], utf8.encode('modrinth-payload').length);

    final url = artifacts.firstWhere((a) => a['source'] == 'url');
    expect(url['filename'], 'mod-b.jar');
    expect(url['sha512'], urlSha);

    // version.json must NOT show up as a standalone artifact.
    expect(
      artifacts.where((a) => a['filename'] == 'version.json'),
      isEmpty,
    );
  });

  test('cache clean --force wipes content but preserves the root dir', () async {
    seedModrinthArtifact(
      projectId: 'PROJ1',
      versionId: 'VER1',
      filename: 'mod.jar',
      body: 'payload',
    );
    expect(cacheRoot.existsSync(), isTrue);

    final out = await runCli(['cache', 'clean', '--force'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(cacheRoot.existsSync(), isTrue,
        reason: 'cache clean must preserve the root directory itself');
    expect(
      Directory(p.join(cacheRoot.path, 'modrinth')).existsSync(),
      isFalse,
    );
  });

  test('cache clean without --force on non-tty stdin exits 64', () async {
    seedModrinthArtifact(
      projectId: 'PROJ1',
      versionId: 'VER1',
      filename: 'mod.jar',
      body: 'payload',
    );

    final out = await runCli(['cache', 'clean'], environment: env);
    expect(out.exitCode, 64);
    expect(out.stderr, contains('--force'));
    expect(
      File(p.join(cacheRoot.path, 'modrinth', 'PROJ1', 'VER1', 'mod.jar'))
          .existsSync(),
      isTrue,
      reason: 'a refused clean must not delete anything',
    );
  });

  test('cache clean on missing cache root exits 0', () async {
    final out = await runCli(['cache', 'clean', '--force'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('already empty'));
  });

  test('cache repair on a healthy seeded cache exits 0', () async {
    seedModrinthArtifact(
      projectId: 'PROJ1',
      versionId: 'VER1',
      filename: 'mod-a.jar',
      body: 'modrinth-payload',
    );
    final urlBody = 'url-payload';
    seedUrlArtifact(
      expectedSha512: sha512Hex(utf8.encode(urlBody)),
      filename: 'mod-b.jar',
      body: urlBody,
    );

    final out = await runCli(['cache', 'repair'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('2 verified'));
  });

  test('cache repair on a tampered url-cached file deletes it, exits 0',
      () async {
    final expected = sha512Hex(utf8.encode('valid content'));
    seedUrlArtifact(
      expectedSha512: expected,
      filename: 'mod.jar',
      body: 'TAMPERED',
    );
    final filePath = p.join(
      cacheRoot.path,
      'url',
      expected.substring(0, 2),
      expected,
      'mod.jar',
    );
    expect(File(filePath).existsSync(), isTrue);

    final out = await runCli(['cache', 'repair'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(File(filePath).existsSync(), isFalse,
        reason: 'corrupt url-cached files should be deleted');
    // The empty <prefix>/<sha512>/ directories should be pruned too.
    expect(
      Directory(p.join(cacheRoot.path, 'url', expected.substring(0, 2)))
          .existsSync(),
      isFalse,
    );
  });

  test('cache repair on modrinth jar with missing version.json warns and skips',
      () async {
    final dir = Directory(p.join(cacheRoot.path, 'modrinth', 'X', 'Y'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'orphan.jar')).writeAsStringSync('garbage');
    // No version.json sibling.

    final out = await runCli(['cache', 'repair'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stderr, contains('no version.json sibling'));
    expect(
      File(p.join(dir.path, 'orphan.jar')).existsSync(),
      isTrue,
      reason: 'skipped orphans must not be deleted',
    );
  });

  test('cache repair on empty cache exits 0', () async {
    final out = await runCli(['cache', 'repair'], environment: env);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
  });

  test('unknown cache subcommand exits 64', () async {
    final out = await runCli(['cache', 'bogus'], environment: env);
    expect(out.exitCode, 64);
  });

  test('cache list rejects positional args with exit 64', () async {
    final out = await runCli(['cache', 'list', 'extra'], environment: env);
    expect(out.exitCode, 64);
  });
}
