import 'package:dio/dio.dart';
import 'package:gitrinth/src/model/curseforge/cf_constants.dart';
import 'package:gitrinth/src/model/curseforge/cf_file_hash.dart';
import 'package:gitrinth/src/model/curseforge/cf_mod.dart';
import 'package:gitrinth/src/model/curseforge/cf_mod_file.dart';
import 'package:gitrinth/src/model/curseforge/cf_search_response.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api.dart';
import 'package:gitrinth/src/service/resolve/curseforge_resolver.dart';
import 'package:test/test.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/source_identity.dart';
import 'package:gitrinth/src/service/resolve/lock_builder.dart';
import 'package:gitrinth/src/service/resolve/resolve_and_sync.dart';
import 'package:gitrinth/src/model/resolver/result.dart';

class _FakeCfApi implements CurseForgeApi {
  /// slug → Mod (or null to simulate not-found)
  final Map<String, Mod?> projectsBySlug;

  /// projectId → list of ModFiles (paginated transparently)
  final Map<int, List<ModFile>> filesByProject;

  /// id → Mod for getMod()
  final Map<int, Mod> modsById;
  final Object? lookupError;
  final Object? listingError;

  final List<String> calls = [];
  final List<String?> requestedGameVersions = [];

  _FakeCfApi({
    this.projectsBySlug = const {},
    this.filesByProject = const {},
    this.modsById = const {},
    this.lookupError,
    this.listingError,
  });

  @override
  Future<ModSearchResponse> searchMods({
    required int gameId,
    int? classId,
    String? slug,
    String? searchFilter,
    int? index,
    int? pageSize,
  }) async {
    calls.add('searchMods($slug)');
    final error = lookupError;
    if (error != null) throw error;
    final found = projectsBySlug[slug];
    return ModSearchResponse(
      data: found == null ? const [] : [found],
      pagination: Pagination(
        index: 0,
        pageSize: pageSize ?? 0,
        resultCount: found == null ? 0 : 1,
        totalCount: found == null ? 0 : 1,
      ),
    );
  }

  @override
  Future<ModEnvelope> getMod(int id) async {
    calls.add('getMod($id)');
    final m = modsById[id];
    if (m == null) throw StateError('no fake mod for id=$id');
    return ModEnvelope(data: m);
  }

  @override
  Future<ModFileSearchResponse> listFiles(
    int modId, {
    String? gameVersion,
    int? modLoaderType,
    int? index,
    int? pageSize,
  }) async {
    calls.add('listFiles($modId)');
    requestedGameVersions.add(gameVersion);
    final error = listingError;
    if (error != null) throw error;
    final files = filesByProject[modId] ?? const [];
    return ModFileSearchResponse(
      data: files,
      pagination: Pagination(
        index: 0,
        pageSize: pageSize ?? 50,
        resultCount: files.length,
        totalCount: files.length,
      ),
    );
  }

  @override
  Future<ModFileEnvelope> getFile(int modId, int fileId) async {
    throw UnimplementedError();
  }
}

ModFile _file({
  required int id,
  required int modId,
  required String fileName,
  required String fileDate,
  int releaseType = 1, // release
  List<String> gameVersions = const ['1.21.5'],
  String? sha1,
  String? downloadUrl = 'https://example.com/x.jar',
}) => ModFile(
  id: id,
  modId: modId,
  displayName: fileName,
  fileName: fileName,
  releaseType: releaseType,
  fileDate: fileDate,
  gameVersions: gameVersions,
  hashes: sha1 == null ? const [] : [FileHash(value: sha1, algoCode: 1)],
  dependencies: const [],
  downloadUrl: downloadUrl,
);

ModsYaml _pack({
  ModLoader mods = ModLoader.fabric,
  PluginLoader? plugins,
  GitrinthPlatformState curseforge = GitrinthPlatformState.enabled,
  Map<String, ModEntry> modsMap = const {},
  Map<String, ModEntry> pluginsMap = const {},
}) => ModsYaml(
  slug: 'pack',
  name: 'pack',
  version: '0.0.1',
  description: '',
  loader: LoaderConfig(
    mods: mods,
    modLoaderVersion: '0.16.0',
    plugins: plugins,
  ),
  mcVersion: '1.21.5',
  gitrinth: GitrinthConfig(curseforge: curseforge),
  mods: modsMap,
  plugins: pluginsMap,
);

void main() {
  // The wrapper test adapter above is a bit indirect; verify it builds
  // a ModFile that compiles (compile-time check only).
  test('test harness builds a ModFile', () {
    final f = _file(
      id: 1,
      modId: 100,
      fileName: 'x.jar',
      fileDate: '2025-01-01T00:00:00Z',
    );
    expect(f.id, 1);
  });

  group('resolveCurseforgeEntries', () {
    test(
      'accepts_mc queries both versions and selects the newest file',
      () async {
        final api = _FakeCfApi(
          projectsBySlug: {
            'jei': const Mod(
              id: 238222,
              gameId: 432,
              name: 'JEI',
              slug: 'jei',
              classId: 6,
            ),
          },
          filesByProject: {
            238222: [
              _file(
                id: 1,
                modId: 238222,
                fileName: 'current.jar',
                fileDate: '2025-01-01',
              ),
              _file(
                id: 2,
                modId: 238222,
                fileName: 'accepted.jar',
                fileDate: '2025-02-01',
                gameVersions: ['1.21.4'],
              ),
            ],
          },
        );
        final result = await resolveCurseforgeEntries(
          manifest: _pack(
            modsMap: {
              'jei': const ModEntry(slug: 'jei', acceptsMc: ['1.21.4']),
            },
          ),
          api: api,
          console: const Console(level: LogLevel.error),
        );
        expect(api.requestedGameVersions, ['1.21.5', '1.21.4']);
        expect(result.resolved.values.single.file.id, 2);
        expect(result.resolved.values.single.candidates.map((f) => f.id), [
          2,
          1,
        ]);
      },
    );

    test(
      'lookup authentication failure preserves its actionable cause',
      () async {
        final api = _FakeCfApi(
          lookupError: DioException(
            requestOptions: RequestOptions(path: '/v1/mods/search'),
            error: const AuthenticationError('CurseForge rejected the API key'),
          ),
        );
        await expectLater(
          resolveCurseforgeEntries(
            manifest: _pack(modsMap: {'jei': const ModEntry(slug: 'jei')}),
            api: api,
            console: const Console(level: LogLevel.error),
          ),
          throwsA(
            isA<AuthenticationError>().having(
              (e) => e.message,
              'message',
              contains('API key'),
            ),
          ),
        );
      },
    );

    test('listing network failure is not a missing compatible file', () async {
      final api = _FakeCfApi(
        projectsBySlug: {
          'jei': const Mod(
            id: 238222,
            gameId: 432,
            name: 'JEI',
            slug: 'jei',
            classId: 6,
          ),
        },
        listingError: DioException(
          requestOptions: RequestOptions(path: '/v1/mods/238222/files'),
          type: DioExceptionType.connectionError,
          message: 'connection refused',
        ),
      );
      await expectLater(
        resolveCurseforgeEntries(
          manifest: _pack(modsMap: {'jei': const ModEntry(slug: 'jei')}),
          api: api,
          console: const Console(level: LogLevel.error),
        ),
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            allOf(contains('238222'), contains('connection refused')),
          ),
        ),
      );
    });

    test(
      'nullable content type reports project identity before file selection',
      () async {
        final project = ModMapper.fromMap({
          'id': 42,
          'gameId': 432,
          'name': 'Unknown',
          'slug': 'unknown',
          'classId': null,
        });
        final api = _FakeCfApi(modsById: {42: project});
        final manifest = _pack(
          modsMap: {
            'alias': const ModEntry(
              slug: 'alias',
              curseforgeSlug: '42',
              sources: {SourceKind.curseforge},
            ),
          },
        );
        await expectLater(
          resolveCurseforgeEntries(
            manifest: manifest,
            api: api,
            console: const Console(level: LogLevel.error),
          ),
          throwsA(
            isA<ValidationError>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('unknown'),
                contains('42'),
                contains('content type'),
              ),
            ),
          ),
        );
        expect(api.calls, ['getMod(42)']);
      },
    );

    test('same local key retains both CurseForge sections', () async {
      final api = _FakeCfApi(
        modsById: {
          1: Mod(
            id: 1,
            gameId: kCurseForgeGameIdMinecraft,
            name: 'Mod',
            slug: 'mod-peer',
            classId: 6,
          ),
          2: Mod(
            id: 2,
            gameId: kCurseForgeGameIdMinecraft,
            name: 'Resources',
            slug: 'resource-peer',
            classId: 12,
          ),
        },
        filesByProject: {
          1: [
            _file(
              id: 11,
              modId: 1,
              fileName: 'mod.jar',
              fileDate: '2025-01-01',
            ),
          ],
          2: [
            _file(
              id: 22,
              modId: 2,
              fileName: 'resources.zip',
              fileDate: '2025-01-01',
            ),
          ],
        },
      );
      final manifest =
          _pack(
            modsMap: {
              'same': const ModEntry(
                slug: 'same',
                curseforgeSlug: '1',
                sources: {SourceKind.curseforge},
              ),
            },
          ).withSectionEntries(Section.resourcePacks, {
            'same': const ModEntry(
              slug: 'same',
              curseforgeSlug: '2',
              sources: {SourceKind.curseforge},
            ),
          });
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: api,
        console: const Console(level: LogLevel.error),
      );
      expect(out.notFound, isEmpty);
      expect(
        out.resolved.values.map((e) => (e.section, e.project.id)),
        unorderedEquals([(Section.mods, 1), (Section.resourcePacks, 2)]),
      );
      final lock = buildLock(
        manifest: manifest,
        resolution: const ResolutionResult([]),
        cfResolution: out,
        hashOutcomes: {},
        resolvedModLoaderVersion: '0.16.0',
        resolvedPluginLoaderVersion: null,
      );
      expect(lock.mods['same']!.curseforge!.projectId, 1);
      expect(lock.resourcePacks['same']!.curseforge!.projectId, 2);
      final offline = synthesizeCfResolutionFromLock(lock, manifest: manifest);
      expect(offline.resolved.keys, out.resolved.keys);
      expect(offline.resolved.values.map((e) => e.project.id), [1, 2]);
    });

    test('newest pick wins (sorted by fileDate descending)', () async {
      final cfApi = _FakeCfApi(
        projectsBySlug: {
          'jei': Mod(
            id: 238222,
            gameId: kCurseForgeGameIdMinecraft,
            name: 'JEI',
            slug: 'jei',
            classId: 6,
          ),
        },
        filesByProject: {
          238222: [
            _file(
              id: 1000,
              modId: 238222,
              fileName: 'jei-old.jar',
              fileDate: '2025-01-01T00:00:00Z',
            ),
            _file(
              id: 2000,
              modId: 238222,
              fileName: 'jei-new.jar',
              fileDate: '2025-06-01T00:00:00Z',
            ),
          ],
        },
      );
      final manifest = _pack(modsMap: {'jei': const ModEntry(slug: 'jei')});
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(out.notFound, isEmpty);
      expect(
        out.resolved[const LocalEntryKey(Section.mods, 'jei')]!.file.id,
        2000,
      );
      expect(
        out.resolved[const LocalEntryKey(Section.mods, 'jei')]!.candidates,
        hasLength(2),
      );
    });

    test('slug not found surfaces CfNotFound(slug-not-found)', () async {
      final cfApi = _FakeCfApi(projectsBySlug: const {'jei': null});
      final manifest = _pack(modsMap: {'jei': const ModEntry(slug: 'jei')});
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(out.resolved, isEmpty);
      expect(out.notFound, hasLength(1));
      expect(out.notFound.single.reason, 'slug-not-found');
      expect(out.notFound.single.slug, 'jei');
    });

    test('empty files surfaces CfNotFound(no-compatible-files)', () async {
      final cfApi = _FakeCfApi(
        projectsBySlug: {
          'jei': Mod(
            id: 238222,
            gameId: kCurseForgeGameIdMinecraft,
            name: 'JEI',
            slug: 'jei',
            classId: 6,
          ),
        },
        filesByProject: const {238222: []},
      );
      final manifest = _pack(modsMap: {'jei': const ModEntry(slug: 'jei')});
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(out.resolved, isEmpty);
      expect(out.notFound.single.reason, 'no-compatible-files');
    });

    test(
      'peer-slug override is used when entry has curseforge: <slug>',
      () async {
        final cfApi = _FakeCfApi(
          projectsBySlug: {
            'jei-peer': Mod(
              id: 999,
              gameId: kCurseForgeGameIdMinecraft,
              name: 'JEI',
              slug: 'jei-peer',
              classId: 6,
            ),
          },
          filesByProject: {
            999: [
              _file(
                id: 5000,
                modId: 999,
                fileName: 'jei.jar',
                fileDate: '2025-06-01T00:00:00Z',
              ),
            ],
          },
        );
        final manifest = _pack(
          modsMap: {
            'jei': const ModEntry(slug: 'jei', curseforgeSlug: 'jei-peer'),
          },
        );
        final out = await resolveCurseforgeEntries(
          manifest: manifest,
          api: cfApi,
          console: const Console(level: LogLevel.error),
        );
        expect(
          out.resolved[const LocalEntryKey(Section.mods, 'jei')]!.project.slug,
          'jei-peer',
        );
        expect(cfApi.calls, contains('searchMods(jei-peer)'));
      },
    );

    test('numeric `curseforge: 32274` short-circuits via getMod', () async {
      final cfApi = _FakeCfApi(
        modsById: {
          32274: Mod(
            id: 32274,
            gameId: kCurseForgeGameIdMinecraft,
            name: 'JEI',
            slug: 'jei',
            classId: 6,
          ),
        },
        filesByProject: {
          32274: [
            _file(
              id: 1,
              modId: 32274,
              fileName: 'jei.jar',
              fileDate: '2025-06-01T00:00:00Z',
            ),
          ],
        },
      );
      final manifest = _pack(
        modsMap: {'jei': const ModEntry(slug: 'jei', curseforgeSlug: '32274')},
      );
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(
        out.resolved[const LocalEntryKey(Section.mods, 'jei')]!.project.id,
        32274,
      );
      expect(cfApi.calls, contains('getMod(32274)'));
      // searchMods should NOT have been called.
      expect(cfApi.calls.where((c) => c.startsWith('searchMods')), isEmpty);
    });

    test('CF disabled at pack level skips silently', () async {
      final cfApi = _FakeCfApi(); // no projects registered
      final manifest = _pack(
        curseforge: GitrinthPlatformState.disabled,
        modsMap: {'jei': const ModEntry(slug: 'jei')},
      );
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(out.resolved, isEmpty);
      expect(out.notFound, isEmpty);
      expect(cfApi.calls, isEmpty);
    });

    test('vanilla mods: section short-circuits before any HTTP call', () async {
      final cfApi = _FakeCfApi();
      final manifest = _pack(
        mods: ModLoader.vanilla,
        modsMap: {'jei': const ModEntry(slug: 'jei')},
      );
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(out.resolved, isEmpty);
      expect(cfApi.calls, isEmpty);
    });

    test('Folia plugins entry silently skipped (matrix ineligible)', () async {
      final cfApi = _FakeCfApi();
      final manifest = _pack(
        mods: ModLoader.fabric,
        plugins: PluginLoader.folia,
        pluginsMap: {'plug': const ModEntry(slug: 'plug')},
      );
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(out.resolved, isEmpty);
      expect(out.notFound, isEmpty);
      expect(cfApi.calls, isEmpty);
    });

    test('url:/path: source entries are skipped (no CF resolution)', () async {
      final cfApi = _FakeCfApi();
      final manifest = _pack(
        modsMap: {
          'urlmod': const ModEntry(
            slug: 'urlmod',
            source: UrlEntrySource(url: 'https://example.com/x.jar'),
          ),
        },
      );
      final out = await resolveCurseforgeEntries(
        manifest: manifest,
        api: cfApi,
        console: const Console(level: LogLevel.error),
      );
      expect(out.resolved, isEmpty);
      expect(out.notFound, isEmpty);
      expect(cfApi.calls, isEmpty);
    });
  });
}
