part of '../parser.dart';

/// Parses the `loader:` block from `mods.yaml`.
///
/// Asymmetries vs. the lock-file parser:
///   * `loader.mods` is optional and defaults to [ModLoader.vanilla]
///     (the "no mod runtime" sentinel).
///   * `loader.plugins` is the declared vocabulary
///     ([DeclaredPluginLoader]: bukkit, folia, paper, spigot, sponge);
///     the concrete Sponge distribution is resolved here from
///     `loader.mods` and stored in the returned [LoaderConfig] as one
///     of the seven [PluginLoader] values.
LoaderConfig _parseLoaderConfigYaml(dynamic raw, String filePath) {
  if (raw == null) {
    // `loader:` omitted entirely — equivalent to an empty mapping
    // (vanilla mods, no shaders, no plugins).
    return const LoaderConfig(mods: ModLoader.vanilla, modsVersion: null);
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
  String? modsVersion;
  if (map.containsKey('mods')) {
    final modsTag = _parseYamlModLoader(map['mods'], filePath);
    modsLoader = modsTag.loader;
    modsVersion = modsTag.version;
  } else {
    modsLoader = ModLoader.vanilla;
    modsVersion = null;
  }

  ShaderLoader? shaders;
  if (map.containsKey('shaders')) {
    shaders = _parseShaderLoader(map['shaders'], filePath);
  }

  PluginLoader? plugins;
  if (map.containsKey('plugins')) {
    final declared = _parseDeclaredPluginLoader(map['plugins'], filePath);
    plugins = declared.resolveWith(modsLoader);
  }

  return LoaderConfig(
    mods: modsLoader,
    modsVersion: modsVersion,
    shaders: shaders,
    plugins: plugins,
  );
}

/// Parses the `loader:` block from `mods.lock`. Lock-file values are
/// the *resolved* shape: `loader.plugins` is one of the seven
/// [PluginLoader] values and `loader.mods` carries the resolved
/// version (or is omitted / `vanilla` with no version).
LoaderConfig _parseLoaderConfigLock(dynamic raw, String filePath) {
  if (raw == null) {
    return const LoaderConfig(mods: ModLoader.vanilla, modsVersion: null);
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
  String? modsVersion;
  if (map.containsKey('mods')) {
    final modsTag = _parseLockModLoader(map['mods'], filePath);
    modsLoader = modsTag.loader;
    modsVersion = modsTag.version;
  } else {
    modsLoader = ModLoader.vanilla;
    modsVersion = null;
  }

  ShaderLoader? shaders;
  if (map.containsKey('shaders')) {
    shaders = _parseShaderLoader(map['shaders'], filePath);
  }

  PluginLoader? plugins;
  if (map.containsKey('plugins')) {
    plugins = _parseResolvedPluginLoader(map['plugins'], filePath);
  }

  return LoaderConfig(
    mods: modsLoader,
    modsVersion: modsVersion,
    shaders: shaders,
    plugins: plugins,
  );
}

class _ModLoaderTag {
  final ModLoader loader;
  final String? version;
  const _ModLoaderTag(this.loader, this.version);
}

/// Parses a `loader.mods` value from `mods.yaml`. Defaults a missing
/// tag on a real loader to `stable`; vanilla has no tag.
_ModLoaderTag _parseYamlModLoader(dynamic raw, String filePath) {
  final (loader, tag) = parseLoaderRef(
    raw.toString(),
    (msg) => throw _err('$filePath: loader.mods $msg'),
  );
  return _ModLoaderTag(
    loader,
    loader == ModLoader.vanilla ? null : (tag ?? 'stable'),
  );
}

/// Parses a `loader.mods` value from `mods.lock`. Same syntax as the
/// yaml form, but a missing tag on a real loader is preserved as-is
/// (older locks may have been written before the resolver existed).
_ModLoaderTag _parseLockModLoader(dynamic raw, String filePath) {
  final (loader, tag) = parseLoaderRef(
    raw.toString(),
    (msg) => throw _err('$filePath: loader.mods $msg'),
  );
  return _ModLoaderTag(
    loader,
    loader == ModLoader.vanilla ? null : (tag ?? 'stable'),
  );
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

/// User-facing plugin-loader parser for `mods.yaml`. The three Sponge
/// distributions are no longer accepted here — they're resolved from
/// the declared [DeclaredPluginLoader.sponge] plus `loader.mods`.
DeclaredPluginLoader _parseDeclaredPluginLoader(dynamic raw, String filePath) {
  final lower = raw.toString().toLowerCase();
  switch (lower) {
    case 'bukkit':
      return DeclaredPluginLoader.bukkit;
    case 'folia':
      return DeclaredPluginLoader.folia;
    case 'paper':
      return DeclaredPluginLoader.paper;
    case 'spigot':
      return DeclaredPluginLoader.spigot;
    case 'sponge':
      return DeclaredPluginLoader.sponge;
    default:
      throw _err(
        '$filePath: loader.plugins "$raw" is not recognized '
        '(allowed: bukkit, folia, paper, spigot, sponge).',
      );
  }
}

/// Lock-file plugin-loader parser. Reads the resolved seven-value
/// vocabulary verbatim — no resolution happens at lock-read time.
PluginLoader _parseResolvedPluginLoader(dynamic raw, String filePath) {
  final lower = raw.toString().toLowerCase();
  switch (lower) {
    case 'bukkit':
      return PluginLoader.bukkit;
    case 'folia':
      return PluginLoader.folia;
    case 'paper':
      return PluginLoader.paper;
    case 'spigot':
      return PluginLoader.spigot;
    case 'spongeforge':
      return PluginLoader.spongeforge;
    case 'spongeneo':
      return PluginLoader.spongeneo;
    case 'spongevanilla':
      return PluginLoader.spongevanilla;
    default:
      throw _err(
        '$filePath: loader.plugins "$raw" is not a recognized resolved '
        'plugin loader (lockfile vocabulary: bukkit, folia, paper, '
        'spigot, spongeforge, spongeneo, spongevanilla).',
      );
  }
}
