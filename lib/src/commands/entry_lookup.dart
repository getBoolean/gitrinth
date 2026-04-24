import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';

/// Finds the `(section, entry)` pair for [slug] in [manifest].
///
/// If [preferredSection] is given (from the `--type` flag), lookup is
/// restricted to that section. Otherwise every section is scanned and
/// ambiguity is surfaced to the user — both `mods:` and `data_packs:` can
/// legitimately carry an entry with the same slug when a project is
/// categorised one way on Modrinth but filed another way locally.
({Section section, ModEntry entry}) resolveEntry(
  ModsYaml manifest, {
  required String slug,
  Section? preferredSection,
}) {
  if (preferredSection != null) {
    final entry = manifest.sectionEntries(preferredSection)[slug];
    if (entry == null) {
      throw UserError(
        "'$slug' is not in section '${preferredSection.name}' of mods.yaml.",
      );
    }
    return (section: preferredSection, entry: entry);
  }

  final hits = <Section, ModEntry>{};
  for (final section in Section.values) {
    final entry = manifest.sectionEntries(section)[slug];
    if (entry != null) {
      hits[section] = entry;
    }
  }

  if (hits.isEmpty) {
    throw UserError("'$slug' is not in mods.yaml.");
  }
  if (hits.length > 1) {
    throw UserError(
      "'$slug' exists in multiple sections "
      '(${hits.keys.map((s) => s.name).join(', ')}); '
      'pass `--type <mod|resourcepack|datapack|shader>` to disambiguate.',
    );
  }
  final entry = hits.entries.single;
  return (section: entry.key, entry: entry.value);
}
