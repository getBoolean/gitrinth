import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  test(
    'accepted Minecraft file is verified and archived by its CF identity',
    () async {
      final root = Directory.systemTemp.createTempSync('cf_workflow_');
      final mr = FakeModrinth();
      await mr.start();
      final cf = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await cf.close(force: true);
        await mr.stop();
        root.deleteSync(recursive: true);
      });
      final host = 'http://127.0.0.1:${cf.port}';
      final bytes = utf8.encode('verified resource pack');
      final queries = <String>[];
      var downloads = 0;
      cf.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final path = request.uri.path;
        if (path == '/artifact.zip') {
          downloads++;
          request.response.add(bytes);
        } else if (path == '/v1/mods/42') {
          request.response.write(
            jsonEncode({
              'data': {
                'id': 42,
                'gameId': 432,
                'name': 'Textures',
                'slug': 'textures',
                'classId': 12,
              },
            }),
          );
        } else if (path == '/v1/mods/42/files') {
          final version = request.uri.queryParameters['gameVersion'];
          queries.add(version ?? 'missing');
          final files = version == '1.21'
              ? [
                  {
                    'id': 420,
                    'modId': 42,
                    'displayName': '1.0.0',
                    'fileName': 'textures.zip',
                    'releaseType': 1,
                    'fileDate': '2026-01-01',
                    'gameVersions': ['1.21'],
                    'downloadUrl': '$host/artifact.zip',
                    'dependencies': <Object>[],
                    'hashes': [
                      {'algo': 1, 'value': sha1.convert(bytes).toString()},
                    ],
                  },
                ]
              : <Object>[];
          request.response.write(
            jsonEncode({
              'data': files,
              'pagination': {
                'index': 0,
                'pageSize': 50,
                'resultCount': files.length,
                'totalCount': files.length,
              },
            }),
          );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: cf-workflow
name: CF Workflow
version: 1.0.0
description: test
mc_version: 1.21.1
gitrinth: {modrinth: disabled, curseforge: enabled}
resource_packs:
  local-textures: {curseforge: '42', accepts_mc: ['1.21']}
''');
      final environment = {
        'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
        'GITRINTH_CACHE': p.join(root.path, 'cache'),
        'GITRINTH_MODRINTH_URL': mr.baseUrl,
        'GITRINTH_CURSEFORGE_URL': host,
        'GITRINTH_CURSEFORGE_TOKEN': 'fixture-key',
      };
      final get = await runCli([
        '-C',
        root.path,
        'get',
      ], environment: environment);
      expect(get.exitCode, 0, reason: '${get.stdout}\n${get.stderr}');
      expect(queries, ['1.21.1', '1.21']);
      expect(downloads, 1);
      final lockFile = File(p.join(root.path, 'mods.lock'));
      final lock = parseModsLock(
        lockFile.readAsStringSync(),
        filePath: lockFile.path,
      );
      final source = lock.resourcePacks['local-textures']!.curseforge!;
      expect((source.projectId, source.fileId), (42, 420));
      final cached = GitrinthCache(
        root: environment['GITRINTH_CACHE']!,
      ).curseforgePath(projectId: 42, fileId: 420, filename: 'textures.zip');
      expect(File(cached).readAsBytesSync(), bytes);
      final pack = await runCli([
        '-C',
        root.path,
        'pack',
        '--curseforge',
        '--offline',
      ], environment: environment);
      expect(pack.exitCode, 0, reason: '${pack.stdout}\n${pack.stderr}');
      expect(downloads, 1);
      final zip = ZipDecoder().decodeBytes(
        File(
          p.join(root.path, 'build', 'cf-workflow-1.0.0.zip'),
        ).readAsBytesSync(),
      );
      final manifest = jsonDecode(
        utf8.decode(zip.findFile('manifest.json')!.content),
      );
      expect(manifest['files'], [
        {'projectID': 42, 'fileID': 420, 'required': true},
      ]);
    },
  );
}
