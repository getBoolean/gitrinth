import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/capture.dart';
import '../../helpers/fake_modrinth.dart';

void main() {
  late Directory root;
  late FakeModrinth mr;
  late HttpServer cf;
  late Map<int, List<Map<String, dynamic>>> files;
  late Map<String, String> environment;
  final bytes = [1, 2, 3];
  final digest = sha1.convert(bytes).toString();
  setUp(() async {
    root = Directory.systemTemp.createTempSync('cf_relationships_');
    mr = FakeModrinth();
    await mr.start();
    cf = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final host = 'http://127.0.0.1:${cf.port}';
    files = {
      for (final id in [1, 2, 3])
        id: [
          {
            'id': id * 10,
            'modId': id,
            'displayName': '1.0.0',
            'fileName': '$id.jar',
            'releaseType': 1,
            'fileDate': '2026-01-01',
            'gameVersions': ['1.21.1'],
            'hashes': [
              {'value': digest, 'algo': 1},
            ],
            'dependencies': <Map<String, dynamic>>[],
            'downloadUrl': '$host/artifact/$id',
          },
        ],
    };
    cf.listen((request) async {
      final parts = request.uri.pathSegments;
      if (parts.first == 'artifact') {
        request.response.add(bytes);
      } else {
        final id = int.parse(parts[2]);
        final dynamic data = parts.length == 3
            ? {
                'id': id,
                'gameId': 432,
                'classId': 6,
                'slug': 'project-$id',
                'name': 'Project $id',
              }
            : files[id];
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': data,
            if (data is List)
              'pagination': {
                'index': 0,
                'pageSize': 50,
                'resultCount': data.length,
                'totalCount': data.length,
              },
          }),
        );
      }
      await request.response.close();
    });
    environment = {
      'GITRINTH_CACHE': p.join(root.path, 'cache'),
      'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
      'GITRINTH_MODRINTH_URL': mr.baseUrl,
      'GITRINTH_NEOFORGE_VERSIONS_URL': mr.neoforgeVersionsUrl,
      'GITRINTH_CURSEFORGE_URL': host,
      'GITRINTH_CURSEFORGE_TOKEN': 'test-key',
    };
  });
  tearDown(() async {
    await cf.close(force: true);
    await mr.stop();
    root.deleteSync(recursive: true);
  });
  void manifest(String mods, {String overrides = ''}) =>
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'neoforge:21.1.50'}
gitrinth: {modrinth: disabled, curseforge: enabled}
mods:
$mods
$overrides
''');
  Future<CapturedOutput> get({bool offline = false}) => runCli([
    '-C',
    root.path,
    'get',
    '--no-search',
    if (offline) '--offline',
  ], environment: environment);
  File lock() => File(p.join(root.path, 'mods.lock'));
  File metadata(int project, int file) => File(
    p.join(
      root.path,
      'cache',
      'curseforge',
      '$project',
      '$file',
      'metadata.json',
    ),
  );
  void incompatible(int a, int b) => files[a]!.first['dependencies'] = [
    {'modId': b, 'relationType': 5},
  ];

  for (final reversed in [false, true]) {
    test(
      'incompatibility rejects selected aliases before lock replacement, reversed=$reversed',
      () async {
        final entries = [
          '  alpha: {curseforge: "1"}',
          '  beta: {curseforge: "2"}',
        ];
        manifest((reversed ? entries.reversed : entries).join('\n'));
        final first = await get();
        expect(first.exitCode, 0, reason: first.stderr);
        final before = lock().readAsStringSync();
        incompatible(1, 2);
        final result = await get();
        expect(
          result.exitCode,
          2,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          result.stderr,
          allOf(
            contains('alpha'),
            contains('beta'),
            contains('10'),
            contains('20'),
            contains('compatible pin'),
          ),
        );
        expect(lock().readAsStringSync(), before);
      },
    );
  }
  test(
    'required transitive project conflicts with final selected file',
    () async {
      manifest('  alpha: {curseforge: "1"}');
      files[1]!.first['dependencies'] = [
        {'modId': 2, 'relationType': 3},
        {'modId': 2, 'relationType': 5},
      ];
      final result = await get();
      expect(result.exitCode, 2, reason: result.stderr);
      expect(result.stderr, allOf(contains('alpha'), contains('project-2')));
      expect(lock().existsSync(), isFalse);
    },
  );
  test('aliases produce one project conflict diagnostic', () async {
    manifest(
      '  alpha: {curseforge: "1"}\n  alpha-copy: {curseforge: "1"}\n  beta: {curseforge: "2"}',
    );
    incompatible(1, 2);
    final result = await get();
    expect(result.exitCode, 2, reason: result.stderr);
    expect(result.stderr, contains('alpha-copy'));
    expect('incompatible with'.allMatches(result.stderr), hasLength(1));
  });
  for (final overridden in ['alpha', 'beta']) {
    test(
      'project override bypasses either incompatibility endpoint $overridden',
      () async {
        manifest(
          '  alpha: {curseforge: "1"}\n  beta: {curseforge: "2"}',
          overrides: 'project_overrides:\n  $overridden: 1.0.0',
        );
        incompatible(1, 2);
        final result = await get();
        expect(result.exitCode, 0, reason: result.stderr);
      },
    );
  }
  test(
    'selected metadata persists raw relations and offline rejects conflicts',
    () async {
      manifest('  alpha: {curseforge: "1"}\n  beta: {curseforge: "2"}');
      final ignored = [
        for (final code in [1, 2, 4, 6, 99]) {'modId': 3, 'relationType': code},
      ];
      files[1]!.first['dependencies'] = ignored;
      final result = await get();
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        parseModsLock(
          lock().readAsStringSync(),
          filePath: lock().path,
        ).mods.keys,
        unorderedEquals(['alpha', 'beta']),
      );
      final saved =
          jsonDecode(metadata(1, 10).readAsStringSync())
              as Map<String, dynamic>;
      expect(saved['schemaVersion'], 1);
      expect(saved['projectId'], 1);
      expect(saved['fileId'], 10);
      expect(saved['file']['dependencies'], ignored);
      saved['file']['dependencies'] = [
        {'modId': 2, 'relationType': 5},
      ];
      metadata(1, 10).writeAsStringSync(jsonEncode(saved));
      final before = lock().readAsStringSync();
      final offline = await get(offline: true);
      expect(offline.exitCode, 2, reason: offline.stderr);
      expect(offline.stderr, contains('incompatible with'));
      expect(lock().readAsStringSync(), before);
    },
  );
  for (final problem in [
    'missing',
    'corrupt',
    'identity',
    'unavailable',
    'changed-hash',
    'missing-hash',
  ]) {
    test('offline $problem metadata fails before lock writes', () async {
      manifest('  alpha: {curseforge: "1"}');
      final first = await get();
      expect(first.exitCode, 0, reason: first.stderr);
      final before = lock().readAsStringSync();
      final sidecar = metadata(1, 10);
      if (problem == 'missing') {
        if (sidecar.existsSync()) sidecar.deleteSync();
      } else if (problem == 'corrupt') {
        sidecar.writeAsStringSync('{');
      } else {
        final saved =
            jsonDecode(sidecar.readAsStringSync()) as Map<String, dynamic>;
        if (problem == 'identity') saved['projectId'] = 999;
        if (problem == 'unavailable') saved['file']['isAvailable'] = false;
        if (problem == 'changed-hash') {
          saved['file']['hashes'] = [
            {'algo': 1, 'value': 'different-sha1'},
          ];
        }
        if (problem == 'missing-hash') saved['file']['hashes'] = [];
        sidecar.writeAsStringSync(jsonEncode(saved));
      }
      final result = await get(offline: true);
      expect(result.exitCode, 2, reason: result.stderr);
      expect(result.stderr, contains('online'));
      expect(lock().readAsStringSync(), before);
    });
  }
  test('metadata write failure preserves previous lock', () async {
    manifest('  alpha: {curseforge: "1"}');
    final first = await get();
    expect(first.exitCode, 0, reason: first.stderr);
    final before = lock().readAsStringSync();
    files[1]!.first['id'] = 11;
    final obstruction = File(
      p.join(root.path, 'cache', 'curseforge', '1', '11'),
    );
    obstruction.parent.createSync(recursive: true);
    obstruction.writeAsStringSync('blocks metadata directory');
    final result = await get();
    expect(result.exitCode, 2, reason: result.stderr);
    expect(result.stderr, contains('metadata'));
    expect(lock().readAsStringSync(), before);
  });

  test('artifact cannot replace its selected metadata sidecar', () async {
    manifest('  alpha: {curseforge: "1"}');
    final first = await get();
    expect(first.exitCode, 0, reason: first.stderr);
    final before = lock().readAsStringSync();
    files[1]!.first['fileName'] = 'metadata.json';
    final result = await get();
    expect(result.exitCode, 2, reason: result.stderr);
    expect(result.stderr, contains('metadata.json'));
    expect(lock().readAsStringSync(), before);
  });

  test('artifact cannot occupy the metadata writer lock path', () async {
    manifest('  alpha: {curseforge: "1"}');
    final first = await get();
    expect(first.exitCode, 0, reason: first.stderr);
    final before = lock().readAsStringSync();
    files[1]!.first['fileName'] = 'metadata.json.lock';
    final result = await get();
    expect(result.exitCode, 2, reason: result.stderr);
    expect(lock().readAsStringSync(), before);
  });
  for (final selectedConflicts in [false, true]) {
    test(
      'hash-selected older file owns final relations, conflicts=$selectedConflicts',
      () async {
        final hosted = FakeModrinth();
        await hosted.start();
        addTearDown(hosted.stop);
        hosted.registerVersion(slug: 'alpha', versionNumber: '1.0.0');
        hosted.artifacts['alpha/alpha-1.0.0.jar'] = Uint8List.fromList(bytes);
        final mrFile =
            (hosted.versions['alpha']!.single['files'] as List).single
                as Map<String, dynamic>;
        (mrFile['hashes'] as Map)['sha1'] = digest;
        (mrFile['hashes'] as Map)['sha512'] = sha512.convert(bytes).toString();
        manifest(
          '  alpha: {curseforge: "1", modrinth_host: "${hosted.baseUrl}", sources: [modrinth, curseforge]}\n  beta: {curseforge: "2"}',
        );
        final older = {...files[1]!.first, 'id': 9, 'fileDate': '2025-01-01'};
        files[1]!.first['hashes'] = [
          {
            'value': sha1.convert([9]).toString(),
            'algo': 1,
          },
        ];
        final conflict = [
          {'modId': 2, 'relationType': 5},
        ];
        files[1]!.first['dependencies'] = selectedConflicts ? [] : conflict;
        older['dependencies'] = selectedConflicts ? conflict : [];
        files[1]!.add(older);
        final result = await get();
        expect(
          result.exitCode,
          selectedConflicts ? 2 : 0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        if (selectedConflicts) {
          expect(
            result.stderr,
            allOf(contains('files 9'), contains('incompatible with')),
          );
          expect(lock().existsSync(), isFalse);
        } else {
          final saved =
              jsonDecode(metadata(1, 9).readAsStringSync())
                  as Map<String, dynamic>;
          expect(saved['file']['dependencies'], isEmpty);
          expect(metadata(1, 10).existsSync(), isFalse);
          final beforePack = lock().readAsStringSync();
          final selected = parseModsLock(
            beforePack,
            filePath: lock().path,
          ).mods['alpha']!;
          expect(selected.modrinth!.host, hosted.baseUrl);
          expect(selected.curseforge!.fileId, 9);
          final requestsBeforePack = Map.of(hosted.requestCounts);
          final packed = await runCli([
            '-C',
            root.path,
            'pack',
            '--curseforge',
            '--offline',
          ], environment: environment);
          expect(
            packed.exitCode,
            0,
            reason: '${packed.stdout}\n${packed.stderr}',
          );
          final archive = ZipDecoder().decodeBytes(
            File(
              p.join(root.path, 'build', 'pack-1.0.0.zip'),
            ).readAsBytesSync(),
          );
          final packedManifest = jsonDecode(
            utf8.decode(archive.findFile('manifest.json')!.content),
          );
          expect(
            packedManifest['files'],
            contains(equals({'projectID': 1, 'fileID': 9, 'required': true})),
          );
          expect(lock().readAsStringSync(), beforePack);
          expect(hosted.requestCounts, requestsBeforePack);
        }
      },
    );
  }
}
