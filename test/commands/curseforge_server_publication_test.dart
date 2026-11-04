import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/multipart.dart';

void main() {
  List<int> clientArchive({
    String version = '1.0.0',
    bool changed = false,
    String? loader = 'fabric-0.16.0',
  }) {
    final manifest = utf8.encode(
      jsonEncode({
        'manifestType': 'minecraftModpack',
        'manifestVersion': 1,
        'name': 'Test',
        'version': version,
        'minecraft': {
          'version': '1.21.1',
          'modLoaders': [
            if (loader != null) {'id': loader, 'primary': true},
          ],
        },
        'files': [],
        'overrides': 'overrides',
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    if (changed) {
      archive.addFile(ArchiveFile('overrides/config/options.txt', 1, [9]));
    }
    return ZipEncoder().encode(archive);
  }

  late Directory root;
  late HttpServer server;
  late String host;
  late List<Map<String, dynamic>> uploads;
  late List<ReceivedPart> uploadedFiles;
  late List<String> paths;
  late bool rejectChild;
  late bool rejectParent;
  late bool invalidClientId;
  late bool classified;
  late bool rejectPeer;
  late bool unknownPeer;
  late int parentProject;
  late String parentRelease;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('cf_server_publish_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    host = 'http://127.0.0.1:${server.port}';
    uploads = [];
    uploadedFiles = [];
    paths = [];
    rejectChild = false;
    rejectParent = false;
    invalidClientId = false;
    classified = false;
    rejectPeer = false;
    unknownPeer = false;
    parentProject = 42;
    parentRelease = 'Test 1.0.0';
    File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: test
name: Test
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'fabric:0.16.0'}
publish_to: curseforge
''');
    final build = Directory(p.join(root.path, 'build'))..createSync();
    File(
      p.join(build.path, 'test-1.0.0.zip'),
    ).writeAsBytesSync(clientArchive());
    final content = utf8.encode('actual server bytes');
    final marker = {
      'formatVersion': 1,
      'artifactType': 'gitrinth-server-distribution',
      'slug': 'test',
      'version': '1.0.0',
      'minecraft': '1.21.1',
      'loader': {'id': 'fabric', 'version': '0.16.0'},
      'runtimeBundled': false,
      'files': [
        {
          'path': 'mods/server.jar',
          'sha256': sha256.convert(content).toString(),
        },
      ],
    };
    final markerBytes = utf8.encode(jsonEncode(marker));
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'gitrinth-server-distribution.json',
          markerBytes.length,
          markerBytes,
        ),
      )
      ..addFile(ArchiveFile('mods/server.jar', content.length, content));
    File(
      p.join(build.path, 'test-1.0.0-server-distribution.zip'),
    ).writeAsBytesSync(ZipEncoder().encode(archive));
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST') {
        if (request.uri.path == '/project/test/version') {
          expect(request.headers.value('Authorization'), 'private-mr-token');
          await request.drain<void>();
          if (rejectPeer) request.response.statusCode = 401;
          request.response.write(unknownPeer ? '{}' : '{"id":"mr-version"}');
          await request.response.close();
          return;
        }
        expect(request.headers.value('X-Api-Token'), 'private-upload-token');
        final parts = await readMultipart(request);
        expect(parts.keys, unorderedEquals(['metadata', 'file']));
        final metadata = parts['metadata']!.json;
        uploads.add(metadata);
        uploadedFiles.add(parts['file']!);
        final child = metadata.containsKey('parentFileID');
        if ((child && rejectChild) || (!child && rejectParent)) {
          request.response.statusCode = 400;
          request.response.write('{"error":"rejected"}');
        } else {
          request.response.write(
            jsonEncode({'id': child ? 200 : (invalidClientId ? 0 : 100)}),
          );
        }
      } else if (request.uri.path.endsWith('/100')) {
        request.response.write(
          jsonEncode({
            'data': {
              'id': 100,
              'modId': parentProject,
              'displayName': parentRelease,
              'releaseType': 1,
              'isServerPack': false,
              'serverPackFileId': classified ? 200 : null,
            },
          }),
        );
      } else if (request.uri.path.endsWith('/200')) {
        request.response.write(
          jsonEncode({
            'data': {
              'id': 200,
              'modId': 42,
              'isServerPack': classified,
              'parentProjectFileId': 100,
            },
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'data': [],
            'pagination': {
              'index': 0,
              'pageSize': 50,
              'resultCount': 0,
              'totalCount': 0,
            },
          }),
        );
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });
  Future<CapturedOutput> publish(List<String> args, {bool forced = false}) =>
      runCli(
        [
          '-C',
          root.path,
          if (forced) 'curseforge',
          'publish',
          '--force',
          '--curseforge-project',
          '42',
          ...args,
        ],
        environment: {
          'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
          'GITRINTH_TOKEN': 'private-mr-token',
          'GITRINTH_MODRINTH_URL': host,
          'GITRINTH_CURSEFORGE_UPLOAD_TOKEN': 'private-upload-token',
          'GITRINTH_CURSEFORGE_TOKEN': 'private-read-token',
          'GITRINTH_CURSEFORGE_UPLOAD_URL': host,
          'GITRINTH_CURSEFORGE_URL': host,
        },
      );
  List<File> receipts() {
    final dir = Directory(
      p.join(root.path, '.gitrinth', 'publications', 'curseforge', '42'),
    );
    return dir.existsSync()
        ? dir
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.json'))
              .toList()
        : [];
  }

  test(
    'uploads parent then child and reports manual classification pending',
    () async {
      final result = await publish(['--with-server', '--draft']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(uploads, hasLength(2));
      expect(uploads.first.containsKey('parentFileID'), isFalse);
      expect(uploads.last['parentFileID'], 100);
      expect(uploads.last.containsKey('gameVersions'), isFalse);
      expect(uploads.last.containsKey('gameVersionNames'), isFalse);
      expect(uploads.last['isMarkedForManualRelease'], isTrue);
      final build = p.join(root.path, 'build');
      final client = File(p.join(build, 'test-1.0.0.zip'));
      final server = File(p.join(build, 'test-1.0.0-server-distribution.zip'));
      expect(uploadedFiles, hasLength(2));
      final (parentFile, childFile) = (uploadedFiles.first, uploadedFiles.last);
      for (final (part, artifact) in [
        (parentFile, client),
        (childFile, server),
      ]) {
        expect(part.filename, p.basename(artifact.path));
        expect(part.contentType, 'application/zip');
        expect(part.bytes, artifact.readAsBytesSync());
      }
      expect(parentFile.zipEntries.keys, contains('manifest.json'));
      expect(
        parentFile.zipEntries.keys,
        isNot(contains('gitrinth-server-distribution.json')),
      );
      expect(
        childFile.zipEntries.keys,
        containsAll(['gitrinth-server-distribution.json', 'mods/server.jar']),
      );
      expect(
        utf8.decode(childFile.zipEntries['mods/server.jar']!),
        'actual server bytes',
      );
      expect(
        result.stdout,
        allOf(
          contains('100'),
          contains('200'),
          contains('pending'),
          contains('author'),
        ),
      );
      final receipt = receipts().single.readAsStringSync();
      expect(receipt, isNot(contains('private-upload-token')));
      expect(receipt, isNot(contains('private-read-token')));
    },
  );
  test(
    'server-only retry reuses verified parent after a definite child rejection',
    () async {
      rejectChild = true;
      final failed = await publish(['--with-server']);
      expect(failed.exitCode, isNot(0));
      expect(
        failed.stderr,
        allOf(
          contains('100'),
          contains('--server-only'),
          contains('--curseforge-parent-file 100'),
        ),
      );
      rejectChild = false;
      final retried = await publish([
        '--server-only',
        '--curseforge-parent-file',
        '100',
      ]);
      expect(
        retried.exitCode,
        0,
        reason: '${retried.stdout}\n${retried.stderr}',
      );
      expect(uploads, hasLength(3));
      expect(
        uploads.where((m) => !m.containsKey('parentFileID')),
        hasLength(1),
      );
    },
  );
  test('missing server artifact fails before parent upload', () async {
    File(
      p.join(root.path, 'build', 'test-1.0.0-server-distribution.zip'),
    ).deleteSync();
    final result = await publish(['--with-server']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('test-1.0.0-server-distribution.zip'));
    expect(uploads, isEmpty);
  });
  test(
    'invalid successful parent response is unknown and never retried automatically',
    () async {
      invalidClientId = true;
      final first = await publish(['--with-server']);
      expect(first.exitCode, isNot(0));
      expect(uploads, hasLength(1));
      final second = await publish(['--with-server']);
      expect(second.exitCode, isNot(0));
      expect(second.stderr, contains('unknown'));
      expect(uploads, hasLength(1));
    },
  );
  for (final wrong in ['project', 'release']) {
    test(
      'rejects existing parent from wrong $wrong before child upload',
      () async {
        if (wrong == 'project') parentProject = 99;
        if (wrong == 'release') parentRelease = 'Test 2.0.0';
        final result = await publish([
          '--server-only',
          '--curseforge-parent-file',
          '100',
        ]);
        expect(result.exitCode, isNot(0));
        expect(
          result.stderr,
          allOf(startsWith('error:'), contains('parent'), contains(wrong)),
        );
        expect(uploads, isEmpty);
      },
    );
  }
  test(
    'dry run shows dependent steps without receipts or remote writes',
    () async {
      final result = await publish(['--with-server', '--dry-run']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.stdout,
        allOf(contains('client'), contains('server'), contains('parentFileID')),
      );
      expect(uploads, isEmpty);
      expect(receipts(), isEmpty);
    },
  );
  test(
    'confirmed server relation is distinct from generic association',
    () async {
      classified = true;
      final result = await publish(['--with-server']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('confirmed'));
      expect(result.stdout, isNot(contains('pending')));
      final repeated = await publish(['--with-server']);
      expect(repeated.exitCode, 0, reason: repeated.stderr);
      expect(uploads, hasLength(2));
    },
  );
  test(
    'changed artifact cannot reuse a completed publication receipt',
    () async {
      expect((await publish(['--with-server'])).exitCode, 0);
      File(
        p.join(root.path, 'build', 'test-1.0.0.zip'),
      ).writeAsBytesSync(clientArchive(changed: true));
      final result = await publish(['--with-server']);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('changed'));
      expect(uploads, hasLength(2));
    },
  );
  test(
    'failed parent prevents child and records a retryable definite rejection',
    () async {
      rejectParent = true;
      final result = await publish(['--with-server']);
      expect(result.exitCode, isNot(0));
      expect(uploads, hasLength(1));
      expect(uploads.single.containsKey('parentFileID'), isFalse);
      final receipt = jsonDecode(receipts().single.readAsStringSync());
      expect(receipt['client']['state'], 'failed');
      expect(receipt['server']['state'], 'pending');
    },
  );
  test(
    'both-platform retry reuses completed Modrinth and client steps',
    () async {
      final yaml = File(p.join(root.path, 'mods.yaml'));
      yaml.writeAsStringSync(
        yaml.readAsStringSync().replaceFirst(
          'publish_to: curseforge',
          'publish_to: [modrinth, curseforge]',
        ),
      );
      File(
        p.join(root.path, 'build', 'test-1.0.0.mrpack'),
      ).writeAsBytesSync([4]);
      rejectChild = true;
      final first = await publish(['--with-server']);
      expect(first.exitCode, isNot(0));
      expect(first.stderr, contains('Modrinth version mr-version'));
      rejectChild = false;
      final second = await publish(['--with-server']);
      expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');
      expect(
        paths.where((path) => path == '/project/test/version'),
        hasLength(1),
      );
      expect(
        uploads.where((metadata) => !metadata.containsKey('parentFileID')),
        hasLength(1),
      );
      final serverOnly = await publish([
        '--server-only',
        '--curseforge-parent-file',
        '100',
      ]);
      expect(serverOnly.exitCode, 64);
      final forced = await publish([
        '--server-only',
        '--curseforge-parent-file',
        '100',
      ], forced: true);
      expect(forced.exitCode, 0, reason: forced.stderr);
      expect(
        paths.where((path) => path == '/project/test/version'),
        hasLength(1),
      );
    },
  );
  for (final unknown in [false, true]) {
    test(
      'CurseForge-first survives peer failure (unknown: $unknown)',
      () async {
        final yaml = File(p.join(root.path, 'mods.yaml'));
        yaml.writeAsStringSync(
          yaml.readAsStringSync().replaceFirst(
            'publish_to: curseforge',
            'publish_to: [curseforge, modrinth]',
          ),
        );
        File(
          p.join(root.path, 'build', 'test-1.0.0.mrpack'),
        ).writeAsBytesSync([4]);
        rejectPeer = !unknown;
        unknownPeer = unknown;
        final first = await publish(['--with-server']);
        expect(first.exitCode, isNot(0));
        expect(first.stdout, contains('client file 100'));
        final receipt = jsonDecode(receipts().single.readAsStringSync());
        expect(receipt['client']['id'], '100');
        expect(receipt['server']['id'], '200');
        rejectPeer = false;
        unknownPeer = false;
        final second = await publish(['--with-server']);
        expect(second.exitCode, unknown ? isNot(0) : 0, reason: second.stderr);
        expect(uploads, hasLength(2));
        expect(
          paths.where((path) => path == '/project/test/version'),
          hasLength(unknown ? 1 : 2),
        );
      },
    );
  }
  for (final change in ['tampered', 'unlisted', 'missing']) {
    test('server inventory rejects $change payload before any POST', () async {
      final file = File(
        p.join(root.path, 'build', 'test-1.0.0-server-distribution.zip'),
      );
      final old = ZipDecoder().decodeBytes(file.readAsBytesSync());
      final marker = old.findFile('gitrinth-server-distribution.json');
      final payload = old.findFile('mods/server.jar');
      if (marker == null || payload == null) {
        throw StateError('missing fixture');
      }
      final archive = Archive()
        ..addFile(
          ArchiveFile(marker.name, marker.content.length, marker.content),
        );
      if (change != 'missing') {
        final bytes = change == 'tampered'
            ? utf8.encode('changed bytes')
            : payload.content;
        archive.addFile(ArchiveFile(payload.name, bytes.length, bytes));
      }
      if (change == 'unlisted') {
        archive.addFile(ArchiveFile('mods/extra.jar', 1, [1]));
      }
      file.writeAsBytesSync(ZipEncoder().encode(archive));
      final result = await publish(['--with-server']);
      expect(result.exitCode, 2, reason: result.stderr);
      expect(result.stderr, contains('inventory'));
      expect(uploads, isEmpty);
    });
  }
  test(
    'in-flight parent requires an explicit verified ID instead of another POST',
    () async {
      invalidClientId = true;
      expect((await publish(['--with-server'])).exitCode, isNot(0));
      final file = receipts().single;
      final receipt = jsonDecode(file.readAsStringSync());
      receipt['client']['state'] = 'inFlight';
      file.writeAsStringSync(jsonEncode(receipt));
      invalidClientId = false;
      final resumed = await publish([
        '--server-only',
        '--curseforge-parent-file',
        '100',
      ]);
      expect(resumed.exitCode, 0, reason: resumed.stderr);
      expect(uploads, hasLength(2));
      expect(uploads.last['parentFileID'], 100);
    },
  );
  test(
    'legacy manifest-server archive is rejected before any upload',
    () async {
      final marker = utf8.encode('{"manifestType":"minecraftModpack"}');
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json', marker.length, marker));
      File(
        p.join(root.path, 'build', 'test-1.0.0-server-distribution.zip'),
      ).writeAsBytesSync(ZipEncoder().encode(archive));
      final result = await publish(['--with-server']);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('legacy manifest-server'));
      expect(uploads, isEmpty);
    },
  );
  for (final directory in [
    '../../escape/',
    '.gitrinth/private/',
    'safe-link/',
  ]) {
    test(
      'rejects unsafe/private or symlink directory $directory before upload',
      () async {
        final file = File(
          p.join(root.path, 'build', 'test-1.0.0-server-distribution.zip'),
        );
        final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
        final entry = ArchiveFile.directory(directory);
        if (directory == 'safe-link/') {
          entry.symbolicLink = '../../outside';
          entry.mode = 0xa1ff;
        }
        archive.addFile(entry);
        file.writeAsBytesSync(ZipEncoder().encode(archive));
        final result = await publish(['--with-server']);
        expect(result.exitCode, 2, reason: result.stderr);
        expect(result.stderr, contains('distribution'));
        expect(uploads, isEmpty);
      },
    );
  }
  for (final wrong in ['corrupt', 'release']) {
    test('rejects $wrong client archive before the first POST', () async {
      File(p.join(root.path, 'build', 'test-1.0.0.zip')).writeAsBytesSync(
        wrong == 'corrupt' ? [9] : clientArchive(version: '2.0.0'),
      );
      final result = await publish(['--with-server']);
      expect(result.exitCode, 2, reason: result.stderr);
      expect(result.stderr, contains('client'));
      expect(uploads, isEmpty);
    });
  }
  test(
    'floating manifest loader can publish matching concrete archives without a lock',
    () async {
      final yaml = File(p.join(root.path, 'mods.yaml'));
      yaml.writeAsStringSync(
        yaml.readAsStringSync().replaceFirst('fabric:0.16.0', 'fabric:stable'),
      );
      final result = await publish(['--with-server']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(uploads, hasLength(2));
    },
  );
  test(
    'server distribution preserves and validates plugin runtime identity',
    () async {
      final yaml = File(p.join(root.path, 'mods.yaml'));
      yaml.writeAsStringSync(
        yaml.readAsStringSync().replaceFirst(
          "loader: {mods: 'fabric:0.16.0'}",
          "loader: {mods: vanilla, plugins: 'paper:100'}",
        ),
      );
      File(
        p.join(root.path, 'build', 'test-1.0.0.zip'),
      ).writeAsBytesSync(clientArchive(loader: null));
      final file = File(
        p.join(root.path, 'build', 'test-1.0.0-server-distribution.zip'),
      );
      final oldArchive = ZipDecoder().decodeBytes(file.readAsBytesSync());
      final oldMarker = jsonDecode(
        utf8.decode(
          oldArchive.findFile('gitrinth-server-distribution.json')!.content,
        ),
      );
      oldMarker['loader'] = {
        'id': 'vanilla',
        'version': null,
        'plugins': {'id': 'paper', 'version': '100'},
      };
      oldMarker['files'].single['path'] = 'plugins/server.jar';
      final marker = utf8.encode(jsonEncode(oldMarker));
      final content = oldArchive.findFile('mods/server.jar')!.content;
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'gitrinth-server-distribution.json',
            marker.length,
            marker,
          ),
        )
        ..addFile(ArchiveFile('plugins/server.jar', content.length, content));
      file.writeAsBytesSync(ZipEncoder().encode(archive));
      final result = await publish(['--with-server']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(uploads, hasLength(2));
      yaml.writeAsStringSync(
        yaml.readAsStringSync().replaceFirst('paper:100', 'paper:101'),
      );
      final wrong = await publish(['--with-server']);
      expect(wrong.exitCode, 2);
      expect(wrong.stderr, contains('loader'));
      expect(uploads, hasLength(2));
    },
  );
  test(
    'printed retry runs from the original external directory with explicit selections',
    () async {
      final outside = Directory(p.join(root.path, 'original directory'))
        ..createSync();
      final config = File(p.join(root.path, 'release config.yaml'))
        ..writeAsStringSync(
          'tokens:\n  https://curseforge.com: private-upload-token\n',
        );
      final descriptors = File(p.join(root.path, 'release loaders.yaml'))
        ..writeAsStringSync('version: 1\nloaders: {}\n');
      final environment = {
        'GITRINTH_CURSEFORGE_TOKEN': 'private-read-token',
        'GITRINTH_CURSEFORGE_URL': host,
        'GITRINTH_CURSEFORGE_UPLOAD_URL': host,
      };
      rejectChild = true;
      final first = await runCli(
        [
          '-C',
          root.path,
          '--config',
          config.path,
          'curseforge',
          'publish',
          '--loader-descriptors',
          descriptors.path,
          '--with-server',
          '--curseforge-project',
          '42',
          '--force',
        ],
        workingDirectory: outside.path,
        environment: environment,
      );
      expect(first.exitCode, isNot(0));
      final command = RegExp(
        r'Retry only the server: (gitrinth [^\r\n]+)',
      ).firstMatch(first.stderr)?.group(1);
      expect(command, isNotNull, reason: first.stderr);
      final arguments = RegExp(r"'(?:[^']|'')*'|[^\s]+")
          .allMatches(command!)
          .map((match) {
            final token = match.group(0)!;
            return token.startsWith("'")
                ? token.substring(1, token.length - 1).replaceAll("''", "'")
                : token;
          })
          .skip(1)
          .toList();
      rejectChild = false;
      final retried = await runCli(
        arguments,
        workingDirectory: outside.path,
        environment: environment,
      );
      expect(
        retried.exitCode,
        0,
        reason: '${retried.stdout}\n${retried.stderr}',
      );
      expect(
        arguments,
        containsAll([
          '-C',
          root.path,
          '--config',
          config.path,
          '--loader-descriptors',
          descriptors.path,
        ]),
      );
      expect(command, isNot(contains('private-upload-token')));
      expect(uploads, hasLength(3));
    },
  );
}
