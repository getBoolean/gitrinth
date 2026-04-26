import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../cli/exceptions.dart';

/// Parses the top-level YAML node of [editor] and asserts it is a mapping.
/// Throws [UserError] with a [filename]-prefixed message when the YAML is
/// unparsable or the root is not a mapping.
YamlMap parseYamlRoot(YamlEditor editor, {required String filename}) {
  final YamlNode root;
  try {
    root = editor.parseAt(<Object>[]);
  } on Object {
    throw UserError('$filename is not valid YAML; cannot edit.');
  }
  if (root is! YamlMap) {
    throw UserError('$filename top-level must be a mapping.');
  }
  return root;
}
