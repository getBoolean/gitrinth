import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  test(
    'a newly discovered loader resolves and packs while runtime remains explicit',
    () async {
      final root = Directory.systemTemp.createTempSync('future_loader_');
      final api = FakeModrinth();
      await api.start();
      addTearDown(() async {
        await api.stop();
        root.deleteSync(recursive: true);
      });
      api.registerVersion(
        slug: 'demo',
        versionNumber: '1.0.0',
        loader: 'future-runtime',
      );
      final version = api.versions['demo']!.single;
      final file = (version['files'] as List).single as Map;
      (file['hashes'] as Map)['sha1'] = sha1
          .convert(api.artifacts.values.single)
          .toString();
      api.loaderTags.add({
        'name': 'future-runtime',
        'supported_project_types': ['mod', 'modpack'],
        'icon': '',
      });
      File(p.join(root.path, 'mods.yaml')).writeAsStringSync('''
slug: future
name: Future
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'future-runtime:1.2.3'}
mods: {demo: null}
publish_to: modrinth
''');
      final environment = {
        'GITRINTH_CACHE': p.join(root.path, 'cache'),
        'GITRINTH_CONFIG': p.join(root.path, 'config.yaml'),
        'GITRINTH_MODRINTH_URL': api.baseUrl,
        'GITRINTH_TOKEN': 'fixture-token',
      };
      final get = await runCli([
        '-C',
        root.path,
        'get',
      ], environment: environment);
      expect(get.exitCode, 0, reason: '${get.stdout}\n${get.stderr}');
      expect(api.lastVersionQuery['demo']?['loaders'], '["future-runtime"]');
      final unsupported = await runCli([
        '-C',
        root.path,
        'pack',
        '--offline',
      ], environment: environment);
      expect(unsupported.exitCode, 2);
      expect(unsupported.stderr, contains('archive metadata capability'));
      final descriptors = File(p.join(root.path, 'user', 'loaders.yaml'));
      descriptors.parent.createSync(recursive: true);
      descriptors.writeAsStringSync(
        "version: 1\nloaders:\n  future-runtime:\n    role: mod\n    modrinth: {${api.baseUrl}: future-runtime}\n    archive: {modrinth: future-runtime}\n",
      );
      final packed = await runCli([
        '-C',
        root.path,
        'pack',
        '--offline',
        '--loader-descriptors',
        descriptors.path,
      ], environment: environment);
      expect(packed.exitCode, 0, reason: '${packed.stdout}\n${packed.stderr}');
      final archive = ZipDecoder().decodeBytes(
        File(
          p.join(root.path, 'build', 'future-1.0.0.mrpack'),
        ).readAsBytesSync(),
      );
      final index = jsonDecode(
        utf8.decode(archive.findFile('modrinth.index.json')!.content),
      );
      expect(index['dependencies'], {
        'minecraft': '1.21.1',
        'future-runtime': '1.2.3',
      });
      final publish = await runCli([
        '-C',
        root.path,
        'publish',
        '--dry-run',
        '--loader-descriptors',
        descriptors.path,
      ], environment: environment);
      expect(
        publish.exitCode,
        0,
        reason: '${publish.stdout}\n${publish.stderr}',
      );
      expect(publish.stdout, contains('future-runtime'));
      final untouched = Directory(p.join(root.path, 'runtime-output'));
      final build = await runCli([
        '-C',
        root.path,
        'build',
        'server',
        '--output',
        untouched.path,
        '--offline',
        '--loader-descriptors',
        descriptors.path,
      ], environment: environment);
      expect(build.exitCode, 2, reason: build.stderr);
      expect(build.stderr, contains('adapter'));
      expect(untouched.existsSync(), isFalse);
    },
  );
}
