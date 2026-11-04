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
  late List<Uri> requests;
  var cfPresent = true;
  var cfHash = 'same';
  var classId = 6;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('gitrinth_bridge_cli_');
    mr = FakeModrinth();
    await mr.start();
    requests = [];
    cfPresent = true;
    cfHash = 'same';
    classId = 6;
    cf = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cf.listen((request) async {
      requests.add(request.uri);
      final project = {
        'id': 1,
        'gameId': 432,
        'name': 'Example',
        'slug': 'example',
        'classId': classId,
      };
      final file = {
        'id': 10,
        'modId': 1,
        'displayName': '1.2.3',
        'fileName': 'example-1.2.3.jar',
        'releaseType': 1,
        'fileDate': '2026-01-01',
        'gameVersions': ['1.21.1'],
        'hashes': [
          {'value': cfHash, 'algo': 1},
        ],
        'dependencies': [],
        'downloadUrl': '${mr.downloadBaseUrl}/example/example-1.2.3.jar',
      };
      final path = request.uri.path;
      final list = path.endsWith('/search')
          ? cfPresent && (request.uri.queryParameters['classId'] == '$classId')
                ? [project]
                : []
          : [file];
      final body = path.endsWith('/files/10')
          ? {'data': file}
          : path == '/v1/mods/1'
          ? {'data': project}
          : {
              'data': list,
              'pagination': {
                'index': 0,
                'pageSize': 50,
                'resultCount': list.length,
                'totalCount': list.length,
              },
            };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
  });
  tearDown(() async {
    await cf.close(force: true);
    await mr.stop();
    root.deleteSync(recursive: true);
  });
  File getYaml() => File(p.join(root.path, 'mods.yaml'));
  void manifest({
    String platforms = '',
    String loader = 'mods: "neoforge:21.1.50"',
  }) {
    getYaml().writeAsStringSync(
      'slug: pack\nname: Pack\nversion: 1.0.0\ndescription: x\nmc_version: 1.21.1\nloader: {$loader}\n$platforms',
    );
  }

  Map<String, String> env() => {
    'GITRINTH_MODRINTH_URL': mr.baseUrl,
    'GITRINTH_CURSEFORGE_URL': 'http://127.0.0.1:${cf.port}',
    'GITRINTH_CURSEFORGE_TOKEN': 'test',
    'GITRINTH_CACHE': p.join(root.path, 'cache'),
    'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
    'GITRINTH_NEOFORGE_VERSIONS_URL': mr.neoforgeVersionsUrl,
    'GITRINTH_PAPER_API_URL': mr.paperBuildsUrl,
  };
  Future<dynamic> add(List<String> args) =>
      runCli(['-C', root.path, 'add', ...args], environment: env());
  void registerMr({String hash = 'same'}) {
    mr.registerVersion(
      slug: 'example',
      versionNumber: '1.2.3',
      versionType: 'release',
    );
    (mr.versions['example']!.first['files'] as List).first['hashes']['sha1'] =
        hash;
  }

  test('toggles preserve version, comments and entries without HTTP', () async {
    manifest(
      platforms:
          'gitrinth:\n  version: ^0.1.0 # retained\nmods:\n  existing: release\n',
    );
    for (final platform in ['curseforge', 'modrinth']) {
      for (final action in ['enable', 'disable']) {
        final result = await runCli([
          '-C',
          root.path,
          platform,
          action,
        ], environment: env());
        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          getYaml().readAsStringSync(),
          contains('version: ^0.1.0 # retained'),
        );
      }
    }
    expect(requests, isEmpty);
  });
  test('top-level token stores CF publish credential without HTTP', () async {
    final result = await runCli([
      'token',
      'add',
      'curseforge.com',
      '--token',
      'secret-publish-value',
    ], environment: env());
    expect(result.exitCode, 0, reason: result.stderr);
    final list = await runCli(['token', 'list'], environment: env());
    expect(list.stdout, contains('https://curseforge.com'));
    expect(list.stdout, isNot(contains('secret-publish-value')));
    final removed = await runCli([
      'token',
      'remove',
      'curseforge.com',
    ], environment: env());
    expect(removed.exitCode, 0);
    expect(requests, isEmpty);
  });
  for (final type in {
    'mod': 6,
    'resourcepack': 12,
    'datapack': 6945,
    'shader': 6552,
    'plugin': 5,
  }.entries) {
    test('cf sugar supports ${type.key} without Modrinth queries', () async {
      classId = type.value;
      manifest(
        loader: type.key == 'plugin'
            ? 'plugins: "paper:100"'
            : type.key == 'shader'
            ? 'mods: "neoforge:21.1.50", shaders: iris'
            : 'mods: "neoforge:21.1.50"',
      );
      final result = await add([
        'cf:example',
        '--type',
        type.key,
        '--dry-run',
        '--no-search',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(result.stdout, contains('sources: curseforge'));
      expect(result.stdout, contains('version: ^1.2.3'));
      expect(
        mr.requestCounts.keys.where((x) => x.contains('/project/')),
        isEmpty,
      );
      expect(getYaml().readAsStringSync(), isNot(contains('example')));
    });
  }
  test('Folia CF request fails before network', () async {
    manifest(loader: 'plugins: "folia:42"');
    final result = await add(['cf:example', '--type', 'plugin', '--dry-run']);
    expect(result.exitCode, isNot(0));
    expect(requests, isEmpty);
    expect(result.stderr, contains('CurseForge plugins require'));
  });
  test('platform modifiers reject manual sources before HTTP', () async {
    manifest();
    for (final flag in [
      '--curseforge',
      '--no-modrinth',
      '--allow-hash-mismatch',
    ]) {
      final result = await add([
        'example',
        '--url',
        'https://example.com/a.jar',
        flag,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Platform options cannot be combined'));
    }
    expect(requests, isEmpty);
    expect(mr.requestCounts, isEmpty);
  });
  test('CF sugar enforces explicit version constraints atomically', () async {
    manifest();
    final before = getYaml().readAsStringSync();
    final rejected = await add([
      'cf:example@^2.0.0',
      '--type',
      'mod',
      '--dry-run',
    ]);
    expect(rejected.exitCode, isNot(0));
    expect(getYaml().readAsStringSync(), before);
    final accepted = await add([
      'cf:example@^1.2.0',
      '--type',
      'mod',
      '--dry-run',
    ]);
    expect(
      accepted.exitCode,
      0,
      reason: '${accepted.stderr}\n${accepted.stdout}',
    );
    expect(accepted.stdout, contains('version: ^1.2.0'));
  });
  test('dual matches write shorthand on dry run', () async {
    manifest(platforms: 'gitrinth: {curseforge: enabled}\n');
    registerMr();
    final result = await add(['example', '--dry-run', '--no-search']);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    expect(result.stdout, contains('example: ^1.2.3'));
    expect(result.stdout, isNot(contains('sources:')));
  });
  test('CF-only add writes its source and a usable lock', () async {
    manifest();
    registerMr();
    cfHash = sha1.convert(mr.artifacts.values.first).toString();
    final result = await add(['cf:example', '--type', 'mod', '--no-search']);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    final text = getYaml().readAsStringSync();
    expect(text, contains('sources: curseforge'));
    expect(text, contains('version: ^1.2.3'));
    expect(
      File(p.join(root.path, 'mods.lock')).readAsStringSync(),
      contains('file_id: 10'),
    );
    expect(
      mr.requestCounts.keys.where((x) => x.contains('/project/')),
      isEmpty,
    );
  });
  test('older matching hash pair determines the written constraint', () async {
    manifest(platforms: 'gitrinth: {curseforge: enabled}\n');
    registerMr();
    mr.registerVersion(
      slug: 'example',
      versionNumber: '2.0.0',
      versionType: 'release',
    );
    (mr.versions['example']!.last['files'] as List).first['hashes']['sha1'] =
        'newer-different';
    final result = await add(['example', '--dry-run', '--no-search']);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    expect(result.stdout, contains('example: ^1.2.3'));
    expect(result.stdout, contains('2.0.0'));
    expect(
      requests.where((uri) => uri.queryParameters.containsKey('searchFilter')),
      isEmpty,
    );
  });
  test('missing CF restricts automatic add', () async {
    manifest(platforms: 'gitrinth: {curseforge: enabled}\n');
    registerMr();
    cfPresent = false;
    final result = await add(['example', '--dry-run', '--no-search']);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    expect(result.stdout, contains('sources: [modrinth]'));
  });
  test('missing Modrinth restricts automatic add to CF', () async {
    manifest(platforms: 'gitrinth: {curseforge: enabled}\n');
    final result = await add([
      'example',
      '--type',
      'mod',
      '--dry-run',
      '--no-search',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    expect(result.stdout, contains('sources: [curseforge]'));
  });
  test('neither platform available leaves manifest unchanged', () async {
    manifest(platforms: 'gitrinth: {curseforge: enabled}\n');
    cfPresent = false;
    final before = getYaml().readAsStringSync();
    final result = await add(['example', '--type', 'mod', '--no-search']);
    expect(result.exitCode, isNot(0));
    expect(getYaml().readAsStringSync(), before);
  });
  test('hosted Modrinth uses its host for matching and constraint', () async {
    final hosted = FakeModrinth();
    await hosted.start();
    try {
      hosted.registerVersion(
        slug: 'example',
        versionNumber: '2.0.0',
        versionType: 'release',
      );
      (hosted.versions['example']!.first['files'] as List)
              .first['hashes']['sha1'] =
          'same';
      manifest(
        platforms:
            'gitrinth: {curseforge: enabled}\nmodrinth_host: ${hosted.baseUrl}\n',
      );
      final result = await add(['example', '--dry-run', '--no-search']);
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(result.stdout, contains('example: ^2.0.0'));
      expect(
        mr.requestCounts.keys.where((x) => x.contains('/project/')),
        isEmpty,
      );
    } finally {
      await hosted.stop();
    }
  });
  test('mismatch is atomic and opt-in records modifier', () async {
    manifest(platforms: 'gitrinth: {curseforge: enabled}\n');
    registerMr();
    cfHash = 'different';
    final before = getYaml().readAsStringSync();
    final failed = await add(['example', '--no-search']);
    expect(failed.exitCode, isNot(0));
    expect(getYaml().readAsStringSync(), before);
    final allowed = await add([
      'example',
      '--allow-hash-mismatch',
      '--dry-run',
      '--no-search',
    ]);
    expect(allowed.exitCode, 0, reason: '${allowed.stderr}\n${allowed.stdout}');
    expect(allowed.stdout, contains('allow_hash_mismatch: true'));
  });
  test('explicit no-CF preserves a visible one-sided restriction', () async {
    manifest(platforms: 'gitrinth: {curseforge: enabled}\n');
    registerMr();
    final result = await add(['example', '--no-curseforge', '--dry-run']);
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('sources: [modrinth]'));
    expect(requests, isEmpty);
  });
}
