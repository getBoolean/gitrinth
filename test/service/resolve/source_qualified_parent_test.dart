import 'dart:io';

import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_metadata_store.dart';
import 'package:crypto/crypto.dart';
import 'package:gitrinth/src/service/resolve/lock_graph.dart';
import 'package:gitrinth/src/service/resolve/resolve_and_sync.dart';
import 'package:gitrinth/src/service/source_identity.dart';
import 'package:test/test.dart';

import '../../helpers/capture.dart';

void main() {
  test(
    'CF-only parent uses source evidence in offline get and dependency reports',
    () async {
      final root = Directory.systemTemp.createTempSync('source_parent_');
      addTearDown(() => root.deleteSync(recursive: true));
      final cache = GitrinthCache(root: '${root.path}/cache');
      LockedEntry cf(String slug, int id, {bool child = false}) => LockedEntry(
        slug: slug,
        kind: LockedEntryKind.resolved,
        version: '1.0.0',
        dependency: child
            ? LockedDependencyKind.transitive
            : LockedDependencyKind.direct,
        requiredBy: child ? ['root'] : [],
        curseforge: LockedCurseforgeSource(
          projectId: id,
          fileId: id,
          file: LockedFile(name: '$id.jar', sha1: sha1.convert([1]).toString()),
          gameVersions: ['1.21.1'],
        ),
      );
      final before = ModsLock(
        gitrinthVersion: '0.1.0',
        loader: const LoaderConfig(
          mods: ModLoader.fabric,
          modLoaderVersion: '0.16.0',
        ),
        mcVersion: '1.21.1',
        mods: {
          'root': const LockedEntry(
            slug: 'root',
            kind: LockedEntryKind.resolved,
            modrinth: LockedModrinthSource(
              projectId: 'mr-only',
              versionId: 'v1',
              file: LockedFile(name: 'mr.jar'),
            ),
          ),
          'library': cf('library', 3, child: true),
        },
        resourcePacks: {'root': cf('root', 2)},
      );
      for (final id in [2, 3]) {
        final file = File(
          cache.curseforgePath(projectId: id, fileId: id, filename: '$id.jar'),
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync([1]);
      }
      for (final entry in synthesizeCfResolutionFromLock(
        before,
      ).resolved.values) {
        CurseForgeMetadataStore(cache).write(entry.file);
      }
      final graph = LockedDependencyGraph(
        before,
        cache,
        defaultHost: 'https://default.example/v2',
      );
      expect(graph.diagnostics, isEmpty);
      expect(
        graph.graph.parents(const LocalEntryKey(Section.mods, 'library')),
        {const LocalEntryKey(Section.resourcePacks, 'root')},
      );
      File('${root.path}/mods.lock').writeAsStringSync(emitModsLock(before));
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
      final result = await runCli(
        ['-C', root.path, 'get', '--offline'],
        environment: {
          'GITRINTH_CACHE': cache.root,
          'GITRINTH_CONFIG': '${root.path}/config.yaml',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final after = parseModsLock(
        File('${root.path}/mods.lock').readAsStringSync(),
        filePath: 'mods.lock',
      );
      expect(after.mods.keys, ['library']);
      expect(after.mods['library']!.requiredBy, ['root']);
      expect(after.resourcePacks['root']!.curseforge!.projectId, 2);
      final mixed = before.copyWith(
        mods: {
          ...before.mods,
          'library': before.mods['library']!.copyWith(
            modrinth: const LockedModrinthSource(
              projectId: 'library-mr',
              versionId: 'v1',
              host: 'https://other.example/v2',
              file: LockedFile(name: 'library.jar'),
            ),
          ),
        },
      );
      final retained = synthesizeCfResolutionFromLock(
        mixed,
        manifest: parseModsYaml(
          File('${root.path}/mods.yaml').readAsStringSync(),
          filePath: 'mods.yaml',
        ),
      );
      expect(
        retained.resolved.keys,
        contains(const LocalEntryKey(Section.mods, 'library')),
      );
    },
  );
}
