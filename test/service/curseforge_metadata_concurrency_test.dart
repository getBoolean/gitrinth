import 'dart:io';
import 'dart:isolate';

import 'package:gitrinth/src/model/curseforge/cf_mod_file.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_metadata_store.dart';
import 'package:test/test.dart';

void _writeMetadata(List<Object> args) {
  final result = args[0] as SendPort;
  final store = CurseForgeMetadataStore(GitrinthCache(root: args[1] as String));
  try {
    for (var i = 0; i < 100; i++) {
      store.write(
        ModFile(
          id: 10,
          modId: 1,
          displayName: '${args[2]}-$i',
          fileName: 'artifact.jar',
          releaseType: 1,
          fileDate: '2026-01-01',
          gameVersions: ['1.21.1'],
          hashes: [],
          dependencies: [],
        ),
      );
    }
    result.send(null);
  } on Object catch (error) {
    result.send(error.toString());
  }
}

void main() {
  test(
    'concurrent selected-metadata writers never collide on staging files',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'cf_metadata_concurrency_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final results = ReceivePort();
      addTearDown(results.close);
      await Future.wait([
        for (var i = 0; i < 4; i++)
          Isolate.spawn(_writeMetadata, <Object>[
            results.sendPort,
            root.path,
            i,
          ]),
      ]);
      final errors = await results.take(4).toList();
      expect(errors, everyElement(isNull));
      final file = CurseForgeMetadataStore(
        GitrinthCache(root: root.path),
      ).read(projectId: 1, fileId: 10);
      expect(file.fileName, 'artifact.jar');
      expect(
        Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => path.contains('.tmp')),
        isEmpty,
      );
    },
  );
}
