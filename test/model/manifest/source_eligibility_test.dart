import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/source_eligibility.dart';
import 'package:test/test.dart';

ModsYaml _pack({
  required PluginLoader? plugins,
  GitrinthPlatformState modrinth = GitrinthPlatformState.enabled,
  GitrinthPlatformState curseforge = GitrinthPlatformState.disabled,
  Map<String, ModEntry> mods = const {},
  Map<String, ModEntry> pluginsMap = const {},
  Map<String, ModEntry> resourcePacks = const {},
}) {
  return ModsYaml(
    slug: 'pack',
    name: 'pack',
    version: '0.0.1',
    description: '',
    loader: LoaderConfig(
      mods: ModLoader.fabric,
      modLoaderVersion: '0.16.0',
      plugins: plugins,
    ),
    mcVersion: '1.21.5',
    gitrinth: GitrinthConfig(modrinth: modrinth, curseforge: curseforge),
    mods: mods,
    resourcePacks: resourcePacks,
    plugins: pluginsMap,
  );
}

ModEntry _entry({Set<SourceKind>? sources, String? curseforgeSlug}) {
  return ModEntry(
    slug: 'jei',
    sources: sources,
    curseforgeSlug: curseforgeSlug,
  );
}

void main() {
  group('effectiveSources', () {
    test('falls back to pack defaults when entry.sources is null', () {
      final manifest = _pack(plugins: null);
      expect(
        effectiveSources(manifest, _entry(), Section.mods),
        equals({SourceKind.modrinth}),
      );
    });

    test('pack default with both platforms enabled returns both', () {
      final manifest = _pack(
        plugins: null,
        modrinth: GitrinthPlatformState.enabled,
        curseforge: GitrinthPlatformState.enabled,
      );
      expect(
        effectiveSources(manifest, _entry(), Section.mods),
        equals({SourceKind.modrinth, SourceKind.curseforge}),
      );
    });

    test('pack default empty when both disabled and no entry override', () {
      final manifest = _pack(
        plugins: null,
        modrinth: GitrinthPlatformState.disabled,
        curseforge: GitrinthPlatformState.disabled,
      );
      expect(effectiveSources(manifest, _entry(), Section.mods), isEmpty);
    });

    test('entry sources: [curseforge] overrides pack-level disable', () {
      final manifest = _pack(
        plugins: null,
        curseforge: GitrinthPlatformState.disabled,
      );
      expect(
        effectiveSources(
          manifest,
          _entry(sources: {SourceKind.curseforge}),
          Section.mods,
        ),
        equals({SourceKind.curseforge}),
      );
    });

    test('Folia plugins section silently drops curseforge', () {
      final manifest = _pack(
        plugins: PluginLoader.folia,
        modrinth: GitrinthPlatformState.enabled,
        curseforge: GitrinthPlatformState.enabled,
      );
      expect(
        effectiveSources(manifest, _entry(), Section.plugins),
        equals({SourceKind.modrinth}),
      );
    });

    test('Sponge plugins section silently drops curseforge', () {
      final manifest = _pack(
        plugins: PluginLoader.spongeforge,
        curseforge: GitrinthPlatformState.enabled,
      );
      expect(
        effectiveSources(manifest, _entry(), Section.plugins),
        equals({SourceKind.modrinth}),
      );
    });

    test('paper plugins section keeps curseforge', () {
      final manifest = _pack(
        plugins: PluginLoader.paper,
        curseforge: GitrinthPlatformState.enabled,
      );
      expect(
        effectiveSources(manifest, _entry(), Section.plugins),
        equals({SourceKind.modrinth, SourceKind.curseforge}),
      );
    });

    test('non-plugins section never filters curseforge by loader', () {
      final manifest = _pack(
        plugins: PluginLoader.folia,
        curseforge: GitrinthPlatformState.enabled,
      );
      expect(
        effectiveSources(manifest, _entry(), Section.mods),
        equals({SourceKind.modrinth, SourceKind.curseforge}),
      );
      expect(
        effectiveSources(manifest, _entry(), Section.resourcePacks),
        equals({SourceKind.modrinth, SourceKind.curseforge}),
      );
    });

    test('entry sources: [curseforge] in Folia plugins drops to empty set', () {
      final manifest = _pack(
        plugins: PluginLoader.folia,
        curseforge: GitrinthPlatformState.enabled,
      );
      expect(
        effectiveSources(
          manifest,
          _entry(sources: {SourceKind.curseforge}),
          Section.plugins,
        ),
        isEmpty,
      );
    });
  });
}
