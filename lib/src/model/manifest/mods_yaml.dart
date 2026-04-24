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
  final ShaderLoader? shaders;
  final PluginLoader? plugins;

  const LoaderConfig({required this.mods, this.shaders, this.plugins});
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

  const ModEntry({
    required this.slug,
    this.constraintRaw,
    this.channel,
    this.env = Environment.both,
    this.source = const ModrinthEntrySource(),
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
