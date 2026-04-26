import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../cli/exceptions.dart';

/// Loads YAML from [text] and casts to [T]. Throws [ValidationError] on
/// parse failure, including [path] in the message so users can locate the
/// offending file.
T safeLoadYaml<T>(String text, {required String path}) {
  final Object? parsed;
  try {
    parsed = loadYaml(text);
  } on YamlException catch (e) {
    throw ValidationError('failed to parse YAML in $path: ${e.message}');
  }
  if (parsed is! T) {
    throw ValidationError(
      'expected ${T.toString()} at the root of $path, got ${parsed.runtimeType}',
    );
  }
  return parsed;
}

/// Decodes JSON from [text] and casts to [T]. Throws [ValidationError] on
/// parse failure or type mismatch, including [path] in the message.
T safeJsonDecode<T>(String text, {required String path}) {
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException catch (e) {
    throw ValidationError('failed to parse JSON in $path: ${e.message}');
  }
  if (parsed is! T) {
    throw ValidationError(
      'expected ${T.toString()} at the root of $path, got ${parsed.runtimeType}',
    );
  }
  return parsed;
}
