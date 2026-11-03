import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/file_entry.dart';
import 'package:gitrinth/src/model/resolver/constraint.dart';
import 'package:gitrinth/src/service/resolve/conflict_disable.dart';
import 'package:test/test.dart';

void main() {
  const entries = {
    'target': ModEntry(slug: 'remote-name', constraintRaw: '^1.0.0'),
    'keep': ModEntry(slug: 'keep', constraintRaw: '^2.0.0'),
  };
  const manifest = ModsYaml(
    slug: 'pack',
    name: 'Pack',
    version: '1.2.3',
    description: 'All settings survive section changes',
    mcVersion: '1.21.1',
    loader: LoaderConfig(
      mods: ModLoader.fabric,
      modLoaderVersion: '0.16.0',
      plugins: PluginLoader.paper,
      pluginLoaderVersion: '100',
    ),
    modrinthHost: 'https://source.example/v2',
    gitrinth: GitrinthConfig(
      version: '^0.1.0',
      curseforge: GitrinthPlatformState.enabled,
    ),
    mods: entries,
    resourcePacks: entries,
    dataPacks: entries,
    shaders: entries,
    plugins: entries,
    projectOverrides: {'override': ModEntry(slug: 'override')},
    files: {'config/a': FileEntry(destination: 'config/a', sourcePath: 'a')},
    publishTo: {SourceKind.modrinth: 'https://publish.example/v2'},
  );

  void expectPackSettingsPreserved(ModsYaml result) {
    expect(result.slug, manifest.slug);
    expect(result.name, manifest.name);
    expect(result.version, manifest.version);
    expect(result.description, manifest.description);
    expect(result.mcVersion, manifest.mcVersion);
    expect(result.loader, manifest.loader);
    expect(result.modrinthHost, manifest.modrinthHost);
    expect(result.gitrinth, manifest.gitrinth);
    expect(result.projectOverrides, manifest.projectOverrides);
    expect(result.files, manifest.files);
    expect(result.publishTo, manifest.publishTo);
  }

  test(
    'section mapping transforms every section and preserves pack settings',
    () {
      final transformed = manifest.mapSectionEntries(
        (section, values) => {
          for (final entry in values.entries)
            entry.key: entry.value.copyWith(constraintRaw: section.name),
        },
      );

      for (final section in Section.values) {
        expect(
          transformed.sectionEntries(section)['target']!.constraintRaw,
          section.name,
        );
        expect(
          transformed.sectionEntries(section)['keep']!.constraintRaw,
          section.name,
        );
        expect(
          manifest.sectionEntries(section)['target']!.constraintRaw,
          '^1.0.0',
        );
      }
      expectPackSettingsPreserved(transformed);
    },
  );

  test('section replacement changes only the selected section', () {
    for (final selected in Section.values) {
      final replaced = manifest.withSectionEntries(selected, const {});
      for (final section in Section.values) {
        expect(
          replaced.sectionEntries(section),
          section == selected ? isEmpty : entries,
        );
      }
      expectPackSettingsPreserved(replaced);
    }
  });

  test('removal uses local map keys in every section', () {
    final stripped = manifest.withoutEntrySlugs({'target'});
    for (final section in Section.values) {
      expect(stripped.sectionEntries(section), {'keep': entries['keep']});
    }
    expectPackSettingsPreserved(stripped);
  });

  test('conflict markers apply to plugins without changing other sections', () {
    const manifest = ModsYaml(
      slug: 'pack',
      name: 'Pack',
      version: '1.0.0',
      description: '',
      mcVersion: '1.21.1',
      loader: LoaderConfig(
        mods: ModLoader.vanilla,
        plugins: PluginLoader.paper,
      ),
      mods: {'same': ModEntry(slug: 'same', constraintRaw: '^1.0.0')},
      plugins: {'same': ModEntry(slug: 'same', constraintRaw: '^2.0.0')},
    );

    final marked = applyDisableMarkers(manifest, {(Section.plugins, 'same')});

    expect(marked.plugins['same']!.constraintRaw, disabledByConflictMarker);
    expect(marked.mods['same']!.constraintRaw, '^1.0.0');
    expect(manifest.plugins['same']!.constraintRaw, '^2.0.0');
  });
}
