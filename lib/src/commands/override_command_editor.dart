import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../cli/exceptions.dart';
import '../util/yaml_root.dart';

/// On-disk YAML key for the `project_overrides` section, in both
/// `mods.yaml` and the standalone `project_overrides.yaml`.
const projectOverridesKey = 'project_overrides';

/// Inserts (or creates) a single override entry under
/// `project_overrides:` inside [yamlText] (typically `mods.yaml`),
/// preserving comments and formatting via `yaml_edit`.
///
/// Exactly one of [shorthandValue] / [longForm] must be non-null;
/// shape mirrors `injectEntry` from add_command_editor.
///
/// Throws [UserError] when `project_overrides` already contains
/// [slug] — duplicates are rejected the same way `add` rejects
/// duplicate sections entries.
String injectOverrideEntry(
  String yamlText, {
  required String slug,
  String? shorthandValue,
  Map<String, Object?>? longForm,
}) {
  return _injectOverride(
    yamlText: yamlText,
    slug: slug,
    shorthandValue: shorthandValue,
    longForm: longForm,
    seedTopLevelOnEmpty: false,
  );
}

/// Same as [injectOverrideEntry] but for the standalone
/// `project_overrides.yaml` file. When [yamlText] is empty (the file
/// doesn't exist yet), seeds a top-level `project_overrides:` mapping
/// with the entry.
String injectStandaloneOverrideEntry(
  String yamlText, {
  required String slug,
  String? shorthandValue,
  Map<String, Object?>? longForm,
}) {
  return _injectOverride(
    yamlText: yamlText,
    slug: slug,
    shorthandValue: shorthandValue,
    longForm: longForm,
    seedTopLevelOnEmpty: true,
  );
}

String _injectOverride({
  required String yamlText,
  required String slug,
  required String? shorthandValue,
  required Map<String, Object?>? longForm,
  required bool seedTopLevelOnEmpty,
}) {
  if ((shorthandValue == null) == (longForm == null)) {
    throw ArgumentError(
      '_injectOverride requires exactly one of shorthandValue or longForm.',
    );
  }

  if (yamlText.trim().isEmpty) {
    if (!seedTopLevelOnEmpty) {
      throw const UserError('mods.yaml is empty; cannot edit.');
    }
    final editor = YamlEditor('')
      ..update([], <String, Object?>{
        projectOverridesKey: <String, Object?>{
          slug: longForm ?? shorthandValue,
        },
      });
    return editor.toString();
  }

  final editor = YamlEditor(yamlText);
  final root = parseYamlRoot(editor, filename: 'project_overrides target file');

  final sectionNode = root.nodes[projectOverridesKey];
  if (sectionNode == null) {
    editor.update(
      [projectOverridesKey],
      <String, Object?>{slug: longForm ?? shorthandValue},
    );
    return editor.toString();
  }
  if (sectionNode.value == null) {
    editor.update(
      [projectOverridesKey],
      <String, Object?>{slug: longForm ?? shorthandValue},
    );
    return editor.toString();
  }
  if (sectionNode is! YamlMap) {
    throw const UserError(
      "'project_overrides' must be a mapping; cannot add entries.",
    );
  }
  if (sectionNode.containsKey(slug)) {
    throw UserError(
      "'$slug' is already in project_overrides; remove it or edit "
      'directly.',
    );
  }
  editor.update([projectOverridesKey, slug], longForm ?? shorthandValue);
  return editor.toString();
}
