import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import 'add_command_editor.dart';

/// Rewrites the constraint for `<section>.<slug>` in [yamlText] to
/// [newConstraint], preserving comments and formatting via `yaml_edit`.
///
/// Handles both short form (`slug: ^1.2.3`) and long form (`slug:\n
/// version: ^1.2.3\n ...`). Long-form entries without a `version:` key
/// (e.g. `url:` or `path:` sourced) are rejected — pinning a non-Modrinth
/// entry has no defined meaning.
String updateEntryConstraint(
  String yamlText, {
  required Section section,
  required String slug,
  required String newConstraint,
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
        'cannot (un)pin.',
      );
    }
    editor.update([sectionKey, slug, 'version'], newConstraint);
  } else {
    editor.update([sectionKey, slug], newConstraint);
  }

  return editor.toString();
}
