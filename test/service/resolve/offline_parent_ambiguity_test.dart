import 'dart:io';

import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';

import '../../helpers/capture.dart';

void main() {
  test(
    'offline removal cannot guess a colliding parent or overwrite the lock',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'offline_parent_ambiguity_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/mods.yaml').writeAsStringSync('''
slug: pack
name: Pack
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'fabric:0.16.0'}
gitrinth: {modrinth: disabled, curseforge: enabled}
resource_packs:
  root:
''');
      LockedEntry entry(String slug, int id, {bool transitive = false}) =>
          LockedEntry(
            slug: slug,
            kind: LockedEntryKind.resolved,
            version: '1.0.0',
            dependency: transitive
                ? LockedDependencyKind.transitive
                : LockedDependencyKind.direct,
            requiredBy: transitive ? ['root'] : [],
            curseforge: LockedCurseforgeSource(
              projectId: id,
              fileId: id,
              file: LockedFile(name: '$id.jar'),
              gameVersions: ['1.21.1'],
            ),
          );
      final lock = File('${root.path}/mods.lock');
      final before = emitModsLock(
        ModsLock(
          gitrinthVersion: '0.1.0',
          mcVersion: '1.21.1',
          loader: const LoaderConfig(
            mods: ModLoader.fabric,
            modLoaderVersion: '0.16.0',
          ),
          mods: {
            'root': entry('root', 1),
            'library': entry('library', 3, transitive: true),
          },
          resourcePacks: {'root': entry('root', 2)},
        ),
      );
      lock.writeAsStringSync(before);
      final result = await runCli(
        ['-C', root.path, 'get', '--offline'],
        environment: {
          'GITRINTH_CACHE': '${root.path}/cache',
          'GITRINTH_CONFIG': '${root.path}/config.yaml',
        },
      );
      expect(result.exitCode, isNot(0));
      expect(lock.readAsStringSync(), before);
      expect(result.stderr, contains('Ambiguous required_by'));
    },
  );
}
