import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'mods_lock.mapper.dart';

@MappableEnum()
enum LockedSourceKind { modrinth, url, path }

/// Mirrors dart pub's lockfile `dependency` classification. `direct`
/// is an entry the user declared in `mods.yaml`; `transitive` was
/// pulled in by another mod's required deps. The dep-graph edges that
/// connect them live in the artifact cache (the `version.json` sibling
/// to each cached jar), not in `mods.lock`, matching pub's "graph in
/// cache, not lock" architecture.
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

  /// Mirror of [ModEntry.client] — the resolved client-side install state.
  final SideEnv client;

  /// Mirror of [ModEntry.server] — the resolved server-side install state.
  final SideEnv server;

  /// Whether this entry was declared by the user (`direct`) or pulled
  /// in transitively (`transitive`). Mirrors dart pub's lockfile
  /// classification. Replaces the older `auto: true/false` flag.
  final LockedDependencyKind dependency;

  /// Minecraft versions the resolved Modrinth version was tagged for.
  /// Empty for non-Modrinth sources. Enables later detection of entries
  /// that became under-tagged after a pack `mc-version` bump.
  final List<String> gameVersions;

  /// Mirror of `ModEntry.acceptsMc`; the user's per-entry override
  /// declaring additional `mc-version`s this entry should be considered
  /// compatible with even when Modrinth's tagging disagrees. Empty when
  /// the user did not set `accepts-mc` in `mods.yaml`.
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

/// Locked counterpart of `FileEntry`. Manifest-only loose copy with a
/// `preserve` bit; intentionally a separate class from [LockedEntry]
/// because `LockedEntry.sourceKind` is closed over dep-graph semantics
/// (`modrinth | url | path`), and `files:` entries do not flow through
/// pubgrub.
@MappableClass()
class LockedFileEntry with LockedFileEntryMappable {
  /// Destination path relative to the build env root.
  final String destination;

  /// Source path relative to the `mods.yaml` directory.
  final String sourcePath;

  final SideEnv client;
  final SideEnv server;
  final bool preserve;

  /// Optional sha512 of the source bytes, recorded at copy time.
  /// Reserved for future "did source change?" optimizations; not
  /// currently consulted by build or pack.
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

  /// Loose-file entries forwarded from `mods.yaml`'s `files:` section.
  /// Keyed by destination path. Outside the [Section] taxonomy.
  final Map<String, LockedFileEntry> files;

  const ModsLock({
    required this.gitrinthVersion,
    required this.loader,
    required this.mcVersion,
    this.mods = const {},
    this.resourcePacks = const {},
    this.dataPacks = const {},
    this.shaders = const {},
    this.files = const {},
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
