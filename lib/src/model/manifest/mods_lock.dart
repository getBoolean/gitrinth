import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'mods_lock.mapper.dart';

@MappableEnum()
enum LockedSourceKind { modrinth, url, path }

/// Mirrors dart pub's lockfile dependency classification.
@MappableEnum()
enum LockedDependencyKind { direct, transitive }

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

  /// Resolved client-side install state.
  final SideEnv client;

  /// Resolved server-side install state.
  final SideEnv server;

  /// Whether this entry is direct or transitive.
  final LockedDependencyKind dependency;

  /// Minecraft versions tagged on the resolved Modrinth version.
  final List<String> gameVersions;

  /// Per-entry `accepts-mc` override from `mods.yaml`.
  final List<String> acceptsMc;

  const LockedEntry({
    required this.slug,
    required this.sourceKind,
    this.version,
    this.projectId,
    this.versionId,
    this.file,
    this.path,
    this.client = SideEnv.required,
    this.server = SideEnv.required,
    this.dependency = LockedDependencyKind.direct,
    this.gameVersions = const [],
    this.acceptsMc = const [],
  });

  /// Returns the install state for the requested build env.
  SideEnv sideFor(bool isClient) => isClient ? client : server;
}

/// Locked counterpart of `FileEntry`.
/// Separate from [LockedEntry] because `files:` entries do not use
/// `LockedEntry.sourceKind`.
@MappableClass()
class LockedFileEntry with LockedFileEntryMappable {
  /// Destination path relative to the build env root.
  final String destination;

  /// Source path relative to the `mods.yaml` directory.
  final String sourcePath;

  final SideEnv client;
  final SideEnv server;
  final bool preserve;

  /// Optional sha512 recorded at copy time.
  final String? sha512;

  const LockedFileEntry({
    required this.destination,
    required this.sourcePath,
    this.client = SideEnv.required,
    this.server = SideEnv.required,
    this.preserve = false,
    this.sha512,
  });

  /// Returns the install state for the requested build env.
  SideEnv sideFor(bool isClient) => isClient ? client : server;
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
  final Map<String, LockedEntry> plugins;

  /// `files:` entries keyed by destination path.
  final Map<String, LockedFileEntry> files;

  const ModsLock({
    required this.gitrinthVersion,
    required this.loader,
    required this.mcVersion,
    this.mods = const {},
    this.resourcePacks = const {},
    this.dataPacks = const {},
    this.shaders = const {},
    this.plugins = const {},
    this.files = const {},
  });

  Iterable<MapEntry<String, LockedEntry>> get allEntries sync* {
    yield* mods.entries;
    yield* resourcePacks.entries;
    yield* dataPacks.entries;
    yield* shaders.entries;
    yield* plugins.entries;
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
      case Section.plugins:
        return plugins;
    }
  }
}
