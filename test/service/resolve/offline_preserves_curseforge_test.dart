import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/modrinth/version.dart' as modrinth;
import 'package:gitrinth/src/model/modrinth/version_file.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api_factory.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_auth_interceptor.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/manifest_io.dart';
import 'package:gitrinth/src/service/modrinth/modrinth_api_factory.dart';
import 'package:gitrinth/src/service/modrinth/modrinth_auth_interceptor.dart';
import 'package:gitrinth/src/service/paper_api_client.dart';
import 'package:gitrinth/src/service/resolve/mod_loader_version_resolver.dart';
import 'package:gitrinth/src/service/resolve/plugin_loader_version_resolver.dart';
import 'package:gitrinth/src/service/resolve/resolve_and_sync.dart';
import 'package:gitrinth/src/service/resolve/solve_report.dart';
import 'package:gitrinth/src/service/sponge_api_client.dart';
import 'package:gitrinth/src/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _console = Console(level: LogLevel.error);

/// Synthetic Modrinth artifact bytes; their sha512 anchors the lock so
/// the Downloader's existence-check accepts the cached file.
final Uint8List _modrinthBytes = Uint8List.fromList(
  List.generate(64, (i) => i & 0xff),
);
final String _modrinthSha512 = sha512.convert(_modrinthBytes).toString();

ModsLock _dualSourceLock({String? gitrinthVersion}) => ModsLock(
  gitrinthVersion: gitrinthVersion ?? '0.1.0',
  loader: const LoaderConfig(
    mods: ModLoader.neoforge,
    modLoaderVersion: '21.1.50',
  ),
  mcVersion: '1.21.1',
  mods: {
    'jei': LockedEntry(
      slug: 'jei',
      kind: LockedEntryKind.resolved,
      version: '15.3.0.4',
      modrinth: LockedModrinthSource(
        projectId: 'JEI_PID',
        versionId: 'JEI_VID',
        versionNumber: '15.3.0.4',
        file: LockedFile(
          name: 'jei-15.3.0.4.jar',
          url:
              'https://cdn.modrinth.com/data/JEI_PID/versions/JEI_VID/jei-15.3.0.4.jar',
          sha1: 'aabb1122',
          sha512: _modrinthSha512,
          size: _modrinthBytes.length,
        ),
        gameVersions: const ['1.21.1'],
      ),
      curseforge: const LockedCurseforgeSource(
        projectId: 238222,
        fileId: 5512345,
        slug: 'jei',
        // CurseForge's lock-builder branch never records `size`; mirror
        // that here so the prior lock and the rebuilt lock match.
        file: LockedFile(
          name: 'jei-15.3.0.4.jar',
          url: 'https://edge.forgecdn.net/files/5512/345/jei-15.3.0.4.jar',
          sha1: 'aabb1122',
        ),
        gameVersions: ['1.21.1'],
      ),
    ),
  },
);

void main() {
  group('synthesizeCfResolutionFromLock', () {
    test('rebuilds a CfResolvedEntry from a dual-source lock', () {
      final out = synthesizeCfResolutionFromLock(_dualSourceLock());

      expect(out.notFound, isEmpty);
      expect(out.resolved.keys, ['jei']);

      final entry = out.resolved['jei']!;
      expect(entry.slug, 'jei');
      expect(entry.section, Section.mods);
      expect(entry.project.id, 238222);
      expect(entry.project.slug, 'jei');
      expect(entry.project.allowModDistribution, isTrue);
      expect(entry.file.id, 5512345);
      expect(entry.file.modId, 238222);
      expect(entry.file.fileName, 'jei-15.3.0.4.jar');
      expect(
        entry.file.downloadUrl,
        'https://edge.forgecdn.net/files/5512/345/jei-15.3.0.4.jar',
      );
      expect(entry.file.sha1Hash, 'aabb1122');
      expect(entry.file.gameVersions, ['1.21.1']);
      expect(entry.candidates, hasLength(1));
      expect(entry.candidates.single.id, entry.file.id);
    });

    test('skips entries without a curseforge block', () {
      final lock = ModsLock(
        gitrinthVersion: '0.1.0',
        loader: const LoaderConfig(
          mods: ModLoader.neoforge,
          modLoaderVersion: '21.1.50',
        ),
        mcVersion: '1.21.1',
        mods: const {
          'mr-only': LockedEntry(
            slug: 'mr-only',
            kind: LockedEntryKind.resolved,
            modrinth: LockedModrinthSource(
              projectId: 'MR',
              versionId: 'V',
              file: LockedFile(name: 'mr-only.jar'),
            ),
          ),
        },
      );
      final out = synthesizeCfResolutionFromLock(lock);
      expect(out.resolved, isEmpty);
    });

    test('preserves allowModDistribution=false and a null download URL', () {
      final lock = ModsLock(
        gitrinthVersion: '0.1.0',
        loader: const LoaderConfig(
          mods: ModLoader.neoforge,
          modLoaderVersion: '21.1.50',
        ),
        mcVersion: '1.21.1',
        mods: const {
          'opaque': LockedEntry(
            slug: 'opaque',
            kind: LockedEntryKind.resolved,
            curseforge: LockedCurseforgeSource(
              projectId: 99,
              fileId: 1,
              slug: 'opaque',
              file: LockedFile(name: 'opaque.jar'),
              allowModDistribution: false,
            ),
          ),
        },
      );
      final out = synthesizeCfResolutionFromLock(lock);
      final entry = out.resolved['opaque']!;
      expect(entry.project.allowModDistribution, isFalse);
      expect(entry.file.downloadUrl, isNull);
      expect(entry.file.sha1Hash, isNull);
    });
  });

  group('resolveAndSync(offline: true) preserves CurseForge blocks', () {
    late Directory tempDir;
    late Directory cacheDir;
    late GitrinthCache cache;
    late ManifestIo io;
    late Downloader downloader;
    late ModrinthApiFactory mrFactory;
    late CurseForgeApiFactory cfFactory;
    late ModLoaderVersionResolver modLoaderResolver;
    late PluginLoaderVersionResolver pluginLoaderResolver;
    const unreachable = 'http://127.0.0.1:1';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gitrinth_off_cf_');
      cacheDir = Directory.systemTemp.createTempSync('gitrinth_off_cf_cache_');
      cache = GitrinthCache(root: cacheDir.path);
      cache.ensureRoot();
      io = ManifestIo(directory: tempDir);
      downloader = Downloader(dio: Dio(), cache: cache);
      mrFactory = ModrinthApiFactory(
        console: _console,
        auth: ModrinthAuthInterceptor(
          tokensProvider: () => const {},
          envTokenLookup: () => null,
          defaultBaseUrl: unreachable,
        ),
        offline: () => true,
        defaultBaseUrl: unreachable,
      );
      cfFactory = CurseForgeApiFactory(
        console: _console,
        auth: CurseForgeAuthInterceptor(
          envTokenLookup: () => null,
          baseUrl: unreachable,
          defaultKeyResolver: () => '',
        ),
        offline: () => true,
        baseUrl: unreachable,
      );
      modLoaderResolver = ModLoaderVersionResolver(dio: Dio());
      final pluginDio = Dio();
      pluginLoaderResolver = PluginLoaderVersionResolver(
        dio: pluginDio,
        paperApi: PaperApiClient(dio: pluginDio),
        spongeApi: SpongeApiClient(dio: pluginDio),
      );
    });

    tearDown(() {
      mrFactory.close();
      cfFactory.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });

    test(
      'CF block is re-emitted byte-for-byte and the artifact cache hits',
      () async {
        // 1. Hand-write mods.yaml. `gitrinth.curseforge: enabled` makes
        //    CF an effective source for jei.
        File(p.join(tempDir.path, 'mods.yaml')).writeAsStringSync('''
slug: testpack
name: TestPack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc_version: 1.21.1
gitrinth:
  curseforge: enabled
mods:
  jei: ^15.0.0
''');

        // 2. Hand-write a mods.lock containing both source blocks. Use
        //    the running packageVersion so the prior lock matches what
        //    buildLock will produce — otherwise the diff would be
        //    non-empty on a gitrinth-version line.
        final template = _dualSourceLock(gitrinthVersion: packageVersion);
        final cf = template.mods['jei']!.curseforge!;
        final priorLock = template.copyWith(
          mods: {
            'jei': template.mods['jei']!.copyWith(
              curseforge: cf.copyWith(
                file: cf.file.copyWith(
                  sha1: sha1.convert(const [0]).toString(),
                ),
              ),
            ),
          },
        );
        final priorLockText = emitModsLock(priorLock);
        File(
          p.join(tempDir.path, 'mods.lock'),
        ).writeAsStringSync(priorLockText);

        // 3. Pre-populate the cache. With files present the Downloader
        //    returns early without HTTP; without the version.json
        //    sidecar the offline Modrinth resolver finds no candidates.
        final mrEntry = priorLock.mods['jei']!.modrinth!;
        File(
            cache.modrinthPath(
              host: unreachable,
              projectId: mrEntry.projectId,
              versionId: mrEntry.versionId,
              filename: mrEntry.file.name,
            ),
          )
          ..createSync(recursive: true)
          ..writeAsBytesSync(_modrinthBytes);

        final cachedVersion = modrinth.Version(
          id: mrEntry.versionId,
          projectId: mrEntry.projectId,
          versionNumber: mrEntry.versionNumber!,
          files: [
            VersionFile(
              url: mrEntry.file.url!,
              filename: mrEntry.file.name,
              hashes: {
                if (mrEntry.file.sha1 != null) 'sha1': mrEntry.file.sha1!,
                'sha512': mrEntry.file.sha512!,
              },
              size: mrEntry.file.size!,
              primary: true,
            ),
          ],
          dependencies: const [],
          loaders: const ['neoforge'],
          gameVersions: const ['1.21.1'],
          versionType: 'release',
        );
        File(
            cache.modrinthVersionMetadataPath(
              host: unreachable,
              projectId: mrEntry.projectId,
              versionId: mrEntry.versionId,
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(cachedVersion.toMap()));

        final cfEntry = priorLock.mods['jei']!.curseforge!;
        File(
            cache.curseforgePath(
              projectId: cfEntry.projectId,
              fileId: cfEntry.fileId,
              filename: cfEntry.file.name,
            ),
          )
          ..createSync(recursive: true)
          ..writeAsBytesSync(const [0]);

        // 4. Run the offline resolve.
        final result = await resolveAndSync(
          io: io,
          console: _console,
          apiFactory: mrFactory,
          cfFactory: cfFactory,
          cache: cache,
          downloader: downloader,
          modLoaderResolver: modLoaderResolver,
          pluginLoaderResolver: pluginLoaderResolver,
          offline: true,
        );

        // 5. The CF source block survives byte-for-byte.
        final newLock = result.newLock!;
        final jei = newLock.mods['jei']!;
        expect(jei.curseforge, isNotNull);
        expect(jei.curseforge!.projectId, cfEntry.projectId);
        expect(jei.curseforge!.fileId, cfEntry.fileId);
        expect(jei.curseforge!.file.sha1, cfEntry.file.sha1);
        expect(jei.curseforge!.file.name, cfEntry.file.name);
        expect(jei.curseforge!.file.url, cfEntry.file.url);
        expect(jei.curseforge!.gameVersions, cfEntry.gameVersions);
        expect(jei.curseforge!.allowModDistribution, isTrue);

        // The Modrinth block also survives.
        expect(jei.modrinth, isNotNull);
        expect(jei.modrinth!.projectId, mrEntry.projectId);
        expect(jei.modrinth!.versionId, mrEntry.versionId);

        // 6. Diff is empty — the lock is byte-stable across the
        //    round-trip.
        final changes = result.diff
            .where((d) => d.kind != DiffKind.unchanged)
            .toList();
        expect(
          changes,
          isEmpty,
          reason:
              'offline resolve should not change a complete lock; got: '
              '${changes.map((c) => "${c.kind.name} ${c.section.name}/${c.slug}").join(", ")}',
        );

        // 7. mods.lock on disk is byte-identical.
        final reReadText = File(
          p.join(tempDir.path, 'mods.lock'),
        ).readAsStringSync();
        expect(reReadText, priorLockText);
      },
    );
  });
}
