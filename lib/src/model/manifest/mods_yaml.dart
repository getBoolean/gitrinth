import 'package:dart_mappable/dart_mappable.dart';

import 'file_entry.dart';

part 'mods_yaml.mapper.dart';

@MappableEnum()
enum Loader { forge, fabric, neoforge }

@MappableEnum()
enum ShaderLoader { iris, optifine, canvas, vanilla }

@MappableEnum()
enum PluginLoader { bukkit, folia, paper, spigot }

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
enum Section { mods, resourcePacks, dataPacks, shaders }

/// Default per-side install state for entries declared in [section].
/// Resource packs default to client-only because servers don't ship
/// resource packs through the `globalpacks` global tree; everything else
/// defaults to installed on both sides.
({SideEnv client, SideEnv server}) defaultSidesFor(Section section) =>
    switch (section) {
      Section.mods => (client: SideEnv.required, server: SideEnv.required),
      Section.shaders => (
        client: SideEnv.required,
        server: SideEnv.unsupported,
      ),
      Section.resourcePacks => (
        client: SideEnv.optional,
        server: SideEnv.unsupported,
      ),
      Section.dataPacks => (client: SideEnv.required, server: SideEnv.required),
    };

@MappableEnum()
enum Channel { release, beta, alpha }

@MappableClass()
class LoaderConfig with LoaderConfigMappable {
  final Loader mods;

  /// Loader-version tag. In `mods.yaml` this is the user-supplied tag —
  /// `"stable"`, `"latest"`, or a concrete version like `"0.17.3"` (default
  /// `"stable"` when the user omits the `:tag` suffix). In `mods.lock` this
  /// is the resolved concrete version. The resolver compares the two: a
  /// concrete tag in the yaml that already matches the lock skips the
  /// loader-version network call.
  final String modsVersion;
  final ShaderLoader? shaders;
  final PluginLoader? plugins;

  const LoaderConfig({
    required this.mods,
    this.modsVersion = 'stable',
    this.shaders,
    this.plugins,
  });
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
    }
  }
}
