import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/overrides_merger.dart';
import 'package:gitrinth/src/model/manifest/project_overrides.dart';
import 'package:test/test.dart';

void main() {
  ModsYaml base() => ModsYaml(
    slug: 'pack',
    name: 'Pack',
    version: '0.1.0',
    description: 'x',
    loader: const LoaderConfig(mods: ModLoader.neoforge),
    mcVersion: '1.21.1',
    mods: {
      'jei': const ModEntry(slug: 'jei', constraintRaw: '^19.0.0'),
      'create': const ModEntry(slug: 'create', constraintRaw: '^6.0.0'),
    },
  );

  Future<Section> stubInferSection(String slug) async => Section.mods;

  test(
    'version-only overrides preserve platform participation and peer identity',
    () async {
      final m = base().copyWith(
        gitrinth: const GitrinthConfig(
          curseforge: GitrinthPlatformState.enabled,
        ),
        modrinthHost: 'https://labrinth.example/v2',
        mods: {
          'jei': const ModEntry(
            slug: 'jei',
            source: ModrinthEntrySource(host: 'https://entry.example/v2'),
            sources: {SourceKind.curseforge},
            curseforgeSlug: 'just-enough-items',
            noCrossPlatformSearch: true,
          ),
        },
      );
      final out = await applyOverrides(
        m,
        const ProjectOverrides(
          entries: {'jei': ModEntry(slug: 'jei', constraintRaw: '19.0.0')},
        ),
        inferSectionForTransitive: stubInferSection,
      );
      expect(out.manifest.gitrinth.curseforge, GitrinthPlatformState.enabled);
      expect(out.manifest.modrinthHost, m.modrinthHost);
      expect(out.manifest.mods['jei']!.sources, {SourceKind.curseforge});
      expect(out.manifest.mods['jei']!.curseforgeSlug, 'just-enough-items');
      expect(out.manifest.mods['jei']!.noCrossPlatformSearch, isTrue);
      expect(
        (out.manifest.mods['jei']!.source as ModrinthEntrySource).host,
        'https://entry.example/v2',
      );
    },
  );

  test('overrides win over matching entries (in-file overrides)', () async {
    final m = base();
    final withOv = ModsYaml(
      slug: m.slug,
      name: m.name,
      version: m.version,
      description: m.description,
      loader: m.loader,
      mcVersion: m.mcVersion,
      mods: m.mods,
      projectOverrides: {
        'jei': const ModEntry(slug: 'jei', constraintRaw: '19.27.0.340'),
      },
    );
    final out = await applyOverrides(
      withOv,
      const ProjectOverrides(),
      inferSectionForTransitive: stubInferSection,
    );
    expect(out.manifest.mods['jei']!.constraintRaw, '19.27.0.340');
    expect(out.manifest.mods['create']!.constraintRaw, '^6.0.0');
    expect(out.overriddenSlugs, {'jei'});
  });

  test('standalone project_overrides.yaml wins on conflicts', () async {
    final m = base();
    final withOv = ModsYaml(
      slug: m.slug,
      name: m.name,
      version: m.version,
      description: m.description,
      loader: m.loader,
      mcVersion: m.mcVersion,
      mods: m.mods,
      projectOverrides: {
        'jei': const ModEntry(slug: 'jei', constraintRaw: '19.0.0'),
      },
    );
    final extra = ProjectOverrides(
      entries: {
        'jei': const ModEntry(slug: 'jei', constraintRaw: '19.27.0.340'),
      },
    );
    final out = await applyOverrides(
      withOv,
      extra,
      inferSectionForTransitive: stubInferSection,
    );
    expect(out.manifest.mods['jei']!.constraintRaw, '19.27.0.340');
  });

  test('source override redirects entry to a local path', () async {
    final m = base();
    final extra = ProjectOverrides(
      entries: {
        'create': const ModEntry(
          slug: 'create',
          source: PathEntrySource(path: './mods/dev.jar'),
        ),
      },
    );
    final out = await applyOverrides(
      m,
      extra,
      inferSectionForTransitive: stubInferSection,
    );
    expect(out.manifest.mods['create']!.source, isA<PathEntrySource>());
    expect(
      (out.manifest.mods['create']!.source as PathEntrySource).path,
      './mods/dev.jar',
    );
  });

  test(
    'transitive override slug gets section from inferSectionForTransitive',
    () async {
      final m = base();
      Future<Section> infer(String slug) async {
        if (slug == 'terralith') return Section.dataPacks;
        return Section.mods;
      }

      final extra = ProjectOverrides(
        entries: {
          'terralith': const ModEntry(
            slug: 'terralith',
            constraintRaw: '^2.5.0',
          ),
        },
      );
      final out = await applyOverrides(
        m,
        extra,
        inferSectionForTransitive: infer,
      );
      expect(out.manifest.dataPacks['terralith'], isNotNull);
      expect(out.manifest.dataPacks['terralith']!.constraintRaw, '^2.5.0');
      expect(out.manifest.mods.containsKey('terralith'), isFalse);
      expect(out.overriddenSlugs, {'terralith'});
    },
  );

  test('merger does not call inferSectionForTransitive for slugs already in '
      'some section', () async {
    final m = base();
    var calls = 0;
    Future<Section> infer(String slug) async {
      calls++;
      return Section.mods;
    }

    final extra = ProjectOverrides(
      entries: {
        'jei': const ModEntry(slug: 'jei', constraintRaw: '19.27.0.340'),
      },
    );
    await applyOverrides(m, extra, inferSectionForTransitive: infer);
    expect(calls, 0);
  });

  test('override on a marker entry replaces the marker', () async {
    final m = ModsYaml(
      slug: 'pack',
      name: 'Pack',
      version: '0.1.0',
      description: 'x',
      loader: const LoaderConfig(mods: ModLoader.neoforge),
      mcVersion: '1.21.1',
      mods: {
        'jei': const ModEntry(
          slug: 'jei',
          constraintRaw: 'gitrinth:disabled-by-conflict',
        ),
      },
    );
    final extra = ProjectOverrides(
      entries: {
        'jei': const ModEntry(slug: 'jei', constraintRaw: '19.27.0.340'),
      },
    );
    final out = await applyOverrides(
      m,
      extra,
      inferSectionForTransitive: stubInferSection,
    );
    expect(out.manifest.mods['jei']!.constraintRaw, '19.27.0.340');
  });
}
