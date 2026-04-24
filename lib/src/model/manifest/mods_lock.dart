import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'mods_lock.mapper.dart';

@MappableEnum()
enum LockedSourceKind { modrinth, url, path }

@MappableClass()
class LockedFile with LockedFileMappable {
  final String name;
  final String? url;
  final String? sha1;
  final String? sha512;
  final int? size;

  const LockedFile({
    required this.name,
    this.url,
    this.sha1,
    this.sha512,
    this.size,
  });
}

@MappableClass()
class LockedEntry with LockedEntryMappable {
  final String slug;
  final LockedSourceKind sourceKind;
  final String? version;
  final String? projectId;
  final String? versionId;
  final LockedFile? file;
  final String? path;
  final Environment env;
  final bool auto;

  /// Minecraft versions the resolved Modrinth version was tagged for.
  /// Empty for non-Modrinth sources. Enables later detection of entries
  /// that became under-tagged after a pack `mc-version` bump.
  final List<String> gameVersions;

  /// Mirror of `ModEntry.optional`; preserved through `gitrinth get` so
  /// `pack` can emit `env: "optional"` in `modrinth.index.json`.
  final bool optional;

  const LockedEntry({
    required this.slug,
    required this.sourceKind,
    this.version,
    this.projectId,
    this.versionId,
    this.file,
    this.path,
    this.env = Environment.both,
    this.auto = false,
    this.gameVersions = const [],
    this.optional = false,
  });
}

@MappableClass()
class ModsLock with ModsLockMappable {
  final String gitrinthVersion;
  final LoaderConfig loader;
  final String mcVersion;
  final Map<String, LockedEntry> mods;
  final Map<String, LockedEntry> resourcePacks;
  final Map<String, LockedEntry> dataPacks;
  final Map<String, LockedEntry> shaders;

  const ModsLock({
    required this.gitrinthVersion,
    required this.loader,
    required this.mcVersion,
    this.mods = const {},
    this.resourcePacks = const {},
    this.dataPacks = const {},
    this.shaders = const {},
  });

  Iterable<MapEntry<String, LockedEntry>> get allEntries sync* {
    yield* mods.entries;
    yield* resourcePacks.entries;
    yield* dataPacks.entries;
    yield* shaders.entries;
  }

  Map<String, LockedEntry> sectionFor(Section section) {
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
