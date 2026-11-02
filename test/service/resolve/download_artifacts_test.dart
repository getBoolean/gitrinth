import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/manifest_io.dart';
import 'package:gitrinth/src/service/resolve/download_artifacts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

ModsLock _lockWith(Map<String, LockedEntry> mods) => ModsLock(
  gitrinthVersion: '0.1.0',
  loader: const LoaderConfig(
    mods: ModLoader.fabric,
    modLoaderVersion: '0.16.0',
  ),
  mcVersion: '1.21.5',
  mods: mods,
);

void main() {
  late Directory tempDir;
  late Directory cacheDir;
  late GitrinthCache cache;
  late Downloader downloader;
  late ManifestIo io;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitrinth_dl_');
    cacheDir = Directory.systemTemp.createTempSync('gitrinth_dl_cache_');
    cache = GitrinthCache(root: cacheDir.path);
    cache.ensureRoot();
    final dio = Dio();
    downloader = Downloader(dio: dio, cache: cache);
    io = ManifestIo(directory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  group('downloadArtifacts', () {
    for (final scenario in [
      'valid cache',
      'corrupt cache',
      'corrupt download',
    ]) {
      test('CurseForge SHA1 verification: $scenario', () async {
        final good = [1, 2, 3, 4];
        final dest = File(
          cache.curseforgePath(projectId: 42, fileId: 7, filename: 'mod.jar'),
        );
        if (scenario != 'corrupt download') {
          dest.parent.createSync(recursive: true);
          dest.writeAsBytesSync(scenario == 'valid cache' ? good : [0]);
        }
        var requests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((req) async {
          requests++;
          req.response.add(scenario == 'corrupt download' ? [0] : good);
          await req.response.close();
        });
        final lock = _lockWith({
          'mod': LockedEntry(
            slug: 'mod',
            kind: LockedEntryKind.resolved,
            curseforge: LockedCurseforgeSource(
              projectId: 42,
              fileId: 7,
              file: LockedFile(
                name: 'mod.jar',
                url: 'http://127.0.0.1:${server.port}/mod.jar',
                sha1: sha1.convert(good).toString(),
              ),
            ),
          ),
        });
        final result = await downloadArtifacts(
          lock: lock,
          cache: cache,
          downloader: downloader,
          console: const Console(level: LogLevel.error),
          io: io,
          hostFor: (_, _) => 'unused',
        );
        if (scenario == 'corrupt download') {
          expect(result.errors, hasLength(1));
          expect(result.errors.single, contains('checksum mismatch'));
          expect(dest.existsSync(), isFalse);
        } else {
          expect(result.errors, isEmpty);
          expect(dest.readAsBytesSync(), good);
          expect(requests, scenario == 'valid cache' ? 0 : 1);
        }
      });
    }

    test('CurseForge entry with allowModDistribution=false aggregates an error '
        'and does not attempt a fetch', () async {
      final lock = _lockWith({
        'opaque': const LockedEntry(
          slug: 'opaque',
          kind: LockedEntryKind.resolved,
          curseforge: LockedCurseforgeSource(
            projectId: 99,
            fileId: 1,
            file: LockedFile(name: 'opaque.jar'),
            allowModDistribution: false,
          ),
        ),
      });
      final result = await downloadArtifacts(
        lock: lock,
        cache: cache,
        downloader: downloader,
        console: const Console(level: LogLevel.error),
        io: io,
        hostFor: (_, _) => 'https://api.modrinth.com/v2',
      );
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('CurseForge does not allow'));
      expect(result.downloaded, 0);
      expect(result.hits, 0);
    });

    test('kind:path entry pointing to existing file passes', () async {
      final localJar = File(p.join(tempDir.path, 'mods', 'local.jar'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0]);
      addTearDown(() {
        if (localJar.existsSync()) localJar.deleteSync();
      });
      final lock = _lockWith({
        'local': LockedEntry(
          slug: 'local',
          kind: LockedEntryKind.path,
          path: p.join('mods', 'local.jar'),
        ),
      });
      final result = await downloadArtifacts(
        lock: lock,
        cache: cache,
        downloader: downloader,
        console: const Console(level: LogLevel.error),
        io: io,
        hostFor: (_, _) => 'https://api.modrinth.com/v2',
      );
      expect(result.errors, isEmpty);
    });

    test(
      'kind:path entry pointing to a missing file aggregates an error',
      () async {
        final lock = _lockWith({
          'missing': const LockedEntry(
            slug: 'missing',
            kind: LockedEntryKind.path,
            path: 'mods/does-not-exist.jar',
          ),
        });
        final result = await downloadArtifacts(
          lock: lock,
          cache: cache,
          downloader: downloader,
          console: const Console(level: LogLevel.error),
          io: io,
          hostFor: (_, _) => 'https://api.modrinth.com/v2',
        );
        expect(result.errors, hasLength(1));
        expect(result.errors.first, contains('does-not-exist.jar'));
      },
    );

    test('resolved entry with no source blocks (defensive) is a no-op, '
        'not an error', () async {
      final lock = _lockWith({
        'empty': const LockedEntry(
          slug: 'empty',
          kind: LockedEntryKind.resolved,
        ),
      });
      final result = await downloadArtifacts(
        lock: lock,
        cache: cache,
        downloader: downloader,
        console: const Console(level: LogLevel.error),
        io: io,
        hostFor: (_, _) => 'https://api.modrinth.com/v2',
      );
      expect(result.errors, isEmpty);
      expect(result.downloaded, 0);
      expect(result.hits, 0);
    });

    test(
      'kind:url entry without urlFile is a no-op (existing behavior)',
      () async {
        final lock = _lockWith({
          'url-no-file': const LockedEntry(
            slug: 'url-no-file',
            kind: LockedEntryKind.url,
            url: 'https://example.com/x.jar',
          ),
        });
        final result = await downloadArtifacts(
          lock: lock,
          cache: cache,
          downloader: downloader,
          console: const Console(level: LogLevel.error),
          io: io,
          hostFor: (_, _) => 'https://api.modrinth.com/v2',
        );
        expect(result.errors, isEmpty);
      },
    );
  });
}
