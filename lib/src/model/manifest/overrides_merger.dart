import 'mods_overrides.dart';
import 'mods_yaml.dart';

/// Merges the standalone `mods_overrides.yaml` into the in-file `overrides:`
/// map (standalone wins on conflicts), then applies the merged override onto
/// the matching entry in `mods`/`resource_packs`/`data_packs`/`shaders`.
///
/// Returns a new ModsYaml. Pure: no I/O.
ModsYaml applyOverrides(ModsYaml base, ModsOverrides extra) {
  final merged = <String, ModEntry>{
    ...base.overrides,
    ...extra.overrides, // standalone-file values win
  };
  if (merged.isEmpty) return base;

  final mods = _applyTo(base.mods, merged);
  final resourcePacks = _applyTo(base.resourcePacks, merged);
  final dataPacks = _applyTo(base.dataPacks, merged);
  final shaders = _applyTo(base.shaders, merged);

  return ModsYaml(
    slug: base.slug,
    name: base.name,
    version: base.version,
    description: base.description,
    loader: base.loader,
    mcVersion: base.mcVersion,
    mods: mods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
    overrides: merged,
  );
}

Map<String, ModEntry> _applyTo(
  Map<String, ModEntry> section,
  Map<String, ModEntry> overrides,
) {
  if (section.isEmpty) return section;
  final result = <String, ModEntry>{};
  section.forEach((slug, entry) {
    final ov = overrides[slug];
    if (ov == null) {
      result[slug] = entry;
      return;
    }
    // Override replaces version + source for this entry; per-side
    // install state is overridden whenever the override declared a
    // non-default value.
    result[slug] = ModEntry(
      slug: slug,
      constraintRaw: ov.constraintRaw ?? entry.constraintRaw,
      client: ov.client,
      server: ov.server,
      source: ov.source,
    );
  });
  return result;
}
