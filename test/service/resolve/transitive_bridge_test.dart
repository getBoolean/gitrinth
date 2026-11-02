import 'package:gitrinth/src/model/curseforge/cf_mod.dart';
import 'package:gitrinth/src/model/curseforge/cf_mod_file.dart';
import 'package:gitrinth/src/model/curseforge/cf_file_relation.dart';
import 'package:gitrinth/src/model/curseforge/cf_search_response.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/service/console.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_api.dart';
import 'package:gitrinth/src/service/resolve/curseforge_resolver.dart';
import 'package:gitrinth/src/service/resolve/resolve_and_sync.dart';
import 'package:test/test.dart';

class GraphApi implements CurseForgeApi {
  final Map<int, Mod> projects;
  final Map<int, List<int>> edges;
  GraphApi(this.projects, this.edges);
  @override
  Future<ModEnvelope> getMod(int id) async => ModEnvelope(data: projects[id]!);
  @override
  Future<ModSearchResponse> searchMods({
    required int gameId,
    int? classId,
    String? slug,
    String? searchFilter,
    int? index,
    int? pageSize,
  }) async {
    final data = projects.values
        .where((p) => p.slug == slug && p.classId == classId)
        .toList();
    return ModSearchResponse(
      data: data,
      pagination: Pagination(
        index: 0,
        pageSize: 50,
        resultCount: data.length,
        totalCount: data.length,
      ),
    );
  }

  @override
  Future<ModFileSearchResponse> listFiles(
    int modId, {
    String? gameVersion,
    int? modLoaderType,
    int? index,
    int? pageSize,
  }) async => ModFileSearchResponse(
    data: [
      ModFile(
        id: modId * 10,
        modId: modId,
        displayName: '1.0.0',
        fileName: '$modId.jar',
        releaseType: 1,
        fileDate: '2026-01-01',
        gameVersions: ['1.21.1'],
        hashes: [],
        dependencies: [
          for (final child in edges[modId] ?? <int>[])
            FileRelation(modId: child, relationTypeCode: 3),
        ],
      ),
    ],
    pagination: Pagination(
      index: 0,
      pageSize: 50,
      resultCount: 1,
      totalCount: 1,
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Mod project(int id, String slug, [int classId = 6]) =>
    Mod(id: id, gameId: 432, name: slug, slug: slug, classId: classId);
ModsYaml pack(Map<String, ModEntry> mods) => ModsYaml(
  slug: 'p',
  name: 'p',
  version: '1',
  description: '',
  loader: LoaderConfig(mods: ModLoader.fabric),
  mcVersion: '1.21.1',
  mods: mods,
  gitrinth: GitrinthConfig(curseforge: GitrinthPlatformState.enabled),
);
void main() {
  for (final constraint in ['^2.0.0', '2.0.0', 'different-label']) {
    test(
      'CF-only version constraint $constraint excludes unmatched files',
      () async {
        final result = await resolveCurseforgeEntries(
          manifest: pack({
            'root': ModEntry(
              slug: 'root',
              sources: {SourceKind.curseforge},
              constraintRaw: constraint,
            ),
          }),
          api: GraphApi({1: project(1, 'root')}, {}),
          console: Console(level: LogLevel.error),
        );
        expect(result.resolved, isEmpty);
        expect(result.notFound.single.reason, 'no-compatible-files');
      },
    );
  }
  test(
    'CF cycles terminate and reuse aliases while retaining all parents',
    () async {
      final result = await resolveCurseforgeEntries(
        manifest: pack({
          'root': ModEntry(slug: 'root'),
          'my-library': ModEntry(slug: 'my-library', curseforgeSlug: 'library'),
        }),
        api: GraphApi(
          {
            1: project(1, 'root'),
            2: project(2, 'library'),
            3: project(3, 'other'),
          },
          {
            1: [2, 3],
            2: [1],
            3: [2],
          },
        ),
        console: Console(level: LogLevel.error),
      );
      expect(
        result.resolved.keys,
        unorderedEquals(['root', 'my-library', 'other']),
      );
      expect(result.resolved['my-library']!.requiredBy, ['other', 'root']);
      expect(result.resolved['my-library']!.transitive, isFalse);
      expect(result.resolved['other']!.transitive, isTrue);
      expect(result.resolved['root']!.requiredBy, ['my-library']);
    },
  );
  test('CF dependencies infer their own section', () async {
    final result = await resolveCurseforgeEntries(
      manifest: pack({'root': ModEntry(slug: 'root')}),
      api: GraphApi(
        {1: project(1, 'root'), 2: project(2, 'textures', 12)},
        {
          1: [2],
        },
      ),
      console: Console(level: LogLevel.error),
    );
    expect(result.resolved['textures']!.section, Section.resourcePacks);
  });
  test('required_by round trips and prunes offline orphan cycles', () {
    final lock = ModsLock(
      gitrinthVersion: '1',
      loader: LoaderConfig(mods: ModLoader.fabric),
      mcVersion: '1.21.1',
      mods: {
        for (final name in ['root', 'child', 'orphan-a', 'orphan-b'])
          name: LockedEntry(
            slug: name,
            kind: LockedEntryKind.resolved,
            dependency: name == 'root'
                ? LockedDependencyKind.direct
                : LockedDependencyKind.transitive,
            requiredBy: switch (name) {
              'child' => ['root'],
              'orphan-a' => ['orphan-b'],
              'orphan-b' => ['orphan-a'],
              _ => [],
            },
            curseforge: LockedCurseforgeSource(
              projectId: name.length,
              fileId: 1,
              file: LockedFile(name: '$name.jar'),
            ),
          ),
      },
    );
    final roundTrip = parseModsLock(emitModsLock(lock), filePath: 'mods.lock');
    expect(roundTrip.mods['child']!.requiredBy, ['root']);
    final retained = synthesizeCfResolutionFromLock(
      roundTrip,
      manifest: pack({'root': ModEntry(slug: 'root')}),
    );
    expect(retained.resolved.keys, unorderedEquals(['root', 'child']));
    expect(retained.resolved['child']!.requiredBy, ['root']);
    final narrowed = synthesizeCfResolutionFromLock(
      roundTrip,
      manifest: pack({
        'root': ModEntry(slug: 'root', sources: {SourceKind.modrinth}),
      }),
    );
    expect(narrowed.resolved, isEmpty);
  });
}
