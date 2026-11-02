import 'mods_yaml.dart';
import 'project_overrides.dart';

/// Merges standalone and inline project overrides, then applies them to
/// declared entries. Undeclared override slugs are synthesized into the
/// section returned by [inferSectionForTransitive].
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
    return MergedManifest(manifest: base, overrideEntries: const {});
  }

  final mods = _applyTo(base.mods, merged);
  final resourcePacks = _applyTo(base.resourcePacks, merged);
  final dataPacks = _applyTo(base.dataPacks, merged);
  final shaders = _applyTo(base.shaders, merged);
  final plugins = _applyTo(base.plugins, merged);

  // Materialize undeclared override slugs into their inferred section.
  for (final e in merged.entries) {
    final slug = e.key;
    final ov = e.value;
    final alreadyDeclared =
        base.mods.containsKey(slug) ||
        base.resourcePacks.containsKey(slug) ||
        base.dataPacks.containsKey(slug) ||
        base.shaders.containsKey(slug) ||
        base.plugins.containsKey(slug);
    if (alreadyDeclared) continue;
    final section = await inferSectionForTransitive(slug);
    final synthesized = ov.copyWith(slug: slug);
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
      case Section.plugins:
        plugins[slug] = synthesized;
        break;
    }
  }

  final mergedManifest = base.copyWith(
    mods: mods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
    plugins: plugins,
    projectOverrides: merged,
    files: base.files,
  );

  return MergedManifest(manifest: mergedManifest, overrideEntries: merged);
}

/// Result of [applyOverrides].
class MergedManifest {
  /// Manifest after applying overrides.
  final ModsYaml manifest;

  /// Effective override entry by slug.
  final Map<String, ModEntry> overrideEntries;

  const MergedManifest({required this.manifest, required this.overrideEntries});

  /// Convenience set of overridden slugs.
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
    // Override version/source, and replace any transient gitrinth marker.
    result[slug] = entry.copyWith(
      constraintRaw: ov.constraintRaw ?? entry.constraintRaw,
      channel: ov.channel ?? entry.channel,
      client: ov.client,
      server: ov.server,
      source: switch ((entry.source, ov.source)) {
        (ModrinthEntrySource(), ModrinthEntrySource(host: null)) =>
          entry.source,
        _ => ov.source,
      },
      acceptsMc: ov.acceptsMc.isNotEmpty ? ov.acceptsMc : entry.acceptsMc,
      modrinthSlug: ov.modrinthSlug ?? entry.modrinthSlug,
      curseforgeSlug: ov.curseforgeSlug ?? entry.curseforgeSlug,
      sources: ov.sources ?? entry.sources,
      hashScanDepth: ov.hashScanDepth ?? entry.hashScanDepth,
      allowHashMismatch: ov.allowHashMismatch ?? entry.allowHashMismatch,
      noCrossPlatformSearch:
          ov.noCrossPlatformSearch || entry.noCrossPlatformSearch,
    );
  });
  return result;
}
