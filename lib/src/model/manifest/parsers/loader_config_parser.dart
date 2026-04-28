part of '../parser.dart';

/// Parses the `loader:` block from `mods.yaml`.
/// `loader.mods` defaults to [ModLoader.vanilla].
/// `loader.plugins` uses the declared vocabulary and resolves Sponge
/// against `loader.mods`.
LoaderConfig _parseLoaderConfigYaml(dynamic raw, String filePath) {
  if (raw == null) {
    // Missing `loader:` is equivalent to an empty mapping.
    return const LoaderConfig(mods: ModLoader.vanilla, modsLoaderVersion: null);
  }
  if (raw is! Map) {
    throw _err(
      '$filePath: loader must be an object (e.g. '
      '`loader: { mods: neoforge }`). The scalar form is no longer '
      'supported.',
    );
  }
  final map = _toPlainMap(raw);
  const allowed = {'mods', 'shaders', 'plugins'};
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw _err(
        '$filePath: loader key "$key" is not recognized '
        '(allowed: mods, shaders, plugins).',
      );
    }
  }

  ModLoader modsLoader;
  String? modsLoaderVersion;
  if (map.containsKey('mods')) {
    final modsTag = _parseYamlModLoader(map['mods'], filePath);
    modsLoader = modsTag.loader;
    modsLoaderVersion = modsTag.version;
  } else {
    modsLoader = ModLoader.vanilla;
    modsLoaderVersion = null;
  }

  ShaderLoader? shaders;
  if (map.containsKey('shaders')) {
    shaders = _parseShaderLoader(map['shaders'], filePath);
  }

  PluginLoader? plugins;
  String? pluginLoaderVersion;
  if (map.containsKey('plugins')) {
    final pluginTag = _parseYamlPluginLoader(map['plugins'], filePath);
    plugins = pluginTag.loader.resolveWith(modsLoader);
    pluginLoaderVersion = pluginTag.version;
  }

  return LoaderConfig(
    mods: modsLoader,
    modsLoaderVersion: modsLoaderVersion,
    shaders: shaders,
    plugins: plugins,
    pluginLoaderVersion: pluginLoaderVersion,
  );
}

/// Parses the `loader:` block from `mods.lock`.
/// Lock values are already resolved.
LoaderConfig _parseLoaderConfigLock(dynamic raw, String filePath) {
  if (raw == null) {
    return const LoaderConfig(mods: ModLoader.vanilla, modsLoaderVersion: null);
  }
  if (raw is! Map) {
    throw _err('$filePath: loader must be an object.');
  }
  final map = _toPlainMap(raw);
  const allowed = {'mods', 'shaders', 'plugins'};
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw _err(
        '$filePath: loader key "$key" is not recognized '
        '(allowed: mods, shaders, plugins).',
      );
    }
  }

  ModLoader modsLoader;
  String? modsLoaderVersion;
  if (map.containsKey('mods')) {
    final modsTag = _parseLockModLoader(map['mods'], filePath);
    modsLoader = modsTag.loader;
    modsLoaderVersion = modsTag.version;
  } else {
    modsLoader = ModLoader.vanilla;
    modsLoaderVersion = null;
  }

  ShaderLoader? shaders;
  if (map.containsKey('shaders')) {
    shaders = _parseShaderLoader(map['shaders'], filePath);
  }

  PluginLoader? plugins;
  String? pluginLoaderVersion;
  if (map.containsKey('plugins')) {
    final pluginTag = _parseLockPluginLoader(map['plugins'], filePath);
    plugins = pluginTag.loader;
    pluginLoaderVersion = pluginTag.version;
  }

  return LoaderConfig(
    mods: modsLoader,
    modsLoaderVersion: modsLoaderVersion,
    shaders: shaders,
    plugins: plugins,
    pluginLoaderVersion: pluginLoaderVersion,
  );
}

class _ModLoaderTag {
  final ModLoader loader;
  final String? version;
  const _ModLoaderTag(this.loader, this.version);
}

/// Parses `loader.mods` from `mods.yaml`.
/// Missing tags on real loaders default to `stable`.
_ModLoaderTag _parseYamlModLoader(dynamic raw, String filePath) {
  final (loader, tag) = parseModLoaderRef(
    raw.toString(),
    (msg) => throw _err('$filePath: loader.mods $msg'),
  );
  return _ModLoaderTag(
    loader,
    loader == ModLoader.vanilla ? null : (tag ?? 'stable'),
  );
}

/// Parses `loader.mods` from `mods.lock`.
/// Older locks may omit the tag.
_ModLoaderTag _parseLockModLoader(dynamic raw, String filePath) {
  final (loader, tag) = parseModLoaderRef(
    raw.toString(),
    (msg) => throw _err('$filePath: loader.mods $msg'),
  );
  return _ModLoaderTag(
    loader,
    loader == ModLoader.vanilla ? null : (tag ?? 'stable'),
  );
}

class _DeclaredPluginLoaderTag {
  final DeclaredPluginLoader loader;
  final String version;
  const _DeclaredPluginLoaderTag(this.loader, this.version);
}

/// Parses `loader.plugins` from `mods.yaml`.
/// Missing tags default to `stable`.
_DeclaredPluginLoaderTag _parseYamlPluginLoader(dynamic raw, String filePath) {
  final (loader, tag) = parseDeclaredPluginLoaderRef(
    raw.toString(),
    (msg) => throw _err('$filePath: loader.plugins $msg'),
  );
  return _DeclaredPluginLoaderTag(loader, tag ?? 'stable');
}

class _ResolvedPluginLoaderTag {
  final PluginLoader loader;
  final String version;
  const _ResolvedPluginLoaderTag(this.loader, this.version);
}

/// Parses `loader.plugins` from `mods.lock`.
/// Lock values must carry concrete resolved versions.
_ResolvedPluginLoaderTag _parseLockPluginLoader(dynamic raw, String filePath) {
  final (loader, tag) = parseResolvedPluginLoaderRef(
    raw.toString(),
    (msg) => throw _err('$filePath: loader.plugins $msg'),
  );
  if (tag == null) {
    throw _err(
      '$filePath: loader.plugins "${loader.name}" has no concrete plugin '
      'loader version; rerun `gitrinth get` to refresh mods.lock.',
    );
  }
  if (tag == 'stable' || tag == 'latest') {
    throw _err(
      '$filePath: loader.plugins "${loader.name}:$tag" is not concrete; '
      'rerun `gitrinth get` to refresh mods.lock.',
    );
  }
  return _ResolvedPluginLoaderTag(loader, tag);
}

ShaderLoader _parseShaderLoader(dynamic raw, String filePath) {
  final lower = raw.toString().toLowerCase();
  switch (lower) {
    case 'iris':
      return ShaderLoader.iris;
    case 'optifine':
      return ShaderLoader.optifine;
    case 'canvas':
      return ShaderLoader.canvas;
    case 'vanilla':
      return ShaderLoader.vanilla;
    default:
      throw _err(
        '$filePath: loader.shaders "$raw" is not recognized '
        '(allowed: iris, optifine, canvas, vanilla).',
      );
  }
}
