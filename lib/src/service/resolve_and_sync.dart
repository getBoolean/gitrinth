library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/emitter.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/overrides_merger.dart';
import '../model/modrinth/project.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../model/resolver/pubgrub.dart';
import '../model/resolver/resolver.dart';
import '../model/resolver/result.dart';
import '../model/resolver/version_selection.dart';
import '../version.dart';
import '../commands/version_picker.dart';
import 'cache.dart';
import 'console.dart';
import 'downloader.dart';
import 'mod_loader_version_resolver.dart';
import 'manifest_io.dart';
import 'modrinth_api.dart';
import 'modrinth_api_factory.dart';
import 'plugin_loader_version_resolver.dart';
import 'section_inference.dart';
import 'solve_report.dart';

part 'lock_builder.dart';

/// Returns true when [v] is admissible under both filters used during
/// resolve: the caller's loader filter (`null` means "any loader is OK"
/// — used for resource_packs / data_packs) and the game-version set.
bool _matchesLoaderAndMc(
  modrinth.Version v,
  List<String>? loaderFilter,
  List<String> gameVersions,
) {
  final loaderOk = loaderFilter == null || v.loaders.any(loaderFilter.contains);
  final mcOk = v.gameVersions.any(gameVersions.contains);
  return loaderOk && mcOk;
}

/// Result of [resolveAndSync]: exit code plus enough detail for the caller
/// to print its own `Got dependencies!` / `Changed N…` summary.
class ResolveSyncResult {
  final ModsLock? newLock;
  final List<LockDiff> diff;
  final int changeCount;
  final int outdated;
  final int exitCode;

  const ResolveSyncResult({
    required this.newLock,
    required this.diff,
    required this.changeCount,
    required this.outdated,
    required this.exitCode,
  });
}

/// Re-resolves `mods.yaml`, writes `mods.lock`, and downloads/verifies every
/// artifact. Shared between `gitrinth get` and `gitrinth add` so both commands
/// produce identical `+ slug version` / `Changed N dependencies!` output.
///
/// When [dryRun] is true, the lockfile and cache are not written; the result
/// carries [exitValidationError] if the lock would have changed, otherwise
/// [exitOk]. When [enforce] is true, any lock change throws a
/// [ValidationError] (same semantics as `gitrinth get --enforce-lockfile`).
///
/// [freshSlugs] holds slugs whose `mods.lock` entries should NOT be passed to
/// the resolver as soft pins, so the resolver picks newest-within-constraint
/// instead of preserving the existing lock. [relaxConstraints] holds slugs
/// whose version constraint should be treated as `any` for resolution. Both
/// power `gitrinth upgrade`; `get` leaves them empty. The diff and the
/// rebuilt lock still come from the *original* manifest and lock, so per-entry
/// metadata (env/optional/channel/etc.) is preserved.
///
/// [manifestOverride] replaces the on-disk `mods.yaml` for resolution.
/// `gitrinth migrate` uses this to resolve against a mutated target without
/// first writing `mods.yaml`.
Future<ResolveSyncResult> resolveAndSync({
  required ManifestIo io,
  required Console console,
  required ModrinthApiFactory apiFactory,
  required GitrinthCache cache,
  required Downloader downloader,
  required ModLoaderVersionResolver modLoaderResolver,
  required PluginLoaderVersionResolver pluginLoaderResolver,
  bool offline = false,
  bool dryRun = false,
  bool enforce = false,
  Set<String> freshSlugs = const {},
  Set<String> relaxConstraints = const {},
  ModsYaml? manifestOverride,
  SolveType solveType = SolveType.get,
}) async {
  final reporter = SolveReporter(console);

  final manifest = manifestOverride ?? io.readModsYaml();
  final defaultBaseUrl = apiFactory.defaultBaseUrl;
  // Effective host for entries that don't override their own. Used for
  // the pack-level slug → projectType lookups (project_overrides
  // section inference) and for the one-shot `mc_version` validation.
  final packHost = manifest.modrinthHost ?? defaultBaseUrl;
  final api = apiFactory.forHost(packHost);
  final projectOverrides = io.readProjectOverrides();
  final slugCache = <String, String?>{};
  // The slug → project_type lookup feeds two things: section
  // inference for purely-transitive overrides (here, in
  // applyOverrides) and reverse lookup of transitive dep project_ids
  // (later, in the Resolver). Cache project lookups so we don't
  // double-fetch the same slug for both purposes when the network
  // is reachable.
  final projectCache = <String, Project>{};
  Future<Project> getProjectCached(String slug) async {
    final cached = projectCache[slug];
    if (cached != null) return cached;
    final p = await api.getProject(slug);
    projectCache[slug] = p;
    return p;
  }

  final mergedResult = await applyOverrides(
    manifest,
    projectOverrides,
    inferSectionForTransitive: (slug) async {
      if (offline) {
        // Without network, we can't infer the project type. Fall back
        // to mods — the override author can write a `type:` hint or
        // declare the slug under the right section explicitly to
        // avoid this fallback.
        return Section.mods;
      }
      try {
        final proj = await getProjectCached(slug);
        return inferSectionFromProject(
          projectType: proj.projectType,
          loaders: proj.loaders,
        );
      } on DioException catch (e) {
        final err = e.error;
        if (err is GitrinthException) throw err;
        throw UserError(
          'project_overrides: failed to look up Modrinth project '
          '"$slug" to infer its section: ${e.message}',
        );
      }
    },
  );
  final merged = mergedResult.manifest;
  final overriddenSlugs = mergedResult.overriddenSlugs;
  final existingLock = io.readModsLock();

  if (enforce) {
    _checkUserEntriesPresentInLock(merged, existingLock);
  }

  final lockForResolution = _stripLockPins(existingLock, freshSlugs);
  final manifestForResolution = _relaxManifestConstraints(
    merged,
    relaxConstraints,
  );

  final loaderConfig = merged.loader;
  final mc = merged.mcVersion;

  // One-shot mc-version validation: only call /tag/game_version when the
  // mc-version differs from what mods.lock already records. The pairing
  // was already validated when it was first locked, so a stable lock is
  // proof enough. Skipped under --offline since we can't reach the tag
  // endpoint; trust mods.yaml.
  if (existingLock?.mcVersion != mc && !offline) {
    await _validateGameVersion(api: api, mcVersion: mc);
  }

  // Loader-tag resolution. Concrete tags pass through unchanged with no
  // network call; `stable` / `latest` always re-resolve (those tags exist
  // precisely to drift). For concrete tags that already match the lock,
  // skip even the passthrough — the lock is the cache. Under --offline,
  // `stable`/`latest` falls back to the lock's concrete version.
  final String? resolvedModLoaderVersion;
  final modLoaderVersion = loaderConfig.modLoaderVersion;
  if (loaderConfig.hasModRuntime && modLoaderVersion != null) {
    resolvedModLoaderVersion = await _resolveModLoaderVersion(
      modLoaderResolver: modLoaderResolver,
      modLoader: loaderConfig.mods,
      tag: modLoaderVersion,
      mcVersion: mc,
      existingLock: existingLock,
      offline: offline,
      console: console,
    );
  } else {
    resolvedModLoaderVersion = null;
  }

  final String? resolvedPluginLoaderVersion;
  final pluginLoader = loaderConfig.plugins;
  final pluginLoaderVersion = loaderConfig.pluginLoaderVersion;
  if (pluginLoader != null && pluginLoaderVersion != null) {
    resolvedPluginLoaderVersion = await _resolvePluginLoaderVersion(
      pluginLoaderResolver: pluginLoaderResolver,
      pluginLoader: pluginLoader,
      tag: pluginLoaderVersion,
      mcVersion: mc,
      existingLock: existingLock,
      offline: offline,
      console: console,
    );
  } else {
    resolvedPluginLoaderVersion = null;
  }

  final slugToSection = <String, Section>{};
  for (final section in Section.values) {
    for (final slug in merged.sectionEntries(section).keys) {
      slugToSection[slug] = section;
    }
  }

  final versionsPerSlug = <String, List<modrinth.Version>>{};

  // Per-entry effective host for the Modrinth source. Walks
  // `entry.source.host → manifest.modrinthHost → defaultBaseUrl` via
  // [ModsYaml.effectiveModrinthHost] so the chain lives in one place.
  String entryHost(Section section, String slug, ModEntry? declaredEntry) {
    final entry = declaredEntry ?? merged.sectionEntries(section)[slug];
    if (entry == null) return packHost;
    return manifest.effectiveModrinthHost(entry, defaultBaseUrl);
  }

  final resolver = Resolver(
    listVersions: (slug) async {
      final section = slugToSection[slug] ?? Section.mods;
      final loaderFilter = filterLoadersForSection(loaderConfig, section);
      final entry = merged.sectionEntries(section)[slug];
      final gameVersions = <String>{mc, ...?entry?.acceptsMc}.toList();
      final host = entryHost(section, slug, entry);

      if (offline) {
        final lockedProjectId = existingLock
            ?.sectionFor(section)[slug]
            ?.projectId;
        if (lockedProjectId == null) {
          throw UserError(
            'cannot resolve "$slug" while offline: not present in mods.lock '
            'and never cached. Try again without --offline, or run '
            '`gitrinth get` once with the network available.',
          );
        }
        final cached = cache
            .listCachedVersions(host, lockedProjectId)
            .where((v) => _matchesLoaderAndMc(v, loaderFilter, gameVersions))
            .toList();
        versionsPerSlug[slug] = cached;
        return cached;
      }

      try {
        final list = await apiFactory
            .forHost(host)
            .listVersions(
              slug,
              loadersJson: loaderFilter == null
                  ? null
                  : encodeFilterArray(loaderFilter),
              gameVersionsJson: encodeFilterArray(gameVersions),
            );
        versionsPerSlug[slug] = list;
        return list;
      } on Object catch (e) {
        final err = (e is DioException) ? e.error : e;
        if (err is GitrinthException) throw err;
        throw UserError('failed to list versions for $slug: $e');
      }
    },
    resolveSlugForProjectId: (projectId) async {
      if (slugCache.containsKey(projectId)) return slugCache[projectId];
      try {
        // Reverse-lookup project IDs against the pack default host —
        // transitive deps don't carry their own per-entry host yet.
        final Project proj = await apiFactory
            .forHost(packHost)
            .getProject(projectId);
        slugCache[projectId] = proj.slug;
        return proj.slug;
      } on Object {
        slugCache[projectId] = null;
        return null;
      }
    },
    solveType: solveType,
  );

  // Promote each Modrinth-source override entry to a concrete
  // Modrinth Version. This is the sticky pre-decision the resolver
  // honors: the slug never enters the candidate-search loop. URL/path
  // overrides take the lock builder's url/path branches and bypass
  // the resolver entirely.
  final overridePins = <String, OverridePin>{};
  for (final e in mergedResult.overrideEntries.entries) {
    final slug = e.key;
    final entry = e.value;
    if (entry.source is! ModrinthEntrySource) continue;
    final section = slugToSection[slug] ?? Section.mods;
    final loaderFilter = filterLoadersForSection(loaderConfig, section);
    final gameVersions = <String>{mc, ...entry.acceptsMc}.toList();
    final overrideHost = entryHost(section, slug, entry);
    final List<modrinth.Version> candidates;
    if (offline) {
      final lockedProjectId = existingLock
          ?.sectionFor(section)[slug]
          ?.projectId;
      if (lockedProjectId == null) {
        throw UserError(
          'cannot apply project_overrides for "$slug" while offline: '
          'not present in mods.lock and never cached.',
        );
      }
      candidates = cache
          .listCachedVersions(overrideHost, lockedProjectId)
          .where((v) => _matchesLoaderAndMc(v, loaderFilter, gameVersions))
          .toList();
    } else {
      try {
        candidates = await apiFactory
            .forHost(overrideHost)
            .listVersions(
              slug,
              loadersJson: loaderFilter == null
                  ? null
                  : encodeFilterArray(loaderFilter),
              gameVersionsJson: encodeFilterArray(gameVersions),
            );
      } on Object catch (err) {
        final e = (err is DioException) ? err.error : err;
        if (e is GitrinthException) throw e;
        throw UserError(
          'project_overrides: failed to list versions for "$slug": $err',
        );
      }
    }
    final picked = pickHighestMatching(
      candidates,
      parseConstraint(entry.constraintRaw),
      entry.channel ?? Channel.alpha,
      solveType: solveType,
    );
    if (picked == null) {
      throw ValidationError(
        "project_overrides: '$slug' has no published version matching "
        "${entry.constraintRaw ?? 'any'} on ${manifest.loader.mods.name} "
        "$mc",
      );
    }
    overridePins[slug] = OverridePin(slug, picked);
    versionsPerSlug[slug] = candidates;
  }

  console.message('Resolving dependencies...');
  console.solver(
    'Resolving with loader.mods=${loaderConfig.mods.name} mc=$mc...',
  );
  final resolution = await resolver.resolve(
    manifestForResolution,
    existingLock: lockForResolution,
    overridePins: overridePins,
  );

  final newLock = _buildLock(
    merged,
    resolution,
    resolvedModLoaderVersion,
    resolvedPluginLoaderVersion,
  );
  final diff = diffLocks(existingLock, newLock);

  reporter.printSimpleDiff(diff);

  if (enforce && diff.isNotEmpty) {
    throw ValidationError(
      'mods.lock is out of date (--enforce-lockfile). '
      '${diff.length} change(s) would be applied.',
    );
  }

  if (dryRun) {
    reporter.printSimpleDiff(diff, force: true);
    return ResolveSyncResult(
      newLock: newLock,
      diff: diff,
      changeCount: diff.where((d) => d.kind != DiffKind.unchanged).length,
      outdated: countOutdated(newLock, versionsPerSlug),
      exitCode: diff.isNotEmpty ? exitValidationError : exitOk,
    );
  }

  final newLockText = emitModsLock(newLock);
  io.writeModsLock(newLockText);

  reporter.printReport(
    newLock: newLock,
    diff: diff,
    versionsPerSlug: versionsPerSlug,
    overriddenSlugs: overriddenSlugs,
  );

  // Persist each resolved Modrinth version's dependency list to the
  // artifact cache, sibling to the .jar. Mirrors dart pub's
  // "graph-in-cache" architecture: `mods.lock` no longer carries
  // forward edges; future `gitrinth upgrade --unlock-transitive`
  // recomputes the closure from these JSON files. Failure here warns
  // but doesn't abort — the artifact download is the contract.
  _persistVersionMetadata(
    resolution,
    cache,
    console,
    (r) => entryHost(r.section, r.slug, null),
  );

  int downloaded = 0;
  int hits = 0;
  final fetchErrors = <String>[];
  for (final section in Section.values) {
    final sectionMap = newLock.sectionFor(section);
    for (final entry in sectionMap.entries) {
      final locked = entry.value;
      try {
        switch (locked.sourceKind) {
          case LockedSourceKind.modrinth:
            final file = locked.file;
            final projectId = locked.projectId;
            final versionId = locked.versionId;
            if (file == null || projectId == null || versionId == null) {
              throw FormatException(
                'lock entry "${locked.slug}" with kind=modrinth is missing '
                'required fields — mods.lock is malformed.',
              );
            }
            final url = file.url;
            if (url == null) continue;
            final dest = cache.modrinthPath(
              host: entryHost(section, locked.slug, null),
              projectId: projectId,
              versionId: versionId,
              filename: file.name,
            );
            final existed = File(dest).existsSync();
            await downloader.downloadTo(
              url: url,
              destinationPath: dest,
              expectedSha512: file.sha512,
            );
            if (existed) {
              hits++;
              console.io('cache hit:  ${locked.slug} -> $dest');
            } else {
              downloaded++;
              console.io('downloaded: ${locked.slug} -> $dest');
            }
            break;
          case LockedSourceKind.url:
            final file = locked.file;
            if (file == null) continue;
            final url = file.url;
            if (url == null) continue;
            final sha512 = file.sha512;
            final dest = sha512 != null
                ? cache.urlPath(sha512: sha512, filename: file.name)
                : cache.unverifiedUrlPath(locked.slug, file.name);
            final existed = File(dest).existsSync();
            await downloader.downloadTo(
              url: url,
              destinationPath: dest,
              expectedSha512: sha512,
            );
            if (existed) {
              hits++;
            } else {
              downloaded++;
            }
            break;
          case LockedSourceKind.path:
            final rawPath = locked.path;
            if (rawPath == null) {
              throw FormatException(
                'lock entry "${locked.slug}" with kind=path has no path '
                '— mods.lock is malformed.',
              );
            }
            final resolved = p.isAbsolute(rawPath)
                ? rawPath
                : p.normalize(p.join(io.directory.path, rawPath));
            if (FileSystemEntity.typeSync(resolved) ==
                FileSystemEntityType.notFound) {
              throw ValidationError(
                'path source for "${locked.slug}" points to a missing file: '
                '$rawPath (looked in $resolved)',
              );
            }
            break;
        }
      } on GitrinthException catch (e) {
        fetchErrors.add(e.message);
      }
    }
  }
  // Verify `files:` source paths exist; mirrors the `path:` mod-entry
  // existence check above. Build-time resolution would also catch
  // this, but failing fast at `get` time matches user expectations.
  for (final entry in newLock.files.values) {
    final resolved = p.isAbsolute(entry.sourcePath)
        ? entry.sourcePath
        : p.normalize(p.join(io.directory.path, entry.sourcePath));
    if (FileSystemEntity.typeSync(resolved) == FileSystemEntityType.notFound) {
      fetchErrors.add(
        'files: entry "${entry.destination}" points to a missing source: '
        '${entry.sourcePath} (looked in $resolved)',
      );
    }
  }
  if (fetchErrors.isNotEmpty) {
    throw ValidationError(
      fetchErrors.length == 1
          ? fetchErrors.first
          : 'failed to fetch ${fetchErrors.length} dependencies:\n'
                '${fetchErrors.map((e) => '  - $e').join('\n')}',
    );
  }

  final changeCount = diff.where((d) => d.kind != DiffKind.unchanged).length;
  final outdated = countOutdated(newLock, versionsPerSlug);
  console.io(
    'Locked $changeCount change(s); $downloaded downloaded, $hits cache hit(s).',
  );

  final markerCount = _countNotFoundMarkers(merged);
  if (markerCount > 0) {
    console.message(
      '$markerCount ${markerCount == 1 ? 'entry' : 'entries'} marked '
      '$notFoundMarker — run `gitrinth migrate <target>` to retry.',
    );
  }
  final disabledCount = _countDisabledByConflictMarkers(merged);
  if (disabledCount > 0) {
    console.message(
      '$disabledCount ${disabledCount == 1 ? 'entry' : 'entries'} marked '
      '$disabledByConflictMarker — run `gitrinth migrate <target>` or '
      '`gitrinth upgrade --major-versions` to retry.',
    );
  }

  return ResolveSyncResult(
    newLock: newLock,
    diff: diff,
    changeCount: changeCount,
    outdated: outdated,
    exitCode: exitOk,
  );
}

int _countNotFoundMarkers(ModsYaml manifest) {
  var count = 0;
  for (final section in Section.values) {
    for (final entry in manifest.sectionEntries(section).values) {
      if (isNotFoundMarker(entry.constraintRaw)) count++;
    }
  }
  return count;
}

int _countDisabledByConflictMarkers(ModsYaml manifest) {
  var count = 0;
  for (final section in Section.values) {
    for (final entry in manifest.sectionEntries(section).values) {
      if (isDisabledByConflictMarker(entry.constraintRaw)) count++;
    }
  }
  return count;
}

void _checkUserEntriesPresentInLock(ModsYaml manifest, ModsLock? lock) {
  if (lock == null) {
    throw const ValidationError('mods.lock is missing (--enforce-lockfile).');
  }
  final missing = <String>[];
  for (final section in Section.values) {
    final entries = manifest.sectionEntries(section);
    final lockSection = lock.sectionFor(section);
    for (final entry in entries.entries) {
      // Marker entries are absent from the lock by design.
      if (isAnyGitrinthMarker(entry.value.constraintRaw)) continue;
      if (!lockSection.containsKey(entry.key)) missing.add(entry.key);
    }
  }
  if (missing.isNotEmpty) {
    throw ValidationError(
      'mods.lock is missing user-declared entries (--enforce-lockfile): '
      '${missing.join(', ')}',
    );
  }
}

/// Hits `/v2/tag/game_version` and throws [ValidationError] if [mcVersion]
/// is not in the list. Called only on first lock or when the user changed
/// `mc-version` in `mods.yaml`.
Future<void> _validateGameVersion({
  required ModrinthApi api,
  required String mcVersion,
}) async {
  final List<String> known;
  try {
    final list = await api.getGameVersions();
    known = list.map((v) => v.version).toList();
  } on Object catch (e) {
    final err = (e is DioException) ? e.error : e;
    if (err is GitrinthException) throw err;
    throw UserError(
      'failed to fetch Minecraft game versions from Modrinth: $e',
    );
  }
  if (!known.contains(mcVersion)) {
    throw ValidationError(
      'mc-version "$mcVersion" is not a known Minecraft release on '
      'Modrinth. Pick one from '
      'https://api.modrinth.com/v2/tag/game_version (e.g. '
      '${known.take(3).join(", ")}).',
    );
  }
}

/// Returns the concrete loader version to bake into the lock.
///
/// Skips re-resolution when the user typed a concrete tag (anything other
/// than `stable`/`latest`) and the existing lock already records that
/// same loader+version pair. `stable`/`latest` always re-resolve.
///
/// Concrete tags hit the network for upstream validation on first use;
/// under `--offline` the validation is skipped (we trust the user's pin).
///
/// Caller is expected to gate on [LoaderConfig.hasModRuntime] and pass
/// the populated [tag]; vanilla packs skip this resolution entirely.
Future<String> _resolveModLoaderVersion({
  required ModLoaderVersionResolver modLoaderResolver,
  required ModLoader modLoader,
  required String tag,
  required String mcVersion,
  required ModsLock? existingLock,
  required bool offline,
  required Console console,
}) async {
  final lockedSameLoader = existingLock?.loader.mods == modLoader;
  final lockedVersion = existingLock?.loader.modLoaderVersion;
  final tagIsConcrete = tag != 'stable' && tag != 'latest';
  if (tagIsConcrete && lockedSameLoader && lockedVersion == tag) {
    return tag;
  }
  if (tagIsConcrete && offline) {
    if (lockedSameLoader && lockedVersion != null && lockedVersion != tag) {
      console.warn(
        'using unvalidated loader pin `${modLoader.name}:'
        '$tag` while offline (mods.lock had `$lockedVersion`).',
      );
    }
    return tag;
  }
  if (!tagIsConcrete && offline) {
    if (lockedSameLoader && lockedVersion != null) {
      return lockedVersion;
    }
    throw UserError(
      'cannot resolve loader tag "$tag" while offline: no concrete '
      'version recorded in mods.lock. Try again without --offline, or '
      'pin a concrete tag like `${modLoader.name}:<version>` in '
      'mods.yaml.',
    );
  }
  return modLoaderResolver.resolve(
    loader: modLoader,
    tag: tag,
    mcVersion: mcVersion,
  );
}

Future<String> _resolvePluginLoaderVersion({
  required PluginLoaderVersionResolver pluginLoaderResolver,
  required PluginLoader pluginLoader,
  required String tag,
  required String mcVersion,
  required ModsLock? existingLock,
  required bool offline,
  required Console console,
}) async {
  final lockedSameLoader = existingLock?.loader.plugins == pluginLoader;
  final lockedVersion = existingLock?.loader.pluginLoaderVersion;
  final tagIsConcrete = tag != 'stable' && tag != 'latest';
  if (tagIsConcrete && lockedSameLoader && lockedVersion == tag) {
    return tag;
  }
  if (tagIsConcrete && offline) {
    if (lockedSameLoader && lockedVersion != null && lockedVersion != tag) {
      console.warn(
        'using unvalidated plugin loader pin `${pluginLoader.name}:'
        '$tag` while offline (mods.lock had `$lockedVersion`).',
      );
    }
    return tag;
  }
  if (!tagIsConcrete && offline) {
    if (lockedSameLoader && lockedVersion != null) {
      return lockedVersion;
    }
    throw UserError(
      'cannot resolve plugin loader tag "$tag" while offline: no concrete '
      'version recorded in mods.lock. Try again without --offline, or pin '
      'a concrete tag like `${pluginLoader.name}:<version>` in mods.yaml.',
    );
  }
  return pluginLoaderResolver.resolve(
    loader: pluginLoader,
    tag: tag,
    mcVersion: mcVersion,
  );
}

/// Returns [existingLock] with each section's map filtered to drop any slug
/// in [freshSlugs]. Used by `gitrinth upgrade` to force the resolver to pick
/// a new version for the named entries instead of preserving the soft pin.
/// When [freshSlugs] is empty (the `get` path), returns [existingLock]
/// unchanged.
ModsLock? _stripLockPins(ModsLock? existingLock, Set<String> freshSlugs) {
  if (existingLock == null || freshSlugs.isEmpty) return existingLock;
  Map<String, LockedEntry> strip(Map<String, LockedEntry> m) => {
    for (final e in m.entries)
      if (!freshSlugs.contains(e.key)) e.key: e.value,
  };
  return existingLock.copyWith(
    mods: strip(existingLock.mods),
    resourcePacks: strip(existingLock.resourcePacks),
    dataPacks: strip(existingLock.dataPacks),
    shaders: strip(existingLock.shaders),
    plugins: strip(existingLock.plugins),
  );
}

/// Returns [merged] with each section entry whose slug is in [relaxConstraints]
/// rewritten to have `constraintRaw: null` (parsed as `VersionConstraint.any`).
/// Channel/env/optional/source are preserved. Used by
/// `gitrinth upgrade --major-versions` to bypass caret ceilings.
ModsYaml _relaxManifestConstraints(ModsYaml merged, Set<String> relax) {
  if (relax.isEmpty) return merged;
  Map<String, ModEntry> relaxSection(Map<String, ModEntry> m) => {
    for (final e in m.entries)
      e.key: relax.contains(e.key)
          ? e.value.copyWith(constraintRaw: null)
          : e.value,
  };
  return merged.copyWith(
    mods: relaxSection(merged.mods),
    resourcePacks: relaxSection(merged.resourcePacks),
    dataPacks: relaxSection(merged.dataPacks),
    shaders: relaxSection(merged.shaders),
    plugins: relaxSection(merged.plugins),
  );
}
