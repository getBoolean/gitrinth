import 'package:dart_mappable/dart_mappable.dart';

import 'file_entry.dart';

part 'mods_yaml.mapper.dart';

@MappableEnum()
enum SpongeLoader { vanilla, forge, neoforge }

/// Mod loader the modpack targets. `vanilla` is the "no mod runtime"
/// sentinel: chosen when `loader.mods` is omitted in `mods.yaml`. Under
/// `vanilla`, the `mods:` section must be empty (parser-enforced).
@MappableEnum()
enum ModLoader { forge, fabric, neoforge, vanilla }

@MappableEnum()
enum ShaderLoader { iris, optifine, canvas, vanilla }

/// Resolved plugin loader stored in `mods.lock` and used by every
/// downstream system (server-jar selection, Modrinth filter, side
/// coercion, pack assembly). User-facing `mods.yaml` declares the
/// coarser [DeclaredPluginLoader]; the parser resolves it to one of
/// these seven values using `loader.mods` as input.
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

/// Plugin loader as declared in `mods.yaml`. The three Sponge
/// distributions (`spongeforge`, `spongeneo`, `spongevanilla`) are not
/// distinguished here — the concrete distribution is a function of
/// `loader.mods` and is resolved at parse time. This enum never
/// appears in [LoaderConfig] or in the lock model.
enum DeclaredPluginLoader { bukkit, folia, paper, spigot, sponge }

/// Runtime entry point for a built server distribution under
/// `build/server/`. `null` means the loader uses an installer-emitted
/// run script (`run.bat` / `run.sh`) rather than a single jar.
///
/// This is *not* a cache key. The artifact filename written into the
/// cache by `gitrinth get` is computed elsewhere (see
/// `_expectedCachedInstallerPath` in `build_orchestrator.dart` and
/// `LoaderBinaryFetcher`); some loaders ship the same name in both
/// places (fabric) and some don't (forge/neoforge installer JAR vs
/// run script).
extension ModLoaderServerInvocation on ModLoader {
  String? get serverLaunchJar => switch (this) {
    ModLoader.vanilla => 'server.jar',
    ModLoader.fabric => 'fabric-server-launch.jar',
    ModLoader.forge || ModLoader.neoforge => null,
  };

  bool get usesServerRunScript => serverLaunchJar == null;
}

extension PluginLoaderToDeclared on PluginLoader {
  /// Maps a resolved [PluginLoader] back to the value that should be
  /// written to `mods.yaml`. Used by writers (`add_command_editor`,
  /// `migrate_command`, scaffolder) so the user-facing manifest stays
  /// in the declared vocabulary.
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

/// Single source of truth for the (declared, mods) → resolved
/// [PluginLoader] mapping. Pairs with [PluginLoaderToDeclared.toDeclared]
/// for the round-trip; called from the yaml parser and from
/// `migrate loader` when re-resolving a sponge pack under a new mod
/// loader.
///
///   declared    loader.mods   resolved
///   ─────────   ───────────   ────────────────
///   bukkit      *             bukkit
///   folia       *             folia
///   paper       *             paper
///   spigot      *             spigot
///   sponge      forge         spongeforge
///   sponge      neoforge      spongeneo
///   sponge      fabric        spongevanilla   (server is SpongeVanilla;
///                                              client-side fabric mods
///                                              coerce to server-unsupported)
///   sponge      vanilla       spongevanilla
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

/// Per-loader behavior knobs. Single source of truth for every
/// plugin-loader-specific decision — call sites read these properties
/// instead of switching on [PluginLoader] themselves.
extension PluginLoaderTraits on PluginLoader {
  /// True when this server platform also runs server-side mods.
  /// `spongeforge` and `spongeneo` layer on Forge / NeoForge so mods
  /// load normally; the bukkit family and `spongevanilla` do not load
  /// mods at all.
  bool get runsServerMods =>
      this == PluginLoader.spongeforge || this == PluginLoader.spongeneo;

  /// Modrinth `loaders` filter token for this loader. Modrinth tags
  /// every Sponge plugin with the single category `sponge` regardless
  /// of which Sponge distribution loads it, so the three Sponge values
  /// collapse to that token; everything else matches the enum name.
  String get modrinthLoaderToken => switch (this) {
    PluginLoader.spongeforge ||
    PluginLoader.spongeneo ||
    PluginLoader.spongevanilla => 'sponge',
    _ => name,
  };

  /// Mod loaders this plugin loader's server runtime accepts. Empty
  /// means the server is a pure plugin server (no mods load on the
  /// server). Informational — the parser no longer uses this to
  /// validate user input; the (declared, mods) -> resolved mapping
  /// supersedes that check.
  Set<ModLoader> get compatibleModLoaders => switch (this) {
    PluginLoader.spongeforge ||
    PluginLoader.spongeneo => const {ModLoader.forge, ModLoader.neoforge},
    _ => const <ModLoader>{},
  };
}

/// Per-side install state. Mirrors the values mrpack's per-file `env`
/// block uses, so `.mrpack` output can pass these through verbatim.
///
/// `required` — installed and mandatory.
/// `optional` — installed but user-toggleable (launcher shows a switch).
/// `unsupported` — not installed on this side at all.
@MappableEnum()
enum SideEnv {
  required,
  optional,
  unsupported;

  /// True when the entry contributes a file on this side (either
  /// `required` or `optional`). Used to gate build output and to compute
  /// mrpack overrides roots.
  bool get includes => this != SideEnv.unsupported;
}

@MappableEnum()
enum Section { mods, resourcePacks, dataPacks, shaders, plugins }

/// Default per-side install state for entries declared in [section].
/// Resource packs default to client-only because servers don't ship
/// resource packs through the `globalpacks` global tree; everything else
/// defaults to installed on both sides.
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

/// Returns [mods] with `server: unsupported` forced on every entry when
/// [pluginLoader] is a non-mod-running platform (paper/folia/bukkit/
/// spigot/spongevanilla). `spongeforge`, `spongeneo`, and the no-plugin
/// case return [mods] unchanged because those platforms run server-side
/// Forge / NeoForge mods alongside plugins. Single source of truth for
/// the docs-spec'd "mods are dead weight on a plugin server" rule;
/// called from the parser and from any future code that materializes
/// the effective entry shape.
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

/// Per-section loader configuration. Asymmetry between yaml and lock
/// is the central invariant of this type:
///
///   * `mods.yaml` carries the *declared* shape: `loader.plugins` is one
///     of `bukkit | folia | paper | spigot | sponge`, and `loader.mods`
///     may be omitted (defaults to [ModLoader.vanilla], "no mod
///     runtime").
///   * `mods.lock` carries the *resolved* shape: `loader.plugins` is one
///     of the seven [PluginLoader] values (the Sponge distribution
///     picked from `loader.mods`), and `loader.mods` is a concrete
///     [ModLoader] plus a resolved version (or [ModLoader.vanilla] with
///     [modsVersion] = null when there is no mod runtime).
///
/// [LoaderConfig] itself stores the resolved values; the declared
/// vocabulary lives in [DeclaredPluginLoader] and never appears here.
@MappableClass()
class LoaderConfig with LoaderConfigMappable {
  final ModLoader mods;

  /// Loader-version tag. In `mods.yaml` this is the user-supplied tag —
  /// `"stable"`, `"latest"`, or a concrete version like `"0.17.3"` (default
  /// `"stable"` when the user omits the `:tag` suffix). In `mods.lock` this
  /// is the resolved concrete version. The resolver compares the two: a
  /// concrete tag in the yaml that already matches the lock skips the
  /// loader-version network call. `null` when [mods] is [ModLoader.vanilla]
  /// — vanilla has no version tag and no resolution step.
  final String? modsVersion;
  final ShaderLoader? shaders;
  final PluginLoader? plugins;

  const LoaderConfig({
    required this.mods,
    this.modsVersion = 'stable',
    this.shaders,
    this.plugins,
  });

  /// True when the pack declares a real mod loader (forge / fabric /
  /// neoforge). False under [ModLoader.vanilla] — no mod runtime, no
  /// Forge/NeoForge installer, no loader-version resolution.
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
