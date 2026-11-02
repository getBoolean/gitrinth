import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  late Directory root;
  late FakeModrinth mr;
  late HttpServer cf;
  late String cfBaseUrl;
  late List<Map<String, dynamic>> candidates;
  late Map<int, List<Map<String, dynamic>>> files;
  late List<Uri> requests;
  late List<Map<String, dynamic>> exactProjects;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('gitrinth_search_');
    mr = FakeModrinth();
    await mr.start();
    mr.registerVersion(slug: 'anchor', versionNumber: '1.0.0');
    cf = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cfBaseUrl = 'http://127.0.0.1:${cf.port}';
    requests = [];
    exactProjects = [];
    candidates = [
      {
        'id': 42,
        'gameId': 432,
        'classId': 6,
        'slug': 'different-slug',
        'name': 'Anchor',
      },
    ];
    final hashes =
        (mr.versions['anchor']!.single['files'] as List).single['hashes']
            as Map;
    hashes['sha1'] = sha1.convert(mr.artifacts.values.single).toString();
    final hash = hashes['sha1'];
    files = {
      42: [
        {
          'id': 7,
          'modId': 42,
          'displayName': '1.0.0',
          'fileName': 'anchor.jar',
          'releaseType': 1,
          'fileDate': '2026-01-01T00:00:00Z',
          'gameVersions': ['1.21.1'],
          'hashes': [
            {'value': hash, 'algo': 1},
          ],
          'dependencies': [],
          'downloadUrl': '${mr.downloadBaseUrl}/anchor/anchor-1.0.0.jar',
        },
      ],
    };
    cf.listen((req) async {
      requests.add(req.uri);
      if (RegExp(r'^/v1/mods/\d+$').hasMatch(req.uri.path)) {
        final id = int.parse(req.uri.pathSegments.last);
        final project = [
          ...exactProjects,
          ...candidates,
        ].where((p) => p['id'] == id).firstOrNull;
        req.response.headers.contentType = ContentType.json;
        if (project == null) req.response.statusCode = 404;
        req.response.write(jsonEncode({'data': project}));
        await req.response.close();
        return;
      }
      final data = req.uri.path.endsWith('/search')
          ? (req.uri.queryParameters.containsKey('searchFilter')
                ? (req.uri.queryParameters['searchFilter'] == 'anchor'
                      ? candidates
                      : [])
                : (req.uri.queryParameters['slug'] == 'anchor'
                      ? exactProjects
                      : []))
          : files[int.tryParse(req.uri.path.split('/')[3])] ?? [];
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'data': data,
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
  });
  tearDown(() async {
    await mr.stop();
    await cf.close(force: true);
    root.deleteSync(recursive: true);
  });

  Future<CapturedOutput> run({
    String extra = '',
    List<String> flags = const [],
    bool dryRun = true,
    String constraint = 'null',
    String section = 'mods',
    String pluginLoader = '',
    String command = 'get',
  }) async {
    File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader:
  mods: "neoforge:21.1.50"
$pluginLoader
gitrinth:
  curseforge: enabled
$section:
  anchor:
    version: $constraint
$extra
''');
    return runCli(
      ['-C', root.path, command, if (dryRun) '--dry-run', ...flags],
      environment: {
        'GITRINTH_CACHE': p.join(root.path, 'cache'),
        'GITRINTH_NEOFORGE_VERSIONS_URL': mr.neoforgeVersionsUrl,
        'GITRINTH_PAPER_API_URL': mr.paperBuildsUrl,
        'GITRINTH_MODRINTH_URL': mr.baseUrl,
        'GITRINTH_CURSEFORGE_URL': cfBaseUrl,
        'GITRINTH_CURSEFORGE_TOKEN': 'test-key',
      },
    );
  }

  test('missing CF slug discovers its hash-identical peer', () async {
    final out = await run(dryRun: false);
    expect(out.exitCode, 0, reason: out.stderr);
    expect(out.stderr, isNot(contains('not found')));
    expect(
      out.stdout,
      contains('different-slug'),
      reason: '${out.exitCode}: ${out.stderr}',
    );
    expect(
      requests.where((u) => u.queryParameters.containsKey('searchFilter')),
      hasLength(1),
    );
    final lock = File(p.join(root.path, 'mods.lock')).readAsStringSync();
    expect(lock, contains('discovered_via_search: true'));
    expect(lock, contains('slug: different-slug'));
    // Project metadata is shared between dependency resolution and peer ranking.
    expect(mr.requestCounts['/v2/project/anchor_ID'], 1);
    final offline = await run(flags: ['--offline'], dryRun: false);
    expect(offline.exitCode, 0, reason: offline.stderr);
    expect(File(p.join(root.path, 'mods.lock')).readAsStringSync(), lock);
  });

  test('CF-only get writes a complete lock and reuses it offline', () async {
    exactProjects = candidates;
    final online = await run(extra: '    sources: curseforge', dryRun: false);
    expect(online.exitCode, 0, reason: online.stderr);
    final lock = File(p.join(root.path, 'mods.lock'));
    final before = lock.readAsStringSync();
    expect(before, contains('project_id: 42'));
    expect(before, isNot(contains('    modrinth:')));
    expect(
      mr.requestCounts.keys.where(
        (k) => k.startsWith('/v2/project/') || k == '/v2/search',
      ),
      isEmpty,
    );
    await cf.close(force: true);
    final offline = await run(
      extra: '    sources: curseforge',
      flags: ['--offline'],
      dryRun: false,
    );
    expect(offline.exitCode, 0, reason: offline.stderr);
    expect(lock.readAsStringSync(), before);
  });

  test('allow_hash_mismatch locks both verified artifacts and warns', () async {
    exactProjects = candidates;
    mr.registerVersion(slug: 'cf-artifact', versionNumber: '2.0.0');
    final cfSha = sha1
        .convert(mr.artifacts['cf-artifact/cf-artifact-2.0.0.jar']!)
        .toString();
    files[42]!.single['hashes'] = [
      {'algo': 1, 'value': cfSha},
    ];
    files[42]!.single['downloadUrl'] =
        '${mr.downloadBaseUrl}/cf-artifact/cf-artifact-2.0.0.jar';
    final out = await run(
      extra: '    allow_hash_mismatch: true',
      dryRun: false,
    );
    expect(out.exitCode, 0, reason: out.stderr);
    expect(out.stderr, contains('accepting because allow_hash_mismatch: true'));
    final text = File(p.join(root.path, 'mods.lock')).readAsStringSync();
    expect(text, contains('    modrinth:'));
    expect(text, contains('    curseforge:'));
    expect(text, contains('sha1: $cfSha'));
    expect(
      requests.where((u) => u.queryParameters.containsKey('searchFilter')),
      isEmpty,
    );
  });

  for (final marker in [
    'gitrinth:not-found',
    'gitrinth:disabled-by-conflict',
  ]) {
    test(
      '$marker is excluded from CF resolution, online and offline',
      () async {
        final initial = await run(dryRun: false);
        expect(initial.exitCode, 0, reason: initial.stderr);
        requests.clear();
        exactProjects = candidates;
        final offline = await run(
          constraint: marker,
          flags: ['--offline'],
          dryRun: false,
        );
        expect(offline.exitCode, 0, reason: offline.stderr);
        expect(
          File(p.join(root.path, 'mods.lock')).readAsStringSync(),
          isNot(contains('  anchor:')),
        );
        final online = await run(constraint: marker, dryRun: false);
        expect(online.exitCode, 0, reason: online.stderr);
        expect(requests, isEmpty);
        expect(
          File(p.join(root.path, 'mods.lock')).readAsStringSync(),
          isNot(contains('  anchor:')),
        );
      },
    );
  }

  test('offline rejects a CF-only entry without a prior lock', () async {
    final out = await run(
      extra: '    sources: curseforge',
      flags: ['--offline'],
      dryRun: false,
    );
    expect(out.exitCode, 2);
    expect(out.stderr, contains('anchor'));
    expect(out.stderr, contains('offline'));
    expect(File(p.join(root.path, 'mods.lock')).existsSync(), isFalse);
  });

  test(
    'offline rejects a newly added CF-only entry without replacing the lock',
    () async {
      final initial = await run(dryRun: false);
      expect(initial.exitCode, 0, reason: initial.stderr);
      final lock = File(p.join(root.path, 'mods.lock'));
      final before = lock.readAsStringSync();
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
  additional:
    sources: curseforge
    curseforge: "99"
''', mode: FileMode.append);
      final out = await runCli(
        ['-C', root.path, 'get', '--offline'],
        environment: {
          'GITRINTH_CACHE': p.join(root.path, 'cache'),
          'GITRINTH_MODRINTH_URL': mr.baseUrl,
        },
      );
      expect(out.exitCode, 2);
      expect(out.stderr, contains('additional'));
      expect(lock.readAsStringSync(), before);
    },
  );

  test('global and per-entry opt-outs suppress fallback requests', () async {
    for (final flags in [
      <String>['--no-search'],
      <String>[],
    ]) {
      requests.clear();
      final out = await run(
        flags: flags,
        extra: flags.isEmpty ? '    no_cross_platform_search: true' : '',
      );
      expect(out.exitCode, 2);
      expect(out.stdout, isNot(contains('via search')));
      expect(
        requests.where((u) => u.queryParameters.containsKey('searchFilter')),
        isEmpty,
      );
      expect(File(p.join(root.path, 'mods.lock')).existsSync(), isFalse);
    }
  });

  test('offline source restriction drops the old CF block', () async {
    final first = await run(dryRun: false);
    expect(first.exitCode, 0, reason: first.stderr);
    final restricted = await run(
      extra: '    sources: modrinth',
      flags: ['--offline'],
      dryRun: false,
    );
    expect(restricted.exitCode, 0, reason: restricted.stderr);
    final lock = File(p.join(root.path, 'mods.lock')).readAsStringSync();
    expect(lock, isNot(contains('    curseforge:')));
    expect(lock, contains('    modrinth:'));
  });

  test('offline get does not resurrect removed entries', () async {
    final first = await run(dryRun: false);
    expect(first.exitCode, 0, reason: first.stderr);
    final manifest = File(p.join(root.path, 'mods.yaml'));
    manifest.writeAsStringSync(
      manifest.readAsStringSync().replaceAll(
        '  anchor:\n    version: null\n',
        '',
      ),
    );
    final out = await runCli(
      ['-C', root.path, 'get', '--offline'],
      environment: {
        'GITRINTH_CACHE': p.join(root.path, 'cache'),
        'GITRINTH_MODRINTH_URL': mr.baseUrl,
      },
    );
    expect(out.exitCode, 0, reason: out.stderr);
    expect(
      File(p.join(root.path, 'mods.lock')).readAsStringSync(),
      isNot(contains('  anchor:')),
    );
  });

  test(
    'upgrade --major-versions relaxes constraints for discovered MR peers',
    () async {
      exactProjects = candidates;
      mr.versions.remove('anchor');
      mr.registerVersion(slug: 'other', versionNumber: '2.0.0');
      mr.projects['other'] = {
        'id': 'other_ID',
        'slug': 'other',
        'title': 'Anchor',
        'project_type': 'mod',
      };
      final hashes =
          (mr.versions['other']!.single['files'] as List).single['hashes']
              as Map;
      hashes['sha1'] = 'new-hash';
      files[42]!.single['hashes'] = [
        {'algo': 1, 'value': 'new-hash'},
      ];
      mr.searchHits = [
        {
          'project_id': 'other_ID',
          'slug': 'other',
          'title': 'Anchor',
          'author': 'Author',
          'project_type': 'mod',
          'categories': ['neoforge'],
        },
      ];
      final out = await run(
        command: 'upgrade',
        constraint: '^1.0.0',
        flags: ['--major-versions'],
      );
      expect(out.stderr, isEmpty);
      expect(out.stdout, contains('resolved on Modrinth via search'));
    },
  );

  test('single-source entry never searches the excluded platform', () async {
    final out = await run(extra: '    sources: modrinth');
    expect(out.stderr, isEmpty);
    expect(requests, isEmpty);
  });

  for (final change in ['version', 'minecraft', 'peer']) {
    test(
      'offline rejects changed CF-only $change before writing lock',
      () async {
        exactProjects = candidates;
        final online = await run(
          extra: '    sources: curseforge',
          dryRun: false,
        );
        expect(online.exitCode, 0, reason: online.stderr);
        final lock = File(p.join(root.path, 'mods.lock'));
        final before = lock.readAsStringSync();
        final manifest = File(p.join(root.path, 'mods.yaml'));
        var text = manifest.readAsStringSync();
        text = switch (change) {
          'version' => text.replaceFirst('version: null', 'version: ^2.0.0'),
          'minecraft' => text.replaceFirst(
            'mc_version: 1.21.1',
            'mc_version: 1.21.4',
          ),
          _ => '$text    curseforge: another-project\n',
        };
        manifest.writeAsStringSync(text);
        final beforeRequests = requests.length;
        final offline = await runCli(
          ['-C', root.path, 'get', '--offline'],
          environment: {
            'GITRINTH_CACHE': p.join(root.path, 'cache'),
            'GITRINTH_MODRINTH_URL': mr.baseUrl,
          },
        );
        expect(offline.exitCode, 2);
        expect(offline.stderr, contains('does not satisfy'));
        expect(lock.readAsStringSync(), before);
        expect(requests.length, beforeRequests);
      },
    );
  }

  test(
    'Modrinth fallback uses the entry host and leaves the default host alone',
    () async {
      final hosted = FakeModrinth();
      await hosted.start();
      addTearDown(hosted.stop);
      hosted.registerVersion(slug: 'other', versionNumber: '1.0.0');
      hosted.projects['other'] = {
        'id': 'other_ID',
        'slug': 'other',
        'title': 'Anchor',
        'project_type': 'mod',
      };
      (hosted.versions['other']!.single['files'] as List)
              .single['hashes']['sha1'] =
          files[42]!.single['hashes'][0]['value'];
      hosted.searchHits = [
        {
          'project_id': 'other_ID',
          'slug': 'other',
          'title': 'Anchor',
          'author': 'Author',
          'project_type': 'mod',
          'categories': ['neoforge'],
        },
      ];
      exactProjects = candidates;
      final out = await run(extra: '    modrinth_host: ${hosted.baseUrl}');
      expect(out.stderr, isEmpty);
      expect(out.stdout, contains('resolved on Modrinth via search'));
      expect(hosted.requestCounts['/v2/search'], 1);
      expect(mr.requestCounts['/v2/search'], isNull);
    },
  );

  test('fuzzy-only results are diagnostics and do not write a lock', () async {
    files[42]!.single['hashes'] = [
      {'algo': 1, 'value': 'different'},
    ];
    candidates.single['authors'] = [
      {'name': 'ExampleAuthor'},
    ];
    final out = await run(dryRun: false);
    expect(out.exitCode, 2);
    expect(out.stderr, contains('Anchor (different-slug)'));
    expect(out.stderr, contains('ExampleAuthor'));
    expect(out.stdout, isNot(contains('via search')));
    expect(File(p.join(root.path, 'mods.lock')).existsSync(), isFalse);
  });

  test('multiple hash-matching projects remain ambiguous', () async {
    candidates.add({...candidates.single, 'id': 43, 'slug': 'another-peer'});
    files[43] = [
      {...files[42]!.single, 'id': 8, 'modId': 43},
    ];
    final out = await run();
    expect(out.stderr, contains('ambiguous hash matches'));
    expect(out.stdout, isNot(contains('via search')));
  });

  test(
    'no compatible files on the declared project does not trigger search',
    () async {
      exactProjects = candidates;
      files.clear();
      final out = await run();
      expect(out.exitCode, 2);
      expect(
        requests.where((u) => u.queryParameters.containsKey('searchFilter')),
        isEmpty,
      );
    },
  );

  test('hash mismatch searches alternative CF projects', () async {
    exactProjects = [
      {...candidates.single, 'id': 99, 'slug': 'anchor'},
    ];
    files[99] = [
      {
        ...files[42]!.single,
        'modId': 99,
        'hashes': [
          {'algo': 1, 'value': 'wrong'},
        ],
      },
    ];
    final out = await run(dryRun: false);
    expect(out.exitCode, 0, reason: out.stderr);
    final lock = File(p.join(root.path, 'mods.lock')).readAsStringSync();
    expect(lock, contains('project_id: 42'));
    expect(lock, contains('discovered_via_search: true'));
  });

  test('older CF file is searched only inside hash_scan_depth', () async {
    files[42] = [
      {
        ...files[42]!.single,
        'id': 8,
        'fileDate': '2026-02-01T00:00:00Z',
        'hashes': [
          {'algo': 1, 'value': 'newer'},
        ],
      },
      files[42]!.single,
    ];
    final excluded = await run(extra: '    hash_scan_depth: 0');
    expect(excluded.stderr, contains('no unique hash match'));
    final included = await run(extra: '    hash_scan_depth: 1', dryRun: false);
    expect(included.exitCode, 0, reason: included.stderr);
    expect(
      File(p.join(root.path, 'mods.lock')).readAsStringSync(),
      contains('file_id: 7'),
    );
  });

  for (final section in ['data_packs', 'plugins']) {
    test(
      '$section accepts legacy Modrinth mod hits with the right loader',
      () async {
        final loader = section == 'data_packs' ? 'datapack' : 'paper';
        exactProjects = [
          {...candidates.single, 'classId': section == 'data_packs' ? 6945 : 5},
        ];
        mr.versions.remove('anchor');
        mr.registerVersion(
          slug: 'other',
          versionNumber: '1.0.0',
          loader: loader,
        );
        mr.projects['other'] = {
          'id': 'other_ID',
          'slug': 'other',
          'title': 'Anchor',
          'project_type': 'mod',
        };
        (mr.versions['other']!.single['files'] as List)
                .single['hashes']['sha1'] =
            files[42]!.single['hashes'][0]['value'];
        mr.searchHits = [
          {
            'project_id': 'other_ID',
            'slug': 'other',
            'title': 'Anchor',
            'author': 'Author',
            'project_type': 'mod',
            'categories': [loader],
          },
        ];
        final out = await run(
          section: section,
          pluginLoader: section == 'plugins' ? '  plugins: paper' : '',
          dryRun: false,
        );
        expect(out.exitCode, 0, reason: out.stderr);
        expect(mr.lastSearchQuery!['facets'], contains('project_type:mod'));
        expect(mr.lastSearchQuery!['facets'], contains('categories:$loader'));
        expect(
          File(p.join(root.path, 'mods.lock')).readAsStringSync(),
          contains('project_id: other_ID'),
        );
        expect(
          requests
              .where((u) => u.path.endsWith('/files'))
              .every((u) => !u.queryParameters.containsKey('modLoaderType')),
          isTrue,
        );
      },
    );
  }

  test(
    'CF fallback filters by section and accepts additional MC versions',
    () async {
      files[42]!.single['gameVersions'] = ['1.21'];
      candidates.add({
        ...candidates.single,
        'id': 43,
        'classId': 12,
        'slug': 'wrong-section',
      });
      files[43] = [
        {...files[42]!.single, 'modId': 43},
      ];
      final out = await run(extra: '    accepts_mc: ["1.21"]');
      expect(out.stderr, isEmpty);
      final search = requests.singleWhere(
        (u) => u.queryParameters.containsKey('searchFilter'),
      );
      expect(search.queryParameters['classId'], '6');
      final fileRequests = requests.where((u) => u.path.endsWith('/42/files'));
      expect(fileRequests, isNotEmpty);
      expect(
        fileRequests.every((u) => u.queryParameters['modLoaderType'] == '6'),
        isTrue,
      );
      expect(requests.where((u) => u.path.endsWith('/43/files')), isEmpty);
    },
  );

  test('Folia entries never attempt CurseForge search', () async {
    mr.versions['anchor']!.single['loaders'] = ['folia'];
    final out = await run(
      section: 'plugins',
      pluginLoader: '  plugins: "folia:100"',
    );
    expect(out.stderr, isEmpty);
    expect(requests, isEmpty);
  });

  test('hash-selected older MR version re-solves its dependencies', () async {
    mr.registerVersion(slug: 'anchor', versionNumber: '2.0.0');
    mr.registerVersion(slug: 'old-child', versionNumber: '1.0.0');
    mr.projects['old-child'] = {
      'id': 'old-child_ID',
      'slug': 'old-child',
      'title': 'Child',
      'project_type': 'mod',
    };
    mr.versions['anchor']!.first['dependencies'] = [
      {'project_id': 'old-child_ID', 'dependency_type': 'required'},
    ];
    final out = await run(dryRun: false);
    expect(out.exitCode, 0, reason: out.stderr);
    final lock = File(p.join(root.path, 'mods.lock')).readAsStringSync();
    expect(lock, contains('version_id: anchor_1_0_0'));
    expect(lock, contains('  old-child:'));
    expect(lock, contains('name: anchor-1.0.0.jar'));
    expect(lock, isNot(contains('anchor-2.0.0.jar')));
  });

  test('hash-selected older CF file replaces its dependency graph', () async {
    final rootFile = files[42]!.single;
    exactProjects = [
      ...candidates,
      {...candidates.single, 'id': 43, 'slug': 'old-cf-child'},
      {...candidates.single, 'id': 44, 'slug': 'new-cf-child'},
    ];
    files[43] = [
      {...rootFile, 'id': 43, 'modId': 43, 'fileName': 'old-child.jar'},
    ];
    files[44] = [
      {...rootFile, 'id': 44, 'modId': 44, 'fileName': 'new-child.jar'},
    ];
    files[42] = [
      {
        ...rootFile,
        'id': 8,
        'fileDate': '2027-01-01T00:00:00Z',
        'hashes': [
          {'algo': 1, 'value': 'different'},
        ],
        'dependencies': [
          {'modId': 44, 'relationType': 3},
        ],
      },
      {
        ...rootFile,
        'dependencies': [
          {'modId': 43, 'relationType': 3},
        ],
      },
    ];
    final out = await run(dryRun: false, flags: ['--no-search']);
    expect(out.exitCode, 0, reason: out.stderr);
    final lock = File(p.join(root.path, 'mods.lock')).readAsStringSync();
    expect(lock, contains('  old-cf-child:'));
    expect(lock, isNot(contains('  new-cf-child:')));
    expect(lock, contains('file_id: 7'));
  });

  test('hash scan cannot escape the manifest version constraint', () async {
    mr.registerVersion(slug: 'anchor', versionNumber: '2.0.0');
    final out = await run(constraint: '^2.0.0', dryRun: false);
    expect(out.exitCode, 2);
    expect(out.stdout, isNot(contains('via search')));
    expect(File(p.join(root.path, 'mods.lock')).existsSync(), isFalse);
  });

  test('hash selection preserves dependency version_id minimums', () async {
    mr.registerVersion(slug: 'child', versionNumber: '1.0.0');
    mr.registerVersion(slug: 'child', versionNumber: '2.0.0');
    mr.versions['anchor']!.single['dependencies'] = [
      {
        'project_id': 'child_ID',
        'version_id': 'child_2_0_0',
        'dependency_type': 'required',
      },
    ];
    exactProjects = [
      ...candidates,
      {...candidates.single, 'id': 43, 'slug': 'child'},
    ];
    files[42]!.single['dependencies'] = [
      {'modId': 43, 'relationType': 3},
    ];
    files[43] = [
      {
        ...files[42]!.single,
        'id': 43,
        'modId': 43,
        'dependencies': [],
        'displayName': '1.0.0',
        'hashes': [
          {
            'algo': 1,
            'value': sha1
                .convert(mr.artifacts['child/child-1.0.0.jar']!)
                .toString(),
          },
        ],
        'downloadUrl': '${mr.downloadBaseUrl}/child/child-1.0.0.jar',
      },
    ];
    final out = await run(dryRun: false, flags: ['--no-search']);
    expect(out.exitCode, 2, reason: '${out.stdout}\n${out.stderr}');
    expect(File(p.join(root.path, 'mods.lock')).existsSync(), isFalse);
  });

  test('hash scan cannot select a beta under channel release', () async {
    mr.versions['anchor']!.single['version_type'] = 'beta';
    mr.registerVersion(
      slug: 'anchor',
      versionNumber: '2.0.0',
      versionType: 'release',
    );
    final out = await run(extra: '    channel: release', dryRun: false);
    expect(out.exitCode, 2);
    expect(out.stdout, isNot(contains('via search')));
    expect(File(p.join(root.path, 'mods.lock')).existsSync(), isFalse);
  });

  test('hash mismatch also searches a different Modrinth project', () async {
    exactProjects = candidates;
    candidates = [];
    mr.registerVersion(
      slug: 'other',
      versionNumber: '2.0.0',
      requiredDeps: ['child'],
    );
    mr.registerVersion(slug: 'child', versionNumber: '1.0.0');
    mr.projects['other'] = {
      'id': 'other_ID',
      'slug': 'other',
      'title': 'Anchor',
      'project_type': 'mod',
    };
    mr.projects['child'] = {
      'id': 'child_ID',
      'slug': 'child',
      'title': 'Child',
      'project_type': 'mod',
    };
    final hashes =
        (mr.versions['other']!.single['files'] as List).single['hashes'] as Map;
    hashes['sha1'] = sha1
        .convert(mr.artifacts['other/other-2.0.0.jar']!)
        .toString();
    files[42]!.single['hashes'] = [
      {'algo': 1, 'value': hashes['sha1']},
    ];
    files[42]!.single['downloadUrl'] =
        '${mr.downloadBaseUrl}/other/other-2.0.0.jar';
    mr.searchHits = [
      {
        'project_id': 'other_ID',
        'slug': 'other',
        'title': 'Anchor',
        'author': 'Author',
        'project_type': 'mod',
        'categories': ['neoforge'],
      },
    ];
    final out = await run(dryRun: false);
    expect(out.exitCode, 0, reason: out.stderr);
    final lock = File(p.join(root.path, 'mods.lock')).readAsStringSync();
    expect(lock, contains('project_id: other_ID'));
    expect(lock, contains('  child:'));
    expect(mr.requestCounts['/v2/search'], 1);
  });

  test(
    'Modrinth slug fallback runs candidates through dependency solving',
    () async {
      exactProjects = candidates;
      mr.versions.remove('anchor');
      mr.registerVersion(
        slug: 'other',
        versionNumber: '1.0.0',
        requiredDeps: ['child'],
      );
      mr.registerVersion(slug: 'child', versionNumber: '1.0.0');
      mr.projects['other'] = {
        'id': 'other_ID',
        'slug': 'other',
        'title': 'Anchor',
        'project_type': 'mod',
      };
      mr.projects['child'] = {
        'id': 'child_ID',
        'slug': 'child',
        'title': 'Child',
        'project_type': 'mod',
      };
      (mr.versions['other']!.single['files'] as List).single['hashes']['sha1'] =
          files[42]!.single['hashes'][0]['value'];
      mr.searchHits = [
        {
          'project_id': 'other_ID',
          'slug': 'other',
          'title': 'Anchor',
          'author': 'Author',
          'project_type': 'mod',
          'categories': ['neoforge'],
        },
      ];
      final out = await run(dryRun: false);
      expect(out.exitCode, 0, reason: out.stderr);
      final lock = File(p.join(root.path, 'mods.lock')).readAsStringSync();
      expect(lock, contains('project_id: other_ID'));
      expect(lock, contains('discovered_via_search: true'));
      expect(lock, contains('  child:'));
      expect(mr.lastSearchQuery!['facets'], contains('versions:1.21.1'));
      expect(mr.lastSearchQuery!['facets'], contains('categories:neoforge'));
    },
  );
}
