import 'package:yaml/yaml.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import 'add_command_editor.dart';

/// Removes the entry keyed by [slug] from [section] inside [yamlText],
/// preserving comments and surrounding whitespace.
///
/// Implemented via span-based text surgery (not `yaml_edit`) because
/// `YamlEditor.remove` eats the trailing blank-line separator when the
/// removed entry is the last in its block, collapsing visually-distinct
/// sections into each other. We splice out only the entry's own lines
/// and leave everything around them alone.
String removeEntry(
  String yamlText, {
  required Section section,
  required String slug,
}) {
  final sectionKey = sectionKeyFor(section);

  final YamlNode root;
  try {
    root = loadYamlNode(yamlText);
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

  MapEntry<dynamic, YamlNode>? target;
  for (final entry in sectionNode.nodes.entries) {
    final keyNode = entry.key as YamlNode;
    if (keyNode.value == slug) {
      target = entry;
      break;
    }
  }
  if (target == null) {
    throw UserError("'$slug' not found under '$sectionKey' in mods.yaml.");
  }

  final keyNode = target.key as YamlNode;
  final valueNode = target.value;

  var lineStart = keyNode.span.start.offset;
  while (lineStart > 0 && yamlText[lineStart - 1] != '\n') {
    lineStart--;
  }

  var lineEnd = valueNode.span.end.offset;
  while (lineEnd < yamlText.length && yamlText[lineEnd] != '\n') {
    lineEnd++;
  }
  if (lineEnd < yamlText.length) lineEnd++;

  return yamlText.substring(0, lineStart) + yamlText.substring(lineEnd);
}
