import 'package:yaml/yaml.dart';

import '../../cli/exceptions.dart';
import 'mods_lock.dart';
import 'mods_overrides.dart';
import 'mods_yaml.dart';

class _ParseError extends ValidationError {
  const _ParseError(super.message);
}

ValidationError _err(String message) => _ParseError(message);

ModsYaml parseModsYaml(String yamlText, {required String filePath}) {
  final dynamic raw;
  try {
    raw = loadYaml(yamlText);
  } on YamlException catch (e) {
    throw _err('Invalid YAML in $filePath: ${e.message}');
  }
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  final map = _toPlainMap(raw);

  final slug = _requireString(map, 'slug', filePath);
  final name = _requireString(map, 'name', filePath);
  final version = _requireString(map, 'version', filePath);
  final description = _requireString(map, 'description', filePath);
  final loader = _parseLoader(map['loader'], filePath);
  final mcVersion = _requireString(map, 'mc-version', filePath);

  return ModsYaml(
    slug: slug,
    name: name,
    version: version,
    description: description,
    loader: loader,
    mcVersion: mcVersion,
    mods: _parseSection(map['mods'], 'mods', filePath, allowEnv: true),
    resourcePacks: _parseSection(
      map['resource_packs'],
      'resource_packs',
      filePath,
      allowEnv: true,
    ),
    dataPacks: _parseSection(
      map['data_packs'],
      'data_packs',
      filePath,
      allowEnv: true,
    ),
    shaders: _parseSection(
      map['shaders'],
      'shaders',
      filePath,
      allowEnv: false,
      forcedEnv: Environment.client,
    ),
    overrides: _parseSection(
      map['overrides'],
      'overrides',
      filePath,
      allowEnv: true,
    ),
  );
}

ModsOverrides parseModsOverrides(String yamlText, {required String filePath}) {
  final raw = yamlText.trim().isEmpty ? null : loadYaml(yamlText);
  if (raw == null) return const ModsOverrides();
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  final map = _toPlainMap(raw);
  final overridesRaw = map['overrides'];
  if (overridesRaw == null) return const ModsOverrides();
  return ModsOverrides(
    overrides: _parseSection(overridesRaw, 'overrides', filePath, allowEnv: true),
  );
}

ModsLock parseModsLock(String yamlText, {required String filePath}) {
  final dynamic raw;
  try {
    raw = loadYaml(yamlText);
  } on YamlException catch (e) {
    throw _err('Invalid YAML in $filePath: ${e.message}');
  }
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  final map = _toPlainMap(raw);
  final gitrinthVersion = _requireString(map, 'gitrinth-version', filePath);
  final loader = _parseLoader(map['loader'], filePath);
  final mcVersion = _requireString(map, 'mc-version', filePath);
  return ModsLock(
    gitrinthVersion: gitrinthVersion,
    loader: loader,
    mcVersion: mcVersion,
    mods: _parseLockSection(map['mods'], 'mods', filePath),
    resourcePacks: _parseLockSection(
      map['resource_packs'],
      'resource_packs',
      filePath,
    ),
    dataPacks: _parseLockSection(map['data_packs'], 'data_packs', filePath),
    shaders: _parseLockSection(map['shaders'], 'shaders', filePath),
  );
}

Map<String, LockedEntry> _parseLockSection(
  dynamic raw,
  String sectionName,
  String filePath,
) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw _err('$filePath: $sectionName must be a mapping.');
  }
  final result = <String, LockedEntry>{};
  raw.forEach((key, value) {
    final slug = key?.toString();
    if (slug == null || slug.isEmpty) {
      throw _err('$filePath: $sectionName has an empty key.');
    }
    if (value is! Map) {
      throw _err('$filePath: $sectionName/$slug must be a mapping.');
    }
    final m = _toPlainMap(value);
    final sourceKind = _parseLockSourceKind(m['source'], sectionName, slug, filePath);
    final env = _parseEnv(m['env'] ?? 'both', '$sectionName/$slug', filePath);
    final auto = m['auto'] == true;
    LockedFile? file;
    final fileRaw = m['file'];
    if (fileRaw != null) {
      if (fileRaw is! Map) {
        throw _err('$filePath: $sectionName/$slug file must be a mapping.');
      }
      final fm = _toPlainMap(fileRaw);
      file = LockedFile(
        name: (fm['name'] as String?) ?? '',
        url: fm['url'] as String?,
        sha512: (fm['sha512'] as String?)?.toLowerCase(),
        size: fm['size'] is int ? fm['size'] as int : (fm['size'] as num?)?.toInt(),
      );
    }
    result[slug] = LockedEntry(
      slug: slug,
      sourceKind: sourceKind,
      version: m['version'] as String?,
      projectId: m['project-id'] as String?,
      versionId: m['version-id'] as String?,
      file: file,
      path: m['path'] as String?,
      env: env,
      auto: auto,
    );
  });
  return result;
}

LockedSourceKind _parseLockSourceKind(
  dynamic raw,
  String sectionName,
  String slug,
  String filePath,
) {
  switch (raw?.toString()) {
    case 'modrinth':
      return LockedSourceKind.modrinth;
    case 'url':
      return LockedSourceKind.url;
    case 'path':
      return LockedSourceKind.path;
    default:
      throw _err(
        '$filePath: $sectionName/$slug source "$raw" must be one of '
        'modrinth, url, path.',
      );
  }
}

Map<String, ModEntry> _parseSection(
  dynamic raw,
  String sectionName,
  String filePath, {
  required bool allowEnv,
  Environment? forcedEnv,
}) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw _err('$filePath: $sectionName must be a mapping.');
  }
  final result = <String, ModEntry>{};
  raw.forEach((key, value) {
    final slug = key?.toString();
    if (slug == null || slug.isEmpty) {
      throw _err('$filePath: $sectionName has an empty key.');
    }
    result[slug] = _parseEntry(
      slug,
      value,
      sectionName,
      filePath,
      allowEnv: allowEnv,
      forcedEnv: forcedEnv,
    );
  });
  return result;
}

ModEntry _parseEntry(
  String slug,
  dynamic raw,
  String sectionName,
  String filePath, {
  required bool allowEnv,
  Environment? forcedEnv,
}) {
  // Short forms: null (latest), or a scalar version constraint.
  if (raw == null) {
    return ModEntry(slug: slug, constraintRaw: null, env: forcedEnv ?? Environment.both);
  }
  if (raw is String || raw is num || raw is bool) {
    return ModEntry(
      slug: slug,
      constraintRaw: raw.toString(),
      env: forcedEnv ?? Environment.both,
    );
  }
  if (raw is! Map) {
    throw _err(
      '$filePath: $sectionName/$slug must be a scalar version or a mapping.',
    );
  }
  final m = _toPlainMap(raw);
  final hosted = m['hosted'];
  final url = m['url'];
  final path = m['path'];
  final sourceCount =
      (hosted == null ? 0 : 1) + (url == null ? 0 : 1) + (path == null ? 0 : 1);
  if (sourceCount > 1) {
    throw _err(
      '$filePath: $sectionName/$slug declares more than one of '
      'hosted/url/path. Choose at most one.',
    );
  }
  if (hosted != null) {
    throw const UserError(
      'hosted source is deferred; use a default-Modrinth slug, url:, or path:.',
    );
  }
  EntrySource source = const ModrinthEntrySource();
  if (url != null) {
    if (url is! String || url.isEmpty) {
      throw _err('$filePath: $sectionName/$slug url must be a non-empty string.');
    }
    source = UrlEntrySource(url: url);
  } else if (path != null) {
    if (path is! String || path.isEmpty) {
      throw _err('$filePath: $sectionName/$slug path must be a non-empty string.');
    }
    source = PathEntrySource(path: path);
  }

  final versionRaw = m['version'];
  final constraintRaw = versionRaw?.toString();

  Environment env = forcedEnv ?? Environment.both;
  final envRaw = m['environment'];
  if (envRaw != null) {
    if (!allowEnv) {
      throw _err(
        '$filePath: $sectionName/$slug must not declare environment '
        '(this section has a fixed side).',
      );
    }
    env = _parseEnv(envRaw, '$sectionName/$slug', filePath);
  }
  if (forcedEnv != null) env = forcedEnv;

  return ModEntry(slug: slug, constraintRaw: constraintRaw, env: env, source: source);
}

Loader _parseLoader(dynamic raw, String filePath) {
  if (raw == null) {
    throw _err('$filePath: loader is required.');
  }
  final lower = raw.toString().toLowerCase();
  switch (lower) {
    case 'forge':
      return Loader.forge;
    case 'fabric':
      return Loader.fabric;
    case 'neoforge':
      return Loader.neoforge;
    default:
      throw _err(
        '$filePath: loader "$raw" is not supported in MVP '
        '(allowed: forge, fabric, neoforge).',
      );
  }
}

Environment _parseEnv(dynamic raw, String where, String filePath) {
  switch (raw.toString()) {
    case 'client':
      return Environment.client;
    case 'server':
      return Environment.server;
    case 'both':
      return Environment.both;
    default:
      throw _err(
        '$filePath: $where environment "$raw" must be one of client, server, both.',
      );
  }
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
