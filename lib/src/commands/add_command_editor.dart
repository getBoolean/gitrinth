import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';

/// Returns the YAML key used for [section] in `mods.yaml` — the parsed
/// [Section] enum values use camelCase, but on-disk the manifest uses
/// snake_case section headings (`resource_packs`, `data_packs`).
String sectionKeyFor(Section section) {
  switch (section) {
    case Section.mods:
      return 'mods';
    case Section.resourcePacks:
      return 'resource_packs';
    case Section.dataPacks:
      return 'data_packs';
    case Section.shaders:
      return 'shaders';
  }
}

/// Allowed values for the `--type` flag on `add`, `pin`, and `unpin`.
/// Mirrors Modrinth's `project_type` naming (singular, lowercase).
const typeFlagValues = ['mod', 'resourcepack', 'datapack', 'shader'];

/// Maps a `--type` flag value to its [Section]. Returns `null` when [raw] is
/// null (flag not passed). Unknown values should already have been rejected
/// by `argParser.addOption(allowed: ...)`, so this throws [ArgumentError]
/// instead of a user-facing error.
Section? sectionFromTypeFlag(String? raw) {
  if (raw == null) return null;
  switch (raw) {
    case 'mod':
      return Section.mods;
    case 'resourcepack':
      return Section.resourcePacks;
    case 'datapack':
      return Section.dataPacks;
    case 'shader':
      return Section.shaders;
    default:
      throw ArgumentError.value(raw, 'raw', 'unknown --type value');
  }
}

/// Inserts (or creates) a single entry under [section] inside [yamlText],
/// preserving comments and formatting via `yaml_edit`.
///
/// Exactly one of [shorthandValue] / [longForm] must be non-null:
///   - [shorthandValue] emits `slug: <value>` (e.g. `sodium: release`,
///     `terralith: ^2.5.8`).
///   - [longForm] emits the mapping form
///     (`slug:\n  key: value\n  ...`). Used when the caller needs
///     `environment:`, `url:`, `path:`, or any other long-only field.
///
/// Throws [UserError] when the section already contains [slug] — the caller
/// is expected to detect the duplicate earlier with a nicer message, but
/// this guard keeps the editor honest.
String injectEntry(
  String yamlText, {
  required Section section,
  required String slug,
  String? shorthandValue,
  Map<String, Object?>? longForm,
}) {
  if ((shorthandValue == null) == (longForm == null)) {
    throw ArgumentError(
      'injectEntry requires exactly one of shorthandValue or longForm.',
    );
  }

  final editor = YamlEditor(yamlText);
  final sectionKey = sectionKeyFor(section);

  final YamlNode root;
  try {
    root = editor.parseAt([]);
  } on Object {
    throw const UserError('mods.yaml is not valid YAML; cannot edit.');
  }
  if (root is! YamlMap) {
    throw const UserError('mods.yaml top-level must be a mapping.');
  }

  final sectionNode = root.nodes[sectionKey];
  if (sectionNode == null) {
    // Section missing entirely — create it with this one entry.
    editor.update(
      [sectionKey],
      <String, Object?>{slug: longForm ?? shorthandValue},
    );
    return editor.toString();
  }

  if (sectionNode.value == null) {
    // Section exists as a null scalar (`mods:` with no value). Replace.
    editor.update(
      [sectionKey],
      <String, Object?>{slug: longForm ?? shorthandValue},
    );
    return editor.toString();
  }

  if (sectionNode is! YamlMap) {
    throw UserError(
      "mods.yaml section '$sectionKey' is not a mapping; cannot add entries.",
    );
  }

  if (sectionNode.containsKey(slug)) {
    throw UserError("'$slug' already exists under '$sectionKey' in mods.yaml.");
  }

  editor.update([sectionKey, slug], longForm ?? shorthandValue);
  return editor.toString();
}
