import 'package:dart_mappable/dart_mappable.dart';

import 'file_entry.dart';

part 'mods_yaml.mapper.dart';

@MappableEnum()
enum SpongeLoader { vanilla, forge, neoforge }

/// Mod loader the pack targets.
/// `vanilla` means no mod runtime.
@MappableEnum()
enum ModLoader { forge, fabric, neoforge, vanilla }

@MappableEnum()
enum ShaderLoader { iris, optifine, canvas, vanilla }

/// Resolved plugin loader stored in `mods.lock`.
/// `mods.yaml` uses [DeclaredPluginLoader]; the parser resolves it.
@MappableEnum()
enum PluginLoader {
  bukkit,
  folia,
  paper,
  spigot,
  spongeneo,
  spongeforge,
  spongevanilla,
}

/// Plugin loader as declared in `mods.yaml`.
/// Sponge variants are resolved later from `loader.mods`.
enum DeclaredPluginLoader { bukkit, folia, paper, spigot, sponge }

/// Runtime entry point for a built server distribution.
/// `null` means the loader uses `run.bat` / `run.sh`.
extension ModLoaderServerInvocation on ModLoader {
  String? get serverLaunchJar => switch (this) {
    ModLoader.vanilla => 'server.jar',
    ModLoader.fabric => 'fabric-server-launch.jar',
    ModLoader.forge || ModLoader.neoforge => null,
  };

  bool get usesServerRunScript => serverLaunchJar == null;
}

extension PluginLoaderToDeclared on PluginLoader {
  /// Maps a resolved [PluginLoader] back to the declared `mods.yaml` value.
  DeclaredPluginLoader toDeclared() => switch (this) {
    PluginLoader.bukkit => DeclaredPluginLoader.bukkit,
    PluginLoader.folia => DeclaredPluginLoader.folia,
    PluginLoader.paper => DeclaredPluginLoader.paper,
    PluginLoader.spigot => DeclaredPluginLoader.spigot,
    PluginLoader.spongeforge ||
    PluginLoader.spongeneo ||
    PluginLoader.spongevanilla => DeclaredPluginLoader.sponge,
  };
}

/// Resolves `(declared plugin loader, mod loader)` to [PluginLoader].
extension DeclaredPluginLoaderResolution on DeclaredPluginLoader {
  PluginLoader resolveWith(ModLoader mods) => switch (this) {
    DeclaredPluginLoader.bukkit => PluginLoader.bukkit,
    DeclaredPluginLoader.folia => PluginLoader.folia,
    DeclaredPluginLoader.paper => PluginLoader.paper,
    DeclaredPluginLoader.spigot => PluginLoader.spigot,
    DeclaredPluginLoader.sponge => switch (mods) {
      ModLoader.forge => PluginLoader.spongeforge,
      ModLoader.neoforge => PluginLoader.spongeneo,
      ModLoader.fabric || ModLoader.vanilla => PluginLoader.spongevanilla,
    },
  };
}

/// Per-loader behavior helpers.
extension PluginLoaderTraits on PluginLoader {
  /// True when this server platform also runs server-side mods.
  bool get runsServerMods =>
      this == PluginLoader.spongeforge || this == PluginLoader.spongeneo;

  /// Modrinth `loaders` filter token for this loader.
  String get modrinthLoaderToken => switch (this) {
    PluginLoader.spongeforge ||
    PluginLoader.spongeneo ||
    PluginLoader.spongevanilla => 'sponge',
    _ => name,
  };

  /// Mod loaders this plugin loader's server runtime accepts.
  Set<ModLoader> get compatibleModLoaders => switch (this) {
    PluginLoader.spongeforge ||
    PluginLoader.spongeneo => const {ModLoader.forge, ModLoader.neoforge},
    _ => const <ModLoader>{},
  };
}

/// Per-side install state.
@MappableEnum()
enum SideEnv {
  required,
  optional,
  unsupported;

  /// True when the entry contributes a file on this side.
  bool get includes => this != SideEnv.unsupported;
}

@MappableEnum()
enum Section { mods, resourcePacks, dataPacks, shaders, plugins }

/// Default per-side install state for [section].
({SideEnv client, SideEnv server}) defaultSidesFor(
  Section section,
) => switch (section) {
  Section.mods => (client: SideEnv.required, server: SideEnv.required),
  Section.shaders => (client: SideEnv.required, server: SideEnv.unsupported),
  Section.resourcePacks => (
    client: SideEnv.optional,
    server: SideEnv.unsupported,
  ),
  Section.dataPacks => (client: SideEnv.required, server: SideEnv.required),
  Section.plugins => (client: SideEnv.unsupported, server: SideEnv.required),
};

/// Forces `server: unsupported` for mods on pure plugin-server platforms.
Map<String, ModEntry> coerceModsForPluginLoader(
  Map<String, ModEntry> mods,
  PluginLoader? pluginLoader,
) {
  if (pluginLoader == null || pluginLoader.runsServerMods) {
    return mods;
  }
  return {
    for (final e in mods.entries)
      e.key: e.value.copyWith(server: SideEnv.unsupported),
  };
}

@MappableEnum()
enum Channel { release, beta, alpha }

/// Per-section loader configuration.
/// `mods.yaml` is declared; `mods.lock` is resolved.
@MappableClass()
class LoaderConfig with LoaderConfigMappable {
  final ModLoader mods;

  /// Mod-loader version tag.
  /// Declared in `mods.yaml`, resolved in `mods.lock`.
  final String? modLoaderVersion;
  final ShaderLoader? shaders;
  final PluginLoader? plugins;

  /// Plugin-loader version tag.
  /// Declared in `mods.yaml`, resolved in `mods.lock`.
  final String? pluginLoaderVersion;

  const LoaderConfig({
    required this.mods,
    this.modLoaderVersion = 'stable',
    this.shaders,
    this.plugins,
    this.pluginLoaderVersion,
  });

  /// True when the pack declares a real mod loader.
  bool get hasModRuntime => mods != ModLoader.vanilla;
}

@MappableClass(discriminatorKey: 'kind')
sealed class EntrySource with EntrySourceMappable {
  const EntrySource();
}

@MappableClass(discriminatorValue: 'modrinth')
class ModrinthEntrySource extends EntrySource with ModrinthEntrySourceMappable {
  const ModrinthEntrySource();
}

@MappableClass(discriminatorValue: 'url')
class UrlEntrySource extends EntrySource with UrlEntrySourceMappable {
  final String url;
  const UrlEntrySource({required this.url});
}

@MappableClass(discriminatorValue: 'path')
class PathEntrySource extends EntrySource with PathEntrySourceMappable {
  final String path;
  const PathEntrySource({required this.path});
}

@MappableClass()
class ModEntry with ModEntryMappable {
  final String slug;
  final String? constraintRaw;
  final Channel? channel;

  /// Install state on the client side. The parser sets this from the
  /// entry's `client:` field, defaulting per [defaultSidesFor].
  final SideEnv client;

  /// Install state on the server side. The parser sets this from the
  /// entry's `server:` field, defaulting per [defaultSidesFor].
  final SideEnv server;

  final EntrySource source;

  /// Additional Minecraft versions to union with the pack's `mc-version`
  /// when querying Modrinth for this entry. Query-time only; does not
  /// influence pack-level decisions.
  final List<String> acceptsMc;

  const ModEntry({
    required this.slug,
    this.constraintRaw,
    this.channel,
    this.client = SideEnv.required,
    this.server = SideEnv.required,
    this.source = const ModrinthEntrySource(),
    this.acceptsMc = const [],
  });
}

@MappableClass()
class ModsYaml with ModsYamlMappable {
  final String slug;
  final String name;
  final String version;
  final String description;
  final LoaderConfig loader;
  final String mcVersion;
  final Map<String, ModEntry> mods;
  final Map<String, ModEntry> resourcePacks;
  final Map<String, ModEntry> dataPacks;
  final Map<String, ModEntry> shaders;
  final Map<String, ModEntry> plugins;
  final Map<String, ModEntry> projectOverrides;

  /// Loose file declarations from the top-level `files:` section.
  /// Keyed by destination path (relative to the build env root).
  /// Outside the [Section] taxonomy because they don't flow through
  /// pubgrub, mrpack `files[]` resolution, or the globalpacks tree.
  final Map<String, FileEntry> files;

  /// Modrinth-compatible server URL `gitrinth modrinth publish`
  /// uploads to. `null` means the default (modrinth.com); the literal
  /// string `none` means publishing is disabled for this pack.
  final String? publishTo;

  const ModsYaml({
    required this.slug,
    required this.name,
    required this.version,
    required this.description,
    required this.loader,
    required this.mcVersion,
    this.mods = const {},
    this.resourcePacks = const {},
    this.dataPacks = const {},
    this.shaders = const {},
    this.plugins = const {},
    this.projectOverrides = const {},
    this.files = const {},
    this.publishTo,
  });

  Map<String, ModEntry> sectionEntries(Section section) {
    switch (section) {
      case Section.mods:
        return mods;
      case Section.resourcePacks:
        return resourcePacks;
      case Section.dataPacks:
        return dataPacks;
      case Section.shaders:
        return shaders;
      case Section.plugins:
        return plugins;
    }
  }
}
