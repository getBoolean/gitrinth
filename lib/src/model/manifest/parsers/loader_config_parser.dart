part of '../parser.dart';

LoaderConfig _parseLoaderConfig(dynamic raw, String filePath) {
  if (raw == null) {
    throw _err('$filePath: loader is required.');
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

  final modsRaw = map['mods'];
  if (modsRaw == null) {
    throw _err('$filePath: loader.mods is required (e.g. `mods: neoforge`).');
  }
  final modsTag = _parseModLoader(modsRaw, filePath);

  ShaderLoader? shaders;
  if (map.containsKey('shaders')) {
    shaders = _parseShaderLoader(map['shaders'], filePath);
  }

  if (map.containsKey('plugins')) {
    throw _err(
      '$filePath: plugin loader support is deferred; remove '
      '`loader.plugins` until the MVP lands it.',
    );
  }

  return LoaderConfig(
    mods: modsTag.loader,
    modsVersion: modsTag.version,
    shaders: shaders,
  );
}

class _ModLoaderTag {
  final Loader loader;
  final String version;
  const _ModLoaderTag(this.loader, this.version);
}

/// Parses a `loader.mods` value of the form `<name>` or `<name>:<tag>`.
/// Bare `<name>` defaults the tag to `stable`. The tag is `stable`,
/// `latest`, or a concrete version string (validated against Modrinth at
/// resolve time, not here).
_ModLoaderTag _parseModLoader(dynamic raw, String filePath) {
  final asString = raw.toString();
  final colon = asString.indexOf(':');
  final namePart = (colon < 0 ? asString : asString.substring(0, colon))
      .toLowerCase();
  final tagPart = colon < 0 ? 'stable' : asString.substring(colon + 1);
  if (tagPart.isEmpty) {
    throw _err(
      '$filePath: loader.mods "$asString" has an empty version tag '
      '(use `<loader>` or `<loader>:<version|stable|latest>`).',
    );
  }
  if (tagPart.contains(':')) {
    throw _err(
      '$filePath: loader.mods "$asString" has more than one `:` '
      '(expected `<loader>` or `<loader>:<version|stable|latest>`).',
    );
  }
  Loader loader;
  switch (namePart) {
    case 'forge':
      loader = Loader.forge;
      break;
    case 'fabric':
      loader = Loader.fabric;
      break;
    case 'neoforge':
      loader = Loader.neoforge;
      break;
    default:
      throw _err(
        '$filePath: loader.mods "$namePart" is not supported in MVP '
        '(allowed: forge, fabric, neoforge).',
      );
  }
  return _ModLoaderTag(loader, tagPart);
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
