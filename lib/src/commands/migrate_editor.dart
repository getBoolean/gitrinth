import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import 'add_command_editor.dart';

/// Updates a top-level scalar at [path] (e.g. `['mc-version']`,
/// `['loader', 'mods']`).
String updateTopLevelScalar(
  String yamlText, {
  required List<String> path,
  required String newValue,
}) {
  final editor = YamlEditor(yamlText);
  final YamlNode root;
  try {
    root = editor.parseAt([]);
  } on Object {
    throw const UserError('mods.yaml is not valid YAML; cannot edit.');
  }
  if (root is! YamlMap) {
    throw const UserError('mods.yaml top-level must be a mapping.');
  }
  editor.update(path, newValue);
  return editor.toString();
}

/// Sets the entry's `version:` to [newVersion]. Accepts non-semver strings
/// (the `gitrinth:not-found` marker, a fresh `^<bare>`). Rejects long-form
/// entries with no `version:` key (url/path sources).
String setEntryVersion(
  String yamlText, {
  required Section section,
  required String slug,
  required String newVersion,
}) {
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
  if (sectionNode == null || sectionNode.value == null) {
    throw UserError("'$slug' not found under '$sectionKey' in mods.yaml.");
  }
  if (sectionNode is! YamlMap) {
    throw UserError(
      "mods.yaml section '$sectionKey' is not a mapping; cannot edit.",
    );
  }

  final entryNode = sectionNode.nodes[slug];
  if (entryNode == null) {
    throw UserError("'$slug' not found under '$sectionKey' in mods.yaml.");
  }

  if (entryNode is YamlMap) {
    if (!entryNode.containsKey('version')) {
      throw UserError(
        "'$slug' has no `version:` field — likely a url/path source; "
        'cannot rewrite version.',
      );
    }
    editor.update([sectionKey, slug, 'version'], newVersion);
  } else {
    editor.update([sectionKey, slug], newVersion);
  }

  return editor.toString();
}
