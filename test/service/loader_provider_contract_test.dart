import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/curseforge_pack_assembler.dart';
import 'package:gitrinth/src/commands/pack_assembler.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_filters.dart';
import 'package:gitrinth/src/service/loader_descriptor_config.dart';
import 'package:test/test.dart';

void main() {
  test(
    'explicit descriptor type and archive token flow without an enum case',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dio = Dio();
      addTearDown(() async {
        dio.close(force: true);
        await server.close(force: true);
      });
      final registry = LoaderDescriptorConfig.parse('''
version: 1
loaders:
  future:
    role: mod
    curseforge_type: 42
    archive: {curseforge: official-future}
''');
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.uri.path, '/v1/mods/7/files');
        expect(request.uri.queryParameters['modLoaderType'], '42');
        expect(request.uri.queryParameters['gameVersion'], '1.21.1');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'id': 70,
                'modId': 7,
                'displayName': '1.0.0',
                'fileName': 'mod.jar',
                'releaseType': 1,
                'fileDate': '2026-01-01',
                'gameVersions': ['1.21.1'],
                'hashes': [],
                'dependencies': [],
              },
            ],
            'pagination': {
              'index': 0,
              'pageSize': 50,
              'resultCount': 1,
              'totalCount': 1,
            },
          }),
        );
        await request.response.close();
      });
      final api = CurseForgeApi(
        dio,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      final files = await listCompatibleFiles(
        api: api,
        registry: registry,
        projectId: 7,
        section: Section.mods,
        modLoader: LoaderId('future'),
        gameVersions: ['1.21.1'],
        channel: Channel.release,
      );
      expect(files.single.id, 70);
      expect(requests, 1);
      final loader = LoaderConfig(
        mods: LoaderId('future'),
        modLoaderVersion: '1.0.0',
      );
      final manifest = buildCurseForgeManifest(
        yaml: ModsYaml(
          slug: 'test',
          name: 'Test',
          version: '1.0.0',
          description: '',
          mcVersion: '1.21.1',
          loader: loader,
        ),
        lock: ModsLock(
          gitrinthVersion: '0.1.0',
          mcVersion: '1.21.1',
          loader: loader,
        ),
        target: PackTarget.client,
        publishable: false,
        registry: registry,
      );
      expect((manifest['minecraft'] as Map)['modLoaders'], [
        {'id': 'official-future-1.0.0', 'primary': true},
      ]);

      final mrOnly = LoaderRegistry([
        LoaderDescriptor(
          id: LoaderId('mr-only'),
          role: LoaderRole.mod,
          modrinthTags: {'*': 'mr-only'},
        ),
      ]);
      await expectLater(
        listCompatibleFiles(
          api: api,
          registry: mrOnly,
          projectId: 7,
          section: Section.mods,
          modLoader: LoaderId('mr-only'),
          gameVersions: ['1.21.1'],
          channel: Channel.release,
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('no CurseForge numeric filter mapping'),
          ),
        ),
      );
      expect(requests, 1);
    },
  );
}
