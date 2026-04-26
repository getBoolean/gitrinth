import 'mods_yaml.dart';
import 'project_overrides.dart';

/// Merges the standalone `project_overrides.yaml` into the in-file
/// `project_overrides:` map (standalone wins on conflicts), then applies
/// the merged override onto the matching entry in
/// `mods`/`resource_packs`/`data_packs`/`shaders`. Purely-transitive
/// overrides — slugs not declared in any section — are synthesized into
/// the section returned by [inferSectionForTransitive].
///
/// Returns a [MergedManifest]. Pure on its own; the I/O it might need
/// for transitive section inference is delegated to the supplied
/// closure.
Future<MergedManifest> applyOverrides(
  ModsYaml base,
  ProjectOverrides extra, {
  required Future<Section> Function(String slug) inferSectionForTransitive,
}) async {
  final merged = <String, ModEntry>{
    ...base.projectOverrides,
    ...extra.entries, // standalone-file values win
  };
  if (merged.isEmpty) {
    return MergedManifest(
      manifest: base,
      overrideEntries: const {},
    );
  }

  final mods = _applyTo(base.mods, merged);
  final resourcePacks = _applyTo(base.resourcePacks, merged);
  final dataPacks = _applyTo(base.dataPacks, merged);
  final shaders = _applyTo(base.shaders, merged);

  // Materialize purely-transitive overrides — slugs the user wrote
  // into project_overrides: but never declared in any project section
  // — into the section matching their Modrinth project type.
  for (final e in merged.entries) {
    final slug = e.key;
    final ov = e.value;
    final alreadyDeclared = base.mods.containsKey(slug)
        || base.resourcePacks.containsKey(slug)
        || base.dataPacks.containsKey(slug)
        || base.shaders.containsKey(slug);
    if (alreadyDeclared) continue;
    final section = await inferSectionForTransitive(slug);
    final synthesized = ModEntry(
      slug: slug,
      constraintRaw: ov.constraintRaw,
      channel: ov.channel,
      client: ov.client,
      server: ov.server,
      source: ov.source,
      acceptsMc: ov.acceptsMc,
    );
    switch (section) {
      case Section.mods:
        mods[slug] = synthesized;
        break;
      case Section.resourcePacks:
        resourcePacks[slug] = synthesized;
        break;
      case Section.dataPacks:
        dataPacks[slug] = synthesized;
        break;
      case Section.shaders:
        shaders[slug] = synthesized;
        break;
    }
  }

  final mergedManifest = ModsYaml(
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
    projectOverrides: merged,
    files: base.files,
  );

  return MergedManifest(
    manifest: mergedManifest,
    overrideEntries: merged,
  );
}

/// Result of [applyOverrides]: the post-merge manifest plus the
/// information the resolver needs to honor sticky overrides.
class MergedManifest {
  /// Manifest with override entries applied to existing slugs and
  /// purely-transitive override slugs synthesized into the section
  /// returned by `inferSectionForTransitive`.
  final ModsYaml manifest;

  /// Slug → effective override entry (in-file ∪ standalone, standalone
  /// wins on conflicts).
  final Map<String, ModEntry> overrideEntries;

  const MergedManifest({
    required this.manifest,
    required this.overrideEntries,
  });

  /// `overrideEntries.keys.toSet()`. Cached on first access.
  Set<String> get overriddenSlugs => overrideEntries.keys.toSet();
}

Map<String, ModEntry> _applyTo(
  Map<String, ModEntry> section,
  Map<String, ModEntry> overrides,
) {
  if (section.isEmpty) return Map.of(section);
  final result = <String, ModEntry>{};
  section.forEach((slug, entry) {
    final ov = overrides[slug];
    if (ov == null) {
      result[slug] = entry;
      return;
    }
    // Override replaces version + source for this entry; per-side
    // install state is overridden whenever the override declared a
    // non-default value. A `gitrinth:` marker on the base entry is
    // replaced entirely — overrides are user intent and bypass the
    // disabled-by-conflict / not-found state.
    result[slug] = ModEntry(
      slug: slug,
      constraintRaw: ov.constraintRaw ?? entry.constraintRaw,
      channel: ov.channel ?? entry.channel,
      client: ov.client,
      server: ov.server,
      source: ov.source,
      acceptsMc: ov.acceptsMc.isNotEmpty ? ov.acceptsMc : entry.acceptsMc,
    );
  });
  return result;
}
