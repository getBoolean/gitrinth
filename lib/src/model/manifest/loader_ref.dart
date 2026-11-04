import 'mods_yaml.dart';

/// Loader names accepted by [parseModLoaderRef].
/// `vanilla` stays last because it is the no-mod-runtime sentinel.
const List<String> modLoaderRefNames = [
  'forge',
  'fabric',
  'neoforge',
  'quilt',
  'vanilla',
];

/// Plugin loader names accepted in `mods.yaml` and `create --plugin-loader`.
const List<String> pluginLoaderRefNames = [
  'bukkit',
  'folia',
  'paper',
  'spigot',
  'sponge',
];

/// Result of the syntax-only tagged-reference parser.
typedef TaggedRef = (String name, String? tag);

/// Parses a generic `<name>` or `<name>:<tag>` reference.
///
/// This deliberately knows nothing about Minecraft loaders. Callers map
/// [name] to its validated identity and decide whether [tag] is allowed or defaulted.
TaggedRef parseTaggedRef(String raw, Never Function(String message) onError) {
  final colon = raw.indexOf(':');
  final namePart = (colon < 0 ? raw : raw.substring(0, colon)).toLowerCase();
  final tagPart = colon < 0 ? null : raw.substring(colon + 1);

  if (namePart.isEmpty) {
    onError(
      '"$raw" has an empty name '
      '(use `<loader>` or `<loader>:<version|stable|latest>`).',
    );
  }

  if (tagPart != null) {
    if (tagPart.isEmpty) {
      onError(
        '"$raw" has an empty version tag '
        '(use `<loader>` or `<loader>:<version|stable|latest>`).',
      );
    }
    if (tagPart.contains(':')) {
      onError(
        '"$raw" has more than one `:` '
        '(expected `<loader>` or `<loader>:<version|stable|latest>`).',
      );
    }
  }

  return (namePart, tagPart);
}

/// Result of [parseModLoaderRef].
/// For [ModLoader.vanilla], the tag is always `null`.
typedef LoaderRef = (ModLoader loader, String? tag);

/// Parses a `loader` or `loader:tag` reference.
/// Shared by `mods.yaml`, `migrate loader`, and `create --mod-loader`.
/// Missing tags return `null`; callers choose their own default.
LoaderRef parseModLoaderRef(
  String raw,
  Never Function(String message) onError,
) {
  final (namePart, tagPart) = parseTaggedRef(raw, onError);
  if (namePart == 'vanilla') {
    if (tagPart != null) {
      onError(
        '"$raw" must not carry a version tag '
        '(write `vanilla` or omit it entirely).',
      );
    }
    return (ModLoader.vanilla, null);
  }

  final id = _parseId(namePart, onError);
  final role = LoaderRegistry.builtins[id]?.role;
  if (role != null && role != LoaderRole.mod) {
    onError('"$namePart" is not a mod loader.');
  }
  return (id, tagPart);
}

LoaderId _parseId(String raw, Never Function(String) onError) {
  try {
    return LoaderId(raw);
  } on FormatException catch (e) {
    onError(e.message);
  }
}

/// Result of [parseDeclaredPluginLoaderRef].
typedef DeclaredPluginLoaderRef = (DeclaredPluginLoader loader, String? tag);

/// Parses the plugin-loader vocabulary accepted in `mods.yaml`.
DeclaredPluginLoaderRef parseDeclaredPluginLoaderRef(
  String raw,
  Never Function(String message) onError,
) {
  final (namePart, tagPart) = parseTaggedRef(raw, onError);
  if (const {'spongeforge', 'spongeneo', 'spongevanilla'}.contains(namePart)) {
    onError(
      '"$namePart" is a resolved lockfile plugin loader; write `sponge` in mods.yaml instead.',
    );
  }
  final id = _parseId(namePart, onError);
  final role = LoaderRegistry.builtins[id]?.role;
  if (role != null && role != LoaderRole.plugin) {
    onError('"$namePart" is not a plugin loader.');
  }
  return (id, tagPart);
}

/// Result of [parseResolvedPluginLoaderRef].
typedef ResolvedPluginLoaderRef = (PluginLoader loader, String? tag);

/// Parses the resolved plugin-loader vocabulary stored in `mods.lock`.
ResolvedPluginLoaderRef parseResolvedPluginLoaderRef(
  String raw,
  Never Function(String message) onError,
) {
  final (namePart, tagPart) = parseTaggedRef(raw, onError);
  return (_parseId(namePart, onError), tagPart);
}
