import 'package:dart_mappable/dart_mappable.dart';

part 'mods_yaml.mapper.dart';

@MappableEnum()
enum Loader { forge, fabric, neoforge }

@MappableEnum()
enum ShaderLoader { iris, optifine, canvas, vanilla }

@MappableEnum()
enum PluginLoader { bukkit, folia, paper, spigot }

@MappableEnum()
enum Environment { client, server, both }

@MappableEnum()
enum Section { mods, resourcePacks, dataPacks, shaders }

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
  final Environment env;
  final EntrySource source;

  /// Additional Minecraft versions to union with the pack's `mc-version`
  /// when querying Modrinth for this entry. Query-time only; does not
  /// influence pack-level decisions.
  final List<String> acceptsMc;

  /// When true, the entry ships in the .mrpack as `env: optional` on
  /// every side it's installed on, so launchers offer a toggle.
  final bool optional;

  const ModEntry({
    required this.slug,
    this.constraintRaw,
    this.channel,
    this.env = Environment.both,
    this.source = const ModrinthEntrySource(),
    this.acceptsMc = const [],
    this.optional = false,
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
  final Map<String, ModEntry> overrides;

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
    this.overrides = const {},
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
