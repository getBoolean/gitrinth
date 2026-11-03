import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

import '../../helpers/capture.dart';
import '../../helpers/fake_modrinth.dart';

void main() {
  for (final declaredResource in [false, true]) {
    test(
      'override targets declared entries with ${declaredResource ? 'declared' : 'synthetic'} same-name CF dependency',
      () async {
        final root = Directory.systemTemp.createTempSync('override_collision_');
        final mr = FakeModrinth();
        await mr.start();
        final cf = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await cf.close(force: true);
          await mr.stop();
          root.deleteSync(recursive: true);
        });
        mr.registerVersion(slug: 'library', versionNumber: '1.0.0');
        mr.registerVersion(slug: 'library', versionNumber: '2.0.0');
        final host = 'http://127.0.0.1:${cf.port}';
        final projects = {
          1: {
            'id': 1,
            'gameId': 432,
            'classId': 6,
            'slug': 'anchor',
            'name': 'Anchor',
          },
          2: {
            'id': 2,
            'gameId': 432,
            'classId': 12,
            'slug': 'library',
            'name': 'Library resource pack',
          },
        };
        Map<String, dynamic> file(
          int project,
          int id,
          String version,
          List<int> children,
        ) => {
          'id': id,
          'modId': project,
          'displayName': version,
          'fileName': '$id.jar',
          'releaseType': 1,
          'fileDate': '2026-${version.startsWith('3') ? '03' : '02'}-01',
          'gameVersions': ['1.21.1'],
          'hashes': [],
          'dependencies': [
            for (final child in children) {'modId': child, 'relationType': 3},
          ],
          'downloadUrl': '$host/artifact/$id',
        };
        final files = {
          1: [
            file(1, 11, '1.0.0', [2]),
          ],
          2: [file(2, 32, '3.0.0', []), file(2, 22, '2.0.0', [])],
        };
        cf.listen((request) async {
          if (request.uri.path.startsWith('/artifact/')) {
            request.response.add([1, 2, 3]);
          } else {
            final parts = request.uri.pathSegments;
            final dynamic data;
            if (parts.last == 'search') {
              data = projects.values
                  .where(
                    (project) =>
                        project['slug'] == request.uri.queryParameters['slug'],
                  )
                  .toList();
            } else {
              final id = int.parse(parts[2]);
              data = parts.length == 3 ? projects[id] : files[id];
            }
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
        File('${root.path}/mods.yaml').writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'neoforge:21.1.50'}
gitrinth: {modrinth: disabled, curseforge: enabled}
mods:
  library: {version: 1.0.0, sources: modrinth}
  anchor: {sources: curseforge}
${declaredResource ? 'resource_packs:\n  library: {version: 1.0.0, sources: curseforge}' : ''}
project_overrides:
  library: 2.0.0
''');
        final result = await runCli(
          ['-C', root.path, 'get', '--no-search'],
          environment: {
            'GITRINTH_CACHE': '${root.path}/cache',
            'GITRINTH_CONFIG': '${root.path}/config.yaml',
            'GITRINTH_MODRINTH_URL': mr.baseUrl,
            'GITRINTH_NEOFORGE_VERSIONS_URL': mr.neoforgeVersionsUrl,
            'GITRINTH_CURSEFORGE_URL': host,
            'GITRINTH_CURSEFORGE_TOKEN': 'test-key',
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final locked = parseModsLock(
          File('${root.path}/mods.lock').readAsStringSync(),
          filePath: 'mods.lock',
        );
        expect(locked.mods['library']!.modrinth!.versionNumber, '2.0.0');
        expect(
          locked.resourcePacks['library']!.curseforge!.fileId,
          declaredResource ? 22 : 32,
        );
        expect(locked.resourcePacks['library']!.requiredBy, ['anchor']);
      },
    );
  }
}
