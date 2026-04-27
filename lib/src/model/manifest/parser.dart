library;

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../cli/exceptions.dart';
import '../resolver/constraint.dart';
import 'file_entry.dart';
import 'loader_ref.dart';
import 'mods_lock.dart';
import 'mods_yaml.dart';
import 'project_overrides.dart';

part 'parsers/file_entry_parser.dart';
part 'parsers/loader_config_parser.dart';
part 'parsers/mod_entry_parser.dart';
part 'parsers/side_env_parser.dart';

class _ParseError extends ValidationError {
  const _ParseError(super.message);
}

ValidationError _err(String message) => _ParseError(message);

/// Decodes [yamlText] and asserts the top-level node is a mapping.
/// Returns the converted plain `Map<String, dynamic>` so callers don't
/// repeat the `loadYaml` / `is! YamlMap` / `_toPlainMap` triplet.
Map<String, dynamic> _loadYamlMap(String yamlText, String filePath) {
  final dynamic raw;
  try {
    raw = loadYaml(yamlText);
  } on YamlException catch (e) {
    throw _err('Invalid YAML in $filePath: ${e.message}');
  }
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  return _toPlainMap(raw);
}

ModsYaml parseModsYaml(String yamlText, {required String filePath}) {
  final map = _loadYamlMap(yamlText, filePath);

  final slug = _requireString(map, 'slug', filePath);
  final name = _requireString(map, 'name', filePath);
  final version = _requireString(map, 'version', filePath);
  final description = _requireString(map, 'description', filePath);
  final loader = _parseLoaderConfigYaml(map['loader'], filePath);
  final mcVersion = _requireString(map, 'mc-version', filePath);

  final mods = _parseSection(map['mods'], 'mods', filePath, Section.mods);
  if (mods.isNotEmpty && !loader.hasModRuntime) {
    throw _err(
      "$filePath: mods: section has ${mods.length} "
      "${mods.length == 1 ? 'entry' : 'entries'} but loader.mods is "
      'not set. Declare a mod loader (forge / fabric / neoforge), or '
      'remove the mods entries.',
    );
  }
  final resourcePacks = _parseSection(
    map['resource_packs'],
    'resource_packs',
    filePath,
    Section.resourcePacks,
  );
  final dataPacks = _parseSection(
    map['data_packs'],
    'data_packs',
    filePath,
    Section.dataPacks,
  );
  final shaders = _parseSection(
    map['shaders'],
    'shaders',
    filePath,
    Section.shaders,
  );
  final plugins = _parseSection(
    map['plugins'],
    'plugins',
    filePath,
    Section.plugins,
  );
  // The legacy `overrides:` key was renamed to `project_overrides:`
  // in v2; surface a clear migration error rather than silently
  // ignoring the old section.
  if (map.containsKey('overrides')) {
    throw _err(
      "$filePath: 'overrides:' was renamed to 'project_overrides:' "
      "in v2. Rename the section in $filePath.",
    );
  }
  // project_overrides patches entries in any section; default per-side
  // state to mods-style required/required since that's the most
  // permissive baseline. Per-side fields on the override still win
  // when present.
  final projectOverrides = _parseSection(
    map['project_overrides'],
    'project_overrides',
    filePath,
    Section.mods,
  );
  final files = _parseFilesSection(map['files'], filePath);

  final publishToRaw = map['publish_to'];
  final String? publishTo;
  if (publishToRaw == null) {
    publishTo = null;
  } else if (publishToRaw is String) {
    final trimmed = publishToRaw.trim();
    publishTo = trimmed.isEmpty ? null : trimmed;
  } else {
    throw _err(
      "$filePath: 'publish_to' must be a string URL, 'none', or omitted.",
    );
  }

  if (shaders.isNotEmpty && loader.shaders == null) {
    throw _err(
      "$filePath: manifest has entries under 'shaders:' but no "
      "'loader.shaders' declared. Add e.g. `shaders: iris` under the "
      '`loader:` object.',
    );
  }

  if (plugins.isNotEmpty && loader.plugins == null) {
    throw _err(
      "$filePath: manifest has entries under 'plugins:' but no "
      "'loader.plugins' declared. Add e.g. `plugins: paper` under "
      'the `loader:` object.',
    );
  }

  final coercedMods = coerceModsForPluginLoader(mods, loader.plugins);

  return ModsYaml(
    slug: slug,
    name: name,
    version: version,
    description: description,
    loader: loader,
    mcVersion: mcVersion,
    mods: coercedMods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
    plugins: plugins,
    projectOverrides: projectOverrides,
    files: files,
    publishTo: publishTo,
  );
}

ProjectOverrides parseProjectOverrides(
  String yamlText, {
  required String filePath,
}) {
  final raw = yamlText.trim().isEmpty ? null : loadYaml(yamlText);
  if (raw == null) return const ProjectOverrides();
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  final map = _toPlainMap(raw);
  // Surface the v2 rename clearly: a standalone file still using the
  // old key is a configuration error, not a no-op.
  if (map.containsKey('overrides')) {
    throw _err(
      "$filePath: 'overrides:' was renamed to 'project_overrides:' "
      "in v2 (and the file itself was renamed from "
      "'mods_overrides.yaml' to 'project_overrides.yaml'). Rename "
      "both to migrate.",
    );
  }
  final entriesRaw = map['project_overrides'];
  if (entriesRaw == null) return const ProjectOverrides();
  return ProjectOverrides(
    entries: _parseSection(
      entriesRaw,
      'project_overrides',
      filePath,
      Section.mods,
    ),
  );
}

ModsLock parseModsLock(String yamlText, {required String filePath}) {
  final map = _loadYamlMap(yamlText, filePath);
  final gitrinthVersion = _requireString(map, 'gitrinth-version', filePath);
  final loader = _parseLoaderConfigLock(map['loader'], filePath);
  final mcVersion = _requireString(map, 'mc-version', filePath);
  final mods = _parseLockSection(map['mods'], 'mods', filePath);
  final resourcePacks = _parseLockSection(
    map['resource_packs'],
    'resource_packs',
    filePath,
  );
  final dataPacks = _parseLockSection(
    map['data_packs'],
    'data_packs',
    filePath,
  );
  final shaders = _parseLockSection(map['shaders'], 'shaders', filePath);
  final plugins = _parseLockSection(map['plugins'], 'plugins', filePath);
  final files = _parseLockFilesSection(map['files'], filePath);

  if (shaders.isNotEmpty && loader.shaders == null) {
    throw _err(
      "$filePath: lockfile has entries under 'shaders:' but no "
      "'loader.shaders' declared.",
    );
  }

  if (plugins.isNotEmpty && loader.plugins == null) {
    throw _err(
      "$filePath: lockfile has entries under 'plugins:' but no "
      "'loader.plugins' declared.",
    );
  }

  return ModsLock(
    gitrinthVersion: gitrinthVersion,
    loader: loader,
    mcVersion: mcVersion,
    mods: mods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
    plugins: plugins,
    files: files,
  );
}

String _requireString(Map<String, dynamic> map, String key, String filePath) {
  final value = map[key];
  if (value == null) {
    throw _err('$filePath: missing required field "$key".');
  }
  if (value is! String || value.isEmpty) {
    throw _err('$filePath: "$key" must be a non-empty string.');
  }
  return value;
}

Map<String, dynamic> _toPlainMap(Map yaml) {
  final out = <String, dynamic>{};
  yaml.forEach((k, v) {
    out[k.toString()] = _convert(v);
  });
  return out;
}

dynamic _convert(dynamic v) {
  if (v is YamlMap) return _toPlainMap(v);
  if (v is Map) return _toPlainMap(v);
  if (v is YamlList) return v.map(_convert).toList();
  if (v is List) return v.map(_convert).toList();
  return v;
}
