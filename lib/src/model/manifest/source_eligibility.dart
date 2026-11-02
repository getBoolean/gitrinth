import 'mods_yaml.dart';

/// Single source of truth for "which platforms participate for this
/// entry". Resolves the entry's `sources:` override (if any) against
/// the pack-level `gitrinth.modrinth` / `gitrinth.curseforge` defaults,
/// then filters CurseForge out when the section/loader combination is
/// CF-ineligible (see [sectionAllowsCurseforge]).
///
/// Returns the set of [SourceKind]s that should attempt resolution.
/// May be empty when both platforms are disabled at the pack level and
/// the entry has no override.
///
/// Used by:
///   - the Modrinth resolver dispatch gate (`Resolver` / `pubgrub`)
///   - the CurseForge resolver pass
///   - the lockfile builder, when deciding whether to emit a
///     per-platform source block
///
/// Per-entry hard-restrictions (`url:` / `path:`) are not handled here
/// — those bypass platform resolution entirely. Callers that operate
/// on `kind: resolved` entries should read [ModEntry.source] separately.
Set<SourceKind> effectiveSources(
  ModsYaml manifest,
  ModEntry entry,
  Section section,
) {
  final base = entry.sources ?? _packDefault(manifest);
  if (base.isEmpty) return base;
  if (sectionAllowsCurseforge(section, manifest.loader.plugins)) {
    return base;
  }
  return base.where((k) => k != SourceKind.curseforge).toSet();
}

Set<SourceKind> _packDefault(ModsYaml manifest) {
  final out = <SourceKind>{};
  if (manifest.gitrinth.isPlatformEnabled(SourceKind.modrinth)) {
    out.add(SourceKind.modrinth);
  }
  if (manifest.gitrinth.isPlatformEnabled(SourceKind.curseforge)) {
    out.add(SourceKind.curseforge);
  }
  return out;
}
