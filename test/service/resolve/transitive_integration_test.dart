import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';
import '../../helpers/capture.dart';
import '../../helpers/fake_modrinth.dart';

void main() {
  test(
    'identical project IDs on two hosts retain separate dependency identities offline',
    () async {
      final root = Directory.systemTemp.createTempSync('two_host_graph_');
      final defaultApi = FakeModrinth();
      final hostedApi = FakeModrinth();
      await defaultApi.start();
      await hostedApi.start();
      addTearDown(() async {
        await defaultApi.stop();
        await hostedApi.stop();
        root.deleteSync(recursive: true);
      });
      for (final api in [defaultApi, hostedApi]) {
        api.registerVersion(
          slug: 'anchor',
          versionNumber: '1.0.0',
          requiredDeps: ['library'],
        );
        api.registerVersion(slug: 'library', versionNumber: '2.0.0');
      }
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
modrinth_host: ${hostedApi.baseUrl}
loader:
  mods: "neoforge:21.1.50"
mods:
  default-anchor:
    modrinth: anchor
    modrinth_host: ${defaultApi.baseUrl}
  hosted-anchor:
    modrinth: anchor
''');
      final environment = {
        'GITRINTH_CACHE': p.join(root.path, 'cache'),
        'GITRINTH_MODRINTH_URL': defaultApi.baseUrl,
        'GITRINTH_NEOFORGE_VERSIONS_URL': defaultApi.neoforgeVersionsUrl,
      };
      final online = await runCli([
        '-C',
        root.path,
        'get',
      ], environment: environment);
      expect(online.exitCode, 0, reason: '${online.stdout}\n${online.stderr}');
      final lockFile = File(p.join(root.path, 'mods.lock'));
      final before = lockFile.readAsStringSync();
      final lock = parseModsLock(before, filePath: 'mods.lock');
      final children = lock.mods.values
          .where((e) => e.modrinth?.projectId == 'library_ID')
          .toList();
      expect(children, hasLength(2));
      expect(
        children.map((e) => e.modrinth!.host),
        unorderedEquals([null, hostedApi.baseUrl]),
      );
      final offline = await runCli([
        '-C',
        root.path,
        'get',
        '--offline',
      ], environment: environment);
      expect(offline.exitCode, 0, reason: offline.stderr);
      expect(lockFile.readAsStringSync(), before);
    },
  );
  test(
    'declared plugin dependency alias takes precedence over sparse project metadata',
    () async {
      final root = Directory.systemTemp.createTempSync('declared_plugin_');
      final mr = FakeModrinth();
      await mr.start();
      addTearDown(() async {
        await mr.stop();
        root.deleteSync(recursive: true);
      });
      mr.registerVersion(
        slug: 'anchor',
        versionNumber: '1.0.0',
        requiredDeps: ['library'],
      );
      mr.registerVersion(slug: 'library', versionNumber: '2.0.0');
      for (final versions in mr.versions.values) {
        versions.single['loaders'] = ['paper'];
      }
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader:
  plugins: "paper:100"
plugins:
  anchor: null
  my-library:
    modrinth: library
    version: ^2.0.0
''');
      final result = await runCli(
        ['-C', root.path, 'get'],
        environment: {
          'GITRINTH_CACHE': p.join(root.path, 'cache'),
          'GITRINTH_MODRINTH_URL': mr.baseUrl,
          'GITRINTH_PAPER_API_URL': mr.paperBuildsUrl,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final lock = parseModsLock(
        File(p.join(root.path, 'mods.lock')).readAsStringSync(),
        filePath: 'mods.lock',
      );
      expect(lock.plugins.keys, unorderedEquals(['anchor', 'my-library']));
      expect(lock.plugins['my-library']!.requiredBy, ['anchor']);
      expect(lock.mods, isEmpty);
    },
  );
  for (final (olderSelection, mrOnlyRoot, cfOnlyRoot, searchPeers) in [
    (false, false, false, false),
    (true, false, false, false),
    (false, true, false, false),
    (false, false, true, false),
    (false, true, false, true),
    (false, false, true, true),
  ]) {
    test(
      searchPeers
          ? 'transitive ${mrOnlyRoot ? "CurseForge" : "Modrinth"} peers use hash-verified search'
          : cfOnlyRoot
          ? 'offline preserves synthetic peers under a CurseForge-only root'
          : mrOnlyRoot
          ? 'offline preserves synthetic peers under a Modrinth-only root'
          : olderSelection
          ? 'hash-selected CF graph removes stale children and probes new MR peers'
          : 'divergent synthetic slugs merge by hash with unioned parent edges',
      () async {
        final root = Directory.systemTemp.createTempSync('transitive_bridge_');
        final mr = FakeModrinth();
        await mr.start();
        final cf = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await cf.close(force: true);
          await mr.stop();
          root.deleteSync(recursive: true);
        });
        mr.registerVersion(
          slug: 'anchor',
          versionNumber: '1.0.0',
          requiredDeps: olderSelection ? [] : ['library'],
        );
        mr.registerVersion(
          slug: 'library',
          versionNumber: '2.0.0',
          requiredDeps: ['leaf'],
        );
        mr.registerVersion(slug: 'leaf', versionNumber: '3.0.0');
        mr.searchHits = [
          {
            'project_id': 'library_ID',
            'slug': 'library',
            'title': 'Library',
            'author': 'Author',
            'project_type': 'mod',
            'categories': ['neoforge'],
          },
        ];
        for (final versions in mr.versions.values) {
          for (final version in versions) {
            final file = (version['files'] as List).single as Map;
            final url = Uri.parse(file['url'] as String);
            final key = url.pathSegments
                .skip(url.pathSegments.length - 2)
                .join('/');
            (file['hashes'] as Map)['sha1'] = sha1
                .convert(mr.artifacts[key]!)
                .toString();
          }
        }
        final anchorFile =
            (mr.versions['anchor']!.single['files'] as List).single as Map;
        final libraryFile =
            (mr.versions['library']!.single['files'] as List).single as Map;
        final leafFile =
            (mr.versions['leaf']!.single['files'] as List).single as Map;
        final projects = {
          4: {
            'id': 4,
            'gameId': 432,
            'classId': 6,
            'slug': 'leaf',
            'name': 'Leaf',
          },
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
            'classId': 6,
            'slug': !searchPeers && (olderSelection || mrOnlyRoot || cfOnlyRoot)
                ? 'library'
                : 'library-forge',
            'name': 'Library',
          },
          3: {
            'id': 3,
            'gameId': 432,
            'classId': 6,
            'slug': 'stale-library',
            'name': 'Stale',
          },
        };
        Map<String, dynamic> file(
          int project,
          int id,
          Map reference,
          List<int> children,
          String date,
        ) => {
          'id': id,
          'modId': project,
          'displayName': '1.0.0',
          'fileName': '$id.jar',
          'releaseType': 1,
          'fileDate': date,
          'gameVersions': ['1.21.1'],
          'hashes': [
            {'algo': 1, 'value': (reference['hashes'] as Map)['sha1']},
          ],
          'dependencies': [
            for (final child in children) {'modId': child, 'relationType': 3},
          ],
          'downloadUrl': reference['url'],
        };
        final files = {
          1: [
            if (olderSelection) file(1, 12, libraryFile, [3], '2026-02-01'),
            file(1, 11, anchorFile, [2], '2026-01-01'),
          ],
          2: [
            file(2, 21, libraryFile, [4], '2026-01-01'),
          ],
          4: [file(4, 41, leafFile, [], '2026-01-01')],
          3: [file(3, 31, libraryFile, [], '2026-01-01')],
        };
        final requestCounts = <String, int>{};
        cf.listen((req) async {
          requestCounts.update(
            req.uri.toString(),
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          dynamic data;
          if (req.uri.path.endsWith('/search')) {
            data = projects.values
                .where(
                  (project) =>
                      project['slug'] == req.uri.queryParameters['slug'] ||
                      (searchPeers &&
                          req.uri.queryParameters['searchFilter'] ==
                              'library' &&
                          project['id'] == 2),
                )
                .toList();
          } else {
            final parts = req.uri.path.split('/');
            final id = int.tryParse(parts[3]);
            data = parts.length == 4 ? projects[id] : files[id] ?? [];
          }
          req.response.headers.contentType = ContentType.json;
          req.response.write(
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
          await req.response.close();
        });
        File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader:
  mods: "neoforge:21.1.50"
gitrinth:
  curseforge: enabled
mods:
  anchor: ${mrOnlyRoot
            ? '{sources: modrinth}'
            : cfOnlyRoot
            ? '{sources: curseforge}'
            : 'null'}
''');
        final result = await runCli(
          ['-C', root.path, 'get', if (!searchPeers) '--no-search'],
          environment: {
            'GITRINTH_CACHE': p.join(root.path, 'cache'),
            'GITRINTH_NEOFORGE_VERSIONS_URL': mr.neoforgeVersionsUrl,
            'GITRINTH_MODRINTH_URL': mr.baseUrl,
            'GITRINTH_CURSEFORGE_URL': 'http://127.0.0.1:${cf.port}',
            'GITRINTH_CURSEFORGE_TOKEN': 'test-key',
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final lock = parseModsLock(
          File(p.join(root.path, 'mods.lock')).readAsStringSync(),
          filePath: 'mods.lock',
        );
        expect(lock.mods.keys, unorderedEquals(['anchor', 'library', 'leaf']));
        expect(lock.mods['leaf']!.modrinth, isNotNull);
        expect(lock.mods['leaf']!.curseforge, isNotNull);
        expect(lock.mods['leaf']!.requiredBy, ['library']);
        expect(lock.mods['library']!.modrinth, isNotNull);
        expect(lock.mods['library']!.curseforge, isNotNull);
        expect(lock.mods['library']!.requiredBy, ['anchor']);
        expect(
          requestCounts.values.every((count) => count == 1),
          isTrue,
          reason: '$requestCounts',
        );
        if (olderSelection) {
          expect(lock.mods['anchor']!.curseforge!.fileId, 11);
        } else if (!mrOnlyRoot && !cfOnlyRoot) {
          expect(lock.mods['library']!.curseforge!.slug, 'library-forge');
        }
        {
          final lockFile = File(p.join(root.path, 'mods.lock'));
          final before = lockFile.readAsStringSync();
          final offline = await runCli(
            ['-C', root.path, 'get', '--offline'],
            environment: {
              'GITRINTH_CACHE': p.join(root.path, 'cache'),
              'GITRINTH_MODRINTH_URL': mr.baseUrl,
              'GITRINTH_CURSEFORGE_URL': 'http://127.0.0.1:${cf.port}',
            },
          );
          expect(offline.exitCode, 0, reason: offline.stderr);
          expect(lockFile.readAsStringSync(), before);
        }
      },
    );
  }
}
