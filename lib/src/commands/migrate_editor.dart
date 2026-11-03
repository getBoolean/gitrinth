import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../model/manifest/mods_yaml.dart';
import '../util/yaml_root.dart';
import 'entry_version_editor.dart';

/// Updates a top-level scalar at [path] (e.g. `['mc_version']`,
/// `['loader', 'mods']`).
String updateTopLevelScalar(
  String yamlText, {
  required List<String> path,
  required String newValue,
}) {
  final editor = YamlEditor(yamlText);
  parseYamlRoot(editor, filename: 'mods.yaml');
  editor.update(path, newValue);
  return editor.toString();
}

/// Sets `loader.mods` to [value], or removes the key when [value] is
/// null (the canonical "vanilla / no mod runtime" form). Inserts
/// `loader:` when the manifest omits it.
///
/// Three legal yaml shapes the helper survives:
///   1. `loader:` missing entirely → insert `loader: { mods: <value> }`.
///   2. `loader:` present but no `mods:` key → insert the leaf.
///   3. `loader:` present with `mods:` already → replace the leaf.
///
/// Plus `value == null`: remove the leaf when present (otherwise
/// no-op — absence is already the canonical form).
String setLoaderMods(String yamlText, {required String? value}) {
  final editor = YamlEditor(yamlText);
  final root = parseYamlRoot(editor, filename: 'mods.yaml');
  final loaderNode = root.nodes['loader'];

  if (value == null) {
    if (loaderNode is YamlMap && loaderNode.containsKey('mods')) {
      editor.remove(['loader', 'mods']);
    }
    return editor.toString();
  }

  if (loaderNode == null || loaderNode.value == null) {
    editor.update(['loader'], {'mods': value});
  } else {
    editor.update(['loader', 'mods'], value);
  }
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
}) => rewriteEntryVersion(
  yamlText,
  section: section,
  slug: slug,
  version: newVersion,
  missingVersionAction: 'rewrite version',
);
