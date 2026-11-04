import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'mods_lock.mapper.dart';

/// What kind of [LockedEntry] this is — drives the lock-emit branches
/// and the artifact-fetch loop. `resolved` entries carry zero or more
/// per-platform source blocks ([LockedEntry.modrinth] /
/// [LockedEntry.curseforge]); `url` entries carry [LockedEntry.url] +
/// [LockedEntry.urlFile]; `path` entries carry [LockedEntry.path].
@MappableEnum()
enum LockedEntryKind { resolved, url, path }

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

/// Per-platform Modrinth source block. Present only when Modrinth
/// participated for this entry (eligible per `effectiveSources` and
/// resolved successfully). Omitted entirely otherwise — there is no
/// "marker" state.
@MappableClass()
class LockedModrinthSource with LockedModrinthSourceMappable {
  final String projectId;
  final String versionId;
  final String? versionNumber;

  /// Resolved Modrinth source host. `null` means the global API default,
  /// including its environment override, rather than the pack's host.
  final String? host;
  final bool discoveredViaSearch;

  final LockedFile file;
  final List<String> gameVersions;

  const LockedModrinthSource({
    required this.projectId,
    required this.versionId,
    this.versionNumber,
    this.host,
    this.discoveredViaSearch = false,
    required this.file,
    this.gameVersions = const [],
  });
}

/// Per-platform CurseForge source block. Present only when CurseForge
/// participated for this entry. `file.url` is `null` when
/// [allowModDistribution] is `false` — the user has to download the
/// jar manually from the CurseForge project page.
@MappableClass()
class LockedCurseforgeSource with LockedCurseforgeSourceMappable {
  final int projectId;
  final int fileId;
  final String? slug;
  final LockedFile file;
  final List<String> gameVersions;
  final bool allowModDistribution;
  final bool discoveredViaSearch;

  const LockedCurseforgeSource({
    required this.projectId,
    required this.fileId,
    this.slug,
    required this.file,
    this.gameVersions = const [],
    this.allowModDistribution = true,
    this.discoveredViaSearch = false,
  });
}

@MappableClass()
class LockedEntry with LockedEntryMappable {
  final String slug;
  final LockedEntryKind kind;

  /// Joint label for `kind: resolved` — Modrinth's `versionNumber` when
  /// it participated, else CurseForge's `file.name` or similar. `null`
  /// for `kind: url` and `kind: path`.
  final String? version;

  /// Per-platform source block. Either fully populated (platform
  /// participated and resolved) or null (excluded by `sources:`,
  /// matrix-ineligible, or pack-default-disabled). For `kind: resolved`,
  /// at least one of [modrinth] / [curseforge] must be non-null.
  final LockedModrinthSource? modrinth;
  final LockedCurseforgeSource? curseforge;

  /// `kind: url` payload.
  final String? url;
  final LockedFile? urlFile;

  /// `kind: path` payload.
  final String? path;

  /// Resolved client-side install state.
  final SideEnv client;

  /// Resolved server-side install state.
  final SideEnv server;

  /// Whether this entry is direct or transitive.
  final LockedDependencyKind dependency;

  /// Logical parents requiring this entry, across all resolved platforms.
  @MappableField(key: 'required_by')
  final List<String> requiredBy;

  /// Per-entry `accepts-mc` override from `mods.yaml`.
  final List<String> acceptsMc;

  const LockedEntry({
    required this.slug,
    required this.kind,
    this.version,
    this.modrinth,
    this.curseforge,
    this.url,
    this.urlFile,
    this.path,
    this.client = SideEnv.required,
    this.server = SideEnv.required,
    this.dependency = LockedDependencyKind.direct,
    this.requiredBy = const [],
    this.acceptsMc = const [],
  });

  /// Returns the install state for the requested build env.
  SideEnv sideFor(bool isClient) => isClient ? client : server;

  /// The most-relevant downloadable file for this entry, for callers
  /// that don't care which platform sourced it (build copy loops,
  /// hash-based lookups). For `kind: resolved`, prefers Modrinth's
  /// file when present, otherwise falls back to CurseForge's.
  /// For `kind: url`, returns [urlFile]. For `kind: path`, returns
  /// null — the caller reads [path] directly.
  LockedFile? get primaryFile {
    switch (kind) {
      case LockedEntryKind.resolved:
        return modrinth?.file ?? curseforge?.file;
      case LockedEntryKind.url:
        return urlFile;
      case LockedEntryKind.path:
        return null;
    }
  }
}

/// Locked counterpart of `FileEntry`.
/// Separate from [LockedEntry] because `files:` entries do not use
/// the platform-source-block layout.
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
