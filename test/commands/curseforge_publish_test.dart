import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/curseforge_pack_assembler.dart';
import 'package:gitrinth/src/commands/pack_assembler.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_upload_client.dart';
import 'package:test/test.dart';
import '../helpers/capture.dart';

const base = '''slug: test
name: Test
version: 1.0.0
description: Test
mc_version: 1.21.1
loader:
  mods: fabric:0.16.0
''';
ModsYaml parse(String tail) =>
    parseModsYaml('$base$tail', filePath: 'mods.yaml');

void main() {
  test(
    'both-target publication uses credentials and changelog captured before uploads',
    () async {
      final temp = Directory.systemTemp.createTempSync('publish_prepared_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        temp.deleteSync(recursive: true);
      });
      final host = 'http://127.0.0.1:${server.port}';
      final config = File('${temp.path}/config.yaml')
        ..writeAsStringSync(
          'tokens:\n  $host: captured-mr-token\n  https://curseforge.com: captured-cf-token\n',
        );
      final changelog = File('${temp.path}/release.md')
        ..writeAsStringSync('Original release notes');
      File(
        '${temp.path}/mods.yaml',
      ).writeAsStringSync('${base}publish_to: [modrinth, curseforge]\n');
      Directory('${temp.path}/build').createSync();
      File('${temp.path}/build/test-1.0.0.mrpack').writeAsBytesSync([1]);
      File('${temp.path}/build/test-1.0.0.zip').writeAsBytesSync([2]);
      final uploads = <String>[];
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        uploads.add(request.uri.path);
        expect(body, contains('Original release notes'));
        if (request.uri.path == '/project/test/version') {
          expect(request.headers.value('Authorization'), 'captured-mr-token');
          config.writeAsStringSync('tokens: {}\n');
          changelog.writeAsStringSync('Changed after first upload');
        } else {
          expect(request.uri.path, '/api/projects/42/upload-file');
          expect(request.headers.value('X-Api-Token'), 'captured-cf-token');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"id":123}');
        await request.response.close();
      });
      final result = await runCli(
        [
          '-C',
          temp.path,
          'publish',
          '--force',
          '--curseforge-project',
          '42',
          '--changelog',
          changelog.path,
        ],
        environment: {
          'GITRINTH_CONFIG': config.path,
          'GITRINTH_MODRINTH_URL': host,
          'GITRINTH_CURSEFORGE_UPLOAD_URL': host,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(uploads, [
        '/project/test/version',
        '/api/projects/42/upload-file',
      ]);
    },
  );
  test(
    'upload honors a caller receive timeout without retrying a stalled response',
    () async {
      final temp = Directory.systemTemp.createTempSync('cf_upload_timeout_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = Dio(
        BaseOptions(receiveTimeout: const Duration(milliseconds: 50)),
      );
      addTearDown(() async {
        dio.close(force: true);
        await server.close(force: true);
        temp.deleteSync(recursive: true);
      });
      final archive = File('${temp.path}/pack.zip')
        ..writeAsBytesSync([1, 2, 3]);
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
      });
      await expectLater(
        CurseForgeUploadClient(
          dio,
          baseUrl: 'http://127.0.0.1:${server.port}',
        ).upload(
          projectId: 42,
          token: 'test-token',
          archive: archive,
          metadata: {'releaseType': 'release'},
        ),
        throwsA(isA<UserError>()),
      );
      expect(requests, 1);
    },
  );
  test(
    'second-target failure preserves first-target success without retrying',
    () async {
      final temp = Directory.systemTemp.createTempSync('publish_partial_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        temp.deleteSync(recursive: true);
      });
      final host = 'http://127.0.0.1:${server.port}';
      final config = File('${temp.path}/config.yaml')
        ..writeAsStringSync(
          'tokens:\n  $host: mr-token\n  https://curseforge.com: cf-token\n',
        );
      File(
        '${temp.path}/mods.yaml',
      ).writeAsStringSync('${base}publish_to: [modrinth, curseforge]\n');
      Directory('${temp.path}/build').createSync();
      File('${temp.path}/build/test-1.0.0.mrpack').writeAsBytesSync([1]);
      File('${temp.path}/build/test-1.0.0.zip').writeAsBytesSync([2]);
      final uploads = <String>[];
      server.listen((request) async {
        await request.drain<void>();
        uploads.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = uploads.length == 1 ? 201 : 500;
        request.response.write(
          uploads.length == 1 ? '{"id":123}' : '{"error":"rejected"}',
        );
        await request.response.close();
      });
      final result = await runCli(
        ['-C', temp.path, 'publish', '--force', '--curseforge-project', '42'],
        environment: {
          'GITRINTH_CONFIG': config.path,
          'GITRINTH_MODRINTH_URL': host,
          'GITRINTH_CURSEFORGE_UPLOAD_URL': host,
        },
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('Published test v1.0.0 to $host'));
      expect(result.stdout, isNot(contains('to CurseForge')));
      expect(result.stderr, contains('upload'));
      expect(uploads, [
        '/project/test/version',
        '/api/projects/42/upload-file',
      ]);
    },
  );
  test(
    'publish selects both platforms and rejects a download key as upload authentication',
    () async {
      final temp = Directory.systemTemp.createTempSync('cf_publish_cli_');
      addTearDown(() => temp.deleteSync(recursive: true));
      File(
        '${temp.path}/mods.yaml',
      ).writeAsStringSync('${base}publish_to: [modrinth, curseforge]\n');
      Directory('${temp.path}/build').createSync();
      File('${temp.path}/build/test-1.0.0.mrpack').writeAsBytesSync([1]);
      File('${temp.path}/build/test-1.0.0.zip').writeAsBytesSync([2]);
      final args = [
        '-C',
        temp.path,
        'publish',
        '--dry-run',
        '--curseforge-project',
        '42',
      ];
      final env = {
        'GITRINTH_CONFIG': '${temp.path}/config.yaml',
        'GITRINTH_TOKEN': 'mr-token',
        'GITRINTH_CURSEFORGE_TOKEN': 'download-token',
      };
      final denied = await runCli(args, environment: env);
      expect(denied.exitCode, 4);
      expect(denied.stderr, contains('publish token'));
      // Preflight prevents even a first-target upload/dry-run with invalid CF auth.
      expect(denied.stdout, isNot(contains('would publish')));
      final out = await runCli(
        args,
        environment: {
          ...env,
          'GITRINTH_CURSEFORGE_UPLOAD_TOKEN': 'upload-token',
        },
      );
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(
        out.stdout,
        contains('would publish to https://api.modrinth.com/v2'),
      );
      expect(out.stdout, contains('would publish to CurseForge'));
      expect(out.stdout, contains('"gameVersionNames"'));
    },
  );

  test('publish_to.modrinth host is independent from source host', () async {
    final temp = Directory.systemTemp.createTempSync('host_publish_cli_');
    addTearDown(() => temp.deleteSync(recursive: true));
    File('${temp.path}/mods.yaml').writeAsStringSync(
      '${base}modrinth_host: https://source.example\npublish_to: {modrinth: https://publish.example/v2}\n',
    );
    Directory('${temp.path}/build').createSync();
    File('${temp.path}/build/test-1.0.0.mrpack').writeAsBytesSync([1]);
    File('${temp.path}/config.yaml').writeAsStringSync(
      'tokens:\n  https://publish.example/v2: hosted-token\n',
    );
    final out = await runCli(
      ['-C', temp.path, 'publish', '--dry-run'],
      environment: {'GITRINTH_CONFIG': '${temp.path}/config.yaml'},
    );
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('would publish to https://publish.example/v2'));
    expect(
      out.stdout,
      isNot(contains('would publish to https://source.example')),
    );
  });

  test('publish selectors normalize and defaults follow enabled platforms', () {
    expect(parse('').publishTargets.keys, [SourceKind.modrinth]);
    expect(parse('gitrinth: {curseforge: enabled}').publishTargets.length, 2);
    expect(parse('publish_to: none').publishTargets, isEmpty);
    for (final selector in [
      'curseforge',
      '[curseforge]',
      '{curseforge: null}',
      '{curseforge: {}}',
    ]) {
      expect(parse('publish_to: $selector').publishTargets, {
        SourceKind.curseforge: null,
      });
    }
    expect(
      parse(
        'publish_to: {modrinth: https://example.org, curseforge: null}',
      ).publishTargets,
      {SourceKind.modrinth: 'https://example.org', SourceKind.curseforge: null},
    );
    for (final selector in [
      '[]',
      '{}',
      '[modrinth, modrinth]',
      '[none]',
      '{none: null}',
      'https://example.org',
      'bad',
      '{curseforge: true}',
      '{modrinth: invalid}',
    ]) {
      expect(
        () => parse('publish_to: $selector'),
        throwsA(isA<ValidationError>()),
        reason: selector,
      );
    }
  });

  test(
    '--publishable rejects explicit hash-mismatch permission for the selected platform',
    () {
      final yaml = parse('mods:\n  divergent: {allow_hash_mismatch: true}\n');
      const entry = LockedEntry(
        slug: 'divergent',
        kind: LockedEntryKind.resolved,
        modrinth: LockedModrinthSource(
          projectId: 'mr',
          versionId: 'v',
          file: LockedFile(name: 'mr.jar', sha1: 'a', sha512: 'b', size: 1),
        ),
        curseforge: LockedCurseforgeSource(
          projectId: 42,
          fileId: 99,
          file: LockedFile(name: 'cf.jar'),
        ),
      );
      const lock = ModsLock(
        gitrinthVersion: 'test',
        mcVersion: '1.21.1',
        loader: LoaderConfig(
          mods: ModLoader.fabric,
          modLoaderVersion: '0.16.0',
        ),
        mods: {'divergent': entry},
      );
      expect(
        () => buildIndex(
          yaml: yaml,
          lock: lock,
          target: PackTarget.client,
          publishable: true,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => buildCurseForgeManifest(
          yaml: yaml,
          lock: lock,
          target: PackTarget.client,
          publishable: true,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(
        buildCurseForgeManifest(
          yaml: yaml,
          lock: lock,
          target: PackTarget.client,
          publishable: false,
        )['files'],
        hasLength(1),
      );
    },
  );

  test(
    'CurseForge archive contains references and server-side plugin override bytes',
    () {
      final temp = Directory.systemTemp.createTempSync('cf_archive_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final plugin = File('${temp.path}/plugin.jar')
        ..writeAsBytesSync([1, 2, 3]);
      final yaml = parse('');
      final lock = ModsLock(
        gitrinthVersion: 'test',
        mcVersion: '1.21.1',
        loader: const LoaderConfig(
          mods: ModLoader.fabric,
          modLoaderVersion: '0.16.0',
          plugins: PluginLoader.folia,
        ),
        mods: {
          'cf': const LockedEntry(
            slug: 'cf',
            kind: LockedEntryKind.resolved,
            curseforge: LockedCurseforgeSource(
              projectId: 42,
              fileId: 99,
              file: LockedFile(name: 'cf.jar'),
            ),
          ),
        },
        plugins: {
          'plugin': LockedEntry(
            slug: 'plugin',
            kind: LockedEntryKind.path,
            path: plugin.path,
            client: SideEnv.unsupported,
          ),
        },
      );
      final overrides = curseForgeOverrides(
        lock: lock,
        cache: GitrinthCache(root: '${temp.path}/cache'),
        projectDir: temp.path,
        target: PackTarget.server,
      );
      final manifest = buildCurseForgeManifest(
        yaml: yaml,
        lock: lock,
        target: PackTarget.server,
        publishable: false,
      );
      final output = File('${temp.path}/pack.zip');
      writePackArchive(
        output,
        manifestName: 'manifest.json',
        manifest: manifest,
        overrides: overrides.entries,
      );
      final zip = ZipDecoder().decodeBytes(output.readAsBytesSync());
      final decoded = jsonDecode(
        utf8.decode(zip.findFile('manifest.json')!.content),
      );
      expect(decoded['files'], [
        {'projectID': 42, 'fileID': 99, 'required': true},
      ]);
      expect(decoded['minecraft']['modLoaders'], [
        {'id': 'fabric-0.16.0', 'primary': true},
      ]);
      expect(zip.findFile('overrides/plugins/plugin.jar')!.content, [1, 2, 3]);
      expect(zip.findFile('modrinth.index.json'), isNull);
      expect(
        () => buildCurseForgeManifest(
          yaml: yaml,
          lock: lock,
          target: PackTarget.server,
          publishable: true,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => buildCurseForgeManifest(
          yaml: yaml,
          lock: lock,
          target: PackTarget.client,
          publishable: true,
        ),
        returnsNormally,
      );
    },
  );

  test(
    'upload sends personal token and multipart metadata to upload endpoint',
    () async {
      final temp = Directory.systemTemp.createTempSync('cf_upload_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/pack.zip')..writeAsBytesSync([1, 2, 3]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestFuture = server.first.then((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/projects/42/upload-file');
        expect(request.headers.value('X-Api-Token'), 'upload-secret');
        expect(request.headers.value('x-api-key'), isNull);
        final body = await utf8.decoder.bind(request).join();
        expect(body, contains('name="metadata"'));
        expect(body, contains('"releaseType":"release"'));
        expect(body, contains('filename="pack.zip"'));
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"id":123}');
        await request.response.close();
      });
      final dio = Dio();
      addTearDown(dio.close);
      final result =
          await CurseForgeUploadClient(
            dio,
            baseUrl: 'http://127.0.0.1:${server.port}',
          ).upload(
            projectId: 42,
            token: 'upload-secret',
            archive: file,
            metadata: {'releaseType': 'release'},
          );
      await requestFuture;
      expect(result.fileId, 123);
    },
  );
}
