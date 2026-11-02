import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../cli/exceptions.dart';
import '../../cli/exit_codes.dart';
import '../../commands/version_picker.dart';
import '../../model/curseforge/cf_constants.dart';
import '../../model/curseforge/cf_file_hash.dart';
import '../../model/curseforge/cf_mod.dart';
import '../../model/curseforge/cf_mod_file.dart';
import '../../model/manifest/emitter.dart';
import '../../model/manifest/mods_lock.dart';
import '../../model/manifest/mods_yaml.dart';
import '../../model/manifest/overrides_merger.dart';
import '../../model/modrinth/project.dart';
import '../../model/modrinth/version.dart' as modrinth;
import '../../model/resolver/constraint.dart';
import '../../model/resolver/modrinth_solver_adapter.dart';
import '../../model/resolver/pubgrub.dart';
import '../../model/resolver/resolver.dart';
import '../../model/resolver/version_selection.dart';
import '../../model/manifest/source_eligibility.dart';
import '../cache.dart';
import '../console.dart';
import '../curseforge/curseforge_api_factory.dart';
import '../curseforge/curseforge_version.dart';
import '../downloader.dart';
import '../manifest_io.dart';
import '../modrinth/modrinth_api.dart';
import '../modrinth/modrinth_api_factory.dart';
import 'curseforge_resolver.dart';
import 'curseforge_resolution_api.dart';
import 'cross_platform_search.dart';
import 'download_artifacts.dart';
import 'hash_scan.dart';
import 'lock_builder.dart';
import 'mod_loader_version_resolver.dart';
import 'plugin_loader_version_resolver.dart';
import 'section_inference.dart';
import 'solve_report.dart';

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
  required CurseForgeApiFactory cfFactory,
  required GitrinthCache cache,
  required Downloader downloader,
  required ModLoaderVersionResolver modLoaderResolver,
  required PluginLoaderVersionResolver pluginLoaderResolver,
  bool offline = false,
  bool dryRun = false,
  bool enforce = false,
  bool noSearch = false,
  Set<String> allowMissingSourcesForSlugs = const {},
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
  var manifestForResolution = _relaxManifestConstraints(
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
  final transitiveHosts = <String, String>{};
  final transitiveProjectSlugs = <String, String>{};

  // Per-entry effective host for the Modrinth source. Walks
  // `entry.source.host → manifest.modrinthHost → defaultBaseUrl` via
  // [ModsYaml.effectiveModrinthHost] so the chain lives in one place.
  String entryHost(Section section, String slug, ModEntry? declaredEntry) {
    final entry = declaredEntry ?? merged.sectionEntries(section)[slug];
    if (entry == null) return transitiveHosts[slug] ?? packHost;
    return manifest.effectiveModrinthHost(entry, defaultBaseUrl);
  }

  // CurseForge resolution pass. Under --offline we skip the network
  // walk and synthesize a CfResolution from the existing lock so the
  // builder re-emits every prior CF source block byte-for-byte. The
  // cache supplies the actual artifacts.
  final cfApi = CurseForgeResolutionApi(cfFactory.api);
  CfResolution cfResolution;
  if (offline) {
    console.warn(
      'Offline: CurseForge resolution skipped; preserving CF source '
      'blocks from the existing lock.',
    );
    cfResolution = existingLock == null
        ? CfResolution.empty
        : synthesizeCfResolutionFromLock(existingLock, manifest: merged);
    final missingCf = <String>[];
    for (final section in Section.values) {
      for (final entry in merged.sectionEntries(section).values) {
        if (entry.source is! ModrinthEntrySource ||
            isAnyGitrinthMarker(entry.constraintRaw)) {
          continue;
        }
        if (!effectiveSources(
          merged,
          entry,
          section,
        ).contains(SourceKind.curseforge)) {
          continue;
        }
        final prior = cfResolution.resolved[entry.slug];
        if (prior == null ||
            prior.project.id <= 0 ||
            prior.file.id <= 0 ||
            prior.file.fileName.isEmpty) {
          missingCf.add('${section.name}/${entry.slug}');
          continue;
        }
        final wantedMc = {mc, ...entry.acceptsMc};
        final matchesMc = prior.file.gameVersions.isEmpty
            ? wantedMc.contains(existingLock?.mcVersion)
            : prior.file.gameVersions.any(wantedMc.contains);
        final peer = entry.curseforgeSlug;
        final matchesPeer =
            peer == null ||
            peer == prior.project.slug ||
            int.tryParse(peer) == prior.project.id;
        final matchesLoader = switch (section) {
          Section.mods => existingLock?.loader.mods == loaderConfig.mods,
          Section.plugins =>
            existingLock?.loader.plugins == loaderConfig.plugins,
          _ => true,
        };
        final cfOnly = !effectiveSources(
          merged,
          entry,
          section,
        ).contains(SourceKind.modrinth);
        if (!matchesMc ||
            !matchesPeer ||
            !matchesLoader ||
            (cfOnly &&
                !curseForgeFileSatisfies(prior.file, entry.constraintRaw))) {
          throw ValidationError(
            'Cannot resolve ${entry.slug} while offline: its locked CurseForge file '
            'does not satisfy the current version, Minecraft version, loader, or peer. '
            'Run `gitrinth get` online first.',
          );
        }
      }
    }
    if (missingCf.isNotEmpty) {
      throw ValidationError(
        'Cannot resolve CurseForge entries while offline: ${missingCf.join(', ')} '
        'have no usable CurseForge block in mods.lock. Run `gitrinth get` online first.',
      );
    }
  } else {
    cfResolution = await resolveCurseforgeEntries(
      manifest: merged,
      api: cfApi,
      console: console,
    );
  }

  final search = CrossPlatformSearch(
    manifest: manifestForResolution,
    mrFactory: apiFactory,
    cfApi: cfApi,
    console: console,
    disabled: offline || noSearch,
  );
  final searchedMrVersions = <String, List<modrinth.Version>>{};
  final hashVersionIds = <String, String>{};

  final resolver = Resolver(
    sectionForSlug: (slug) => slugToSection[slug] ?? Section.mods,
    resolveDependencySlug: (projectId, parentSlug) async {
      final parentSection = slugToSection[parentSlug] ?? Section.mods;
      final host = entryHost(parentSection, parentSlug, null);
      final cacheKey = '$host/$projectId';
      if (slugCache.containsKey(cacheKey)) return slugCache[cacheKey];
      if (offline) {
        for (final section in Section.values) {
          for (final e
              in existingLock?.sectionFor(section).entries ??
                  <MapEntry<String, LockedEntry>>[]) {
            if (e.value.modrinth?.projectId != projectId) continue;
            if ((e.value.modrinth?.host ?? defaultBaseUrl) != host) continue;
            slugToSection[e.key] = section;
            transitiveHosts[e.key] = host;
            return slugCache[cacheKey] = e.key;
          }
        }
        throw ValidationError(
          'Cannot resolve dependency $projectId required by $parentSlug while offline: missing from mods.lock.',
        );
      }
      final project = await apiFactory.forHost(host).getProject(projectId);
      final declaredSections = <Section>{
        for (final section in Section.values)
          for (final e in manifestForResolution.sectionEntries(section).entries)
            if (e.value.source is ModrinthEntrySource &&
                entryHost(section, e.key, e.value) == host &&
                ((e.value.modrinthSlug ?? e.key) == project.slug ||
                    e.value.modrinthSlug == project.id))
              section,
      };
      if (declaredSections.length > 1) {
        throw ValidationError(
          'Dependency ${project.slug} is declared in multiple sections.',
        );
      }
      final section =
          declaredSections.firstOrNull ??
          inferSectionFromProject(
            projectType: project.projectType,
            loaders: project.loaders,
          );
      var key = project.slug;
      for (final e in manifestForResolution.sectionEntries(section).entries) {
        if (e.value.source is! ModrinthEntrySource) continue;
        if (entryHost(section, e.key, e.value) != host) continue;
        if ((e.value.modrinthSlug ?? e.key) != project.slug &&
            e.value.modrinthSlug != project.id) {
          continue;
        }
        if (!effectiveSources(
              manifestForResolution,
              e.value,
              section,
            ).contains(SourceKind.modrinth) ||
            isAnyGitrinthMarker(e.value.constraintRaw)) {
          throw ValidationError(
            '$parentSlug requires Modrinth ${project.slug}, but top-level ${e.key} excludes that source.',
          );
        }
        key = e.key;
        break;
      }
      if (slugToSection.containsKey(key) && slugToSection[key] != section) {
        throw ValidationError(
          'Dependency $key resolves to conflicting content types; declare a top-level entry in its intended section.',
        );
      }
      final declaredSameKey = manifestForResolution.sectionEntries(
        section,
      )[key];
      if ((declaredSameKey != null &&
              entryHost(section, key, declaredSameKey) != host) ||
          (transitiveHosts.containsKey(key) && transitiveHosts[key] != host)) {
        key = '${project.slug}@${Uri.encodeComponent(host)}';
      }
      slugToSection[key] = section;
      transitiveHosts[key] = host;
      transitiveProjectSlugs[key] = project.slug;
      return slugCache[cacheKey] = key;
    },
    listVersions: (slug) async {
      final section = slugToSection[slug] ?? Section.mods;
      final loaderFilter = filterLoadersForSection(loaderConfig, section);
      final entry = manifestForResolution.sectionEntries(section)[slug];
      final gameVersions = <String>{mc, ...?entry?.acceptsMc}.toList();
      final host = entryHost(section, slug, entry);

      final searched = searchedMrVersions[slug];
      if (searched != null) {
        versionsPerSlug[slug] = searched;
        return searched.map(ModrinthSolverVersion.new).toList();
      }
      if (offline) {
        final lockedProjectId = existingLock
            ?.sectionFor(section)[slug]
            ?.modrinth
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
        return cached.map(ModrinthSolverVersion.new).toList();
      }

      try {
        final list = await apiFactory
            .forHost(host)
            .listVersions(
              entry?.modrinthSlug ?? transitiveProjectSlugs[slug] ?? slug,
              loadersJson: loaderFilter == null
                  ? null
                  : encodeFilterArray(loaderFilter),
              gameVersionsJson: encodeFilterArray(gameVersions),
            );
        versionsPerSlug[slug] = list;
        return list.map(ModrinthSolverVersion.new).toList();
      } on Object catch (e) {
        final anchor = cfResolution.resolved[slug];
        if (e is DioException &&
            e.response?.statusCode == 404 &&
            entry != null &&
            anchor != null) {
          final found = await search.findModrinth(
            slug: slug,
            section: section,
            entry: entry,
            anchor: anchor,
          );
          if (found != null) {
            searchedMrVersions[slug] = found;
            versionsPerSlug[slug] = found;
            return found.map(ModrinthSolverVersion.new).toList();
          }
          final detail = search.diagnostics[slug];
          if (detail != null) {
            throw ValidationError(
              '$slug: $detail\nSet a peer slug override or restrict `sources:`.',
            );
          }
        }
        if (allowMissingSourcesForSlugs.contains(slug) &&
            e is DioException &&
            e.response?.statusCode == 404 &&
            cfResolution.resolved.containsKey(slug)) {
          versionsPerSlug[slug] = [];
          return [];
        }
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
    if (!effectiveSources(
      merged,
      entry,
      section,
    ).contains(SourceKind.modrinth)) {
      continue;
    }
    final loaderFilter = filterLoadersForSection(loaderConfig, section);
    final gameVersions = <String>{mc, ...entry.acceptsMc}.toList();
    final overrideHost = entryHost(section, slug, entry);
    final List<modrinth.Version> candidates;
    if (offline) {
      final lockedProjectId = existingLock
          ?.sectionFor(section)[slug]
          ?.modrinth
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
              entry.modrinthSlug ?? slug,
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
    overridePins[slug] = OverridePin(slug, ModrinthSolverVersion(picked));
    versionsPerSlug[slug] = candidates;
  }

  console.message('Resolving dependencies...');
  console.solver(
    'Resolving with loader.mods=${loaderConfig.mods.name} mc=$mc...',
  );

  // Dispatch gate: compute the set of slugs that Modrinth participates
  // in. Entries whose effective sources exclude Modrinth (e.g.
  // `sources: [curseforge]`) are passed to the CF resolver only.
  final modrinthSlugs = <String>{};
  for (final section in Section.values) {
    merged.sectionEntries(section).forEach((slug, entry) {
      if (entry.source is! ModrinthEntrySource) return;
      if (effectiveSources(
        merged,
        entry,
        section,
      ).contains(SourceKind.modrinth)) {
        modrinthSlugs.add(slug);
      }
    });
  }

  // CF-discovered synthetics may also be present on Modrinth. A missing
  // peer is permitted for synthetics; declared roots remain strict.
  final promotedCfRoots = <String, Section>{};
  Future<bool> promoteCfSynthetics() async {
    var changed = false;
    if (offline || !merged.gitrinth.isPlatformEnabled(SourceKind.modrinth)) {
      return false;
    }
    for (final e in promotedCfRoots.entries.toList()) {
      if (cfResolution.resolved.containsKey(e.key)) continue;
      modrinthSlugs.remove(e.key);
      searchedMrVersions.remove(e.key);
      manifestForResolution = _withoutResolutionEntry(
        manifestForResolution,
        e.value,
        e.key,
      );
      promotedCfRoots.remove(e.key);
      changed = true;
    }
    for (final cf in cfResolution.resolved.values.where((e) => e.transitive)) {
      if (merged.sectionEntries(cf.section).containsKey(cf.slug) ||
          modrinthSlugs.contains(cf.slug)) {
        continue;
      }
      final synthetic = ModEntry(
        slug: cf.slug,
        sources: const {SourceKind.modrinth, SourceKind.curseforge},
      );
      List<modrinth.Version> candidates = [];
      var promotedSlug = cf.slug;
      try {
        final peer = await apiFactory
            .forHost(packHost)
            .getProject(cf.project.slug);
        final peerSection = inferSectionFromProject(
          projectType: peer.projectType,
          loaders: peer.loaders,
        );
        if (peerSection != cf.section) {
          throw ValidationError(
            'Transitive ${cf.slug} resolves to different platform content types; declare its intended section explicitly.',
          );
        }
        candidates = await apiFactory
            .forHost(packHost)
            .listVersions(
              cf.project.slug,
              loadersJson:
                  filterLoadersForSection(loaderConfig, cf.section) == null
                  ? null
                  : encodeFilterArray(
                      filterLoadersForSection(loaderConfig, cf.section)!,
                    ),
              gameVersionsJson: encodeFilterArray([mc]),
            );
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
      if (candidates.isEmpty) {
        candidates =
            await search.findModrinth(
              slug: cf.slug,
              section: cf.section,
              entry: synthetic,
              anchor: cf,
            ) ??
            [];
        if (candidates.isNotEmpty) {
          promotedSlug =
              (await apiFactory
                      .forHost(packHost)
                      .getProject(candidates.first.projectId))
                  .slug;
        }
      }
      if (candidates.isEmpty) continue;
      if (modrinthSlugs.contains(promotedSlug)) continue;
      searchedMrVersions[promotedSlug] = candidates;
      slugToSection[promotedSlug] = cf.section;
      modrinthSlugs.add(promotedSlug);
      promotedCfRoots[promotedSlug] = cf.section;
      changed = true;
      manifestForResolution = _withResolutionEntry(
        manifestForResolution,
        cf.section,
        synthetic.copyWith(slug: promotedSlug),
      );
    }
    return changed;
  }

  await promoteCfSynthetics();

  if (offline && merged.gitrinth.isPlatformEnabled(SourceKind.modrinth)) {
    for (final cf in cfResolution.resolved.values.where((e) => e.transitive)) {
      final prior = existingLock?.sectionFor(cf.section)[cf.slug]?.modrinth;
      if (prior == null) continue;
      modrinthSlugs.add(cf.slug);
      slugToSection[cf.slug] = cf.section;
      transitiveHosts[cf.slug] = prior.host ?? defaultBaseUrl;
      manifestForResolution = _withResolutionEntry(
        manifestForResolution,
        cf.section,
        ModEntry(
          slug: cf.slug,
          source: ModrinthEntrySource(host: prior.host ?? defaultBaseUrl),
          sources: const {SourceKind.modrinth},
        ),
      );
    }
  }

  for (final slug in allowMissingSourcesForSlugs.intersection(modrinthSlugs)) {
    if (!cfResolution.resolved.containsKey(slug)) continue;
    final candidates = await resolver.listVersions(slug);
    if (candidates.isEmpty) modrinthSlugs.remove(slug);
  }
  var resolution = await resolver.resolve(
    manifestForResolution,
    existingLock: lockForResolution,
    overridePins: overridePins,
    modrinthSlugs: modrinthSlugs,
    requiredVersionIds: hashVersionIds,
  );

  final selectedCfFiles = <int, int>{};
  Future<void> refreshCfPeers() async {
    if (offline) return;
    var syntheticManifest = merged;
    final nativeMr = <String>{
      for (final r in resolution.entries)
        if (merged.sectionEntries(r.section).containsKey(r.slug)) r.slug,
    };
    var grew = true;
    while (grew) {
      grew = false;
      for (final parent in resolution.entries.where(
        (r) => nativeMr.contains(r.slug),
      )) {
        for (final child in resolution.entries) {
          if (parent.version.dependencies.any(
                (d) =>
                    d.dependencyType.name == 'required' &&
                    d.projectId == child.version.projectId,
              ) &&
              nativeMr.add(child.slug)) {
            grew = true;
          }
        }
      }
    }
    for (final section in Section.values) {
      for (final e in merged.sectionEntries(section).entries) {
        final prior = cfResolution.resolved[e.key];
        if (prior?.discoveredViaSearch == true) {
          syntheticManifest = _withResolutionEntry(
            syntheticManifest,
            section,
            e.value.copyWith(curseforgeSlug: prior!.project.id.toString()),
          );
        }
      }
    }
    for (final r in resolution.entries) {
      if (merged.sectionEntries(r.section).containsKey(r.slug) ||
          !merged.gitrinth.isPlatformEnabled(SourceKind.curseforge) ||
          !nativeMr.contains(r.slug)) {
        continue;
      }
      syntheticManifest = _withResolutionEntry(
        syntheticManifest,
        r.section,
        ModEntry(
          slug: r.slug,
          curseforgeSlug: cfResolution.resolved[r.slug]?.project.id.toString(),
          sources: const {SourceKind.curseforge},
        ),
      );
    }
    var peers = await resolveCurseforgeEntries(
      manifest: syntheticManifest,
      api: cfApi,
      console: console,
      selectedFiles: selectedCfFiles,
    );
    final discovered = <String>{};
    for (final missing in peers.notFound) {
      if (merged.sectionEntries(missing.section).containsKey(missing.slug)) {
        continue;
      }
      final mrPeer = resolution.entries
          .where((r) => r.slug == missing.slug)
          .firstOrNull;
      if (mrPeer == null || missing.reason != 'slug-not-found') continue;
      final entry = ModEntry(
        slug: missing.slug,
        source: ModrinthEntrySource(
          host: entryHost(missing.section, missing.slug, null),
        ),
        sources: const {SourceKind.modrinth, SourceKind.curseforge},
      );
      final found = await search.findCurseforge(
        slug: missing.slug,
        section: missing.section,
        entry: entry,
        anchors: [mrPeer.version],
      );
      if (found == null) continue;
      discovered.add(missing.slug);
      syntheticManifest = _withResolutionEntry(
        syntheticManifest,
        missing.section,
        entry.copyWith(
          curseforgeSlug: found.project.id.toString(),
          sources: const {SourceKind.curseforge},
        ),
      );
    }
    if (discovered.isNotEmpty) {
      peers = await resolveCurseforgeEntries(
        manifest: syntheticManifest,
        api: cfApi,
        console: console,
        selectedFiles: selectedCfFiles,
      );
    }
    cfResolution = CfResolution(
      resolved: {
        for (final e in peers.resolved.entries)
          e.key: CfResolvedEntry(
            slug: e.value.slug,
            section: e.value.section,
            project: e.value.project,
            file: e.value.file,
            candidates: e.value.candidates,
            requiredBy: e.value.requiredBy,
            transitive: e.value.transitive,
            discoveredViaSearch:
                discovered.contains(e.key) ||
                (cfResolution.resolved[e.key]?.discoveredViaSearch ?? false),
          ),
      },
      notFound: cfResolution.notFound,
    );
  }

  await refreshCfPeers();

  // Different slugs are one identity only when an actual SHA1 pair proves
  // it. Re-key CF to Modrinth before the shared hash/solver convergence loop.
  final reportedSyntheticPairs = <String>{};
  void mergeSyntheticIdentities() {
    final cfEntries = Map<String, CfResolvedEntry>.from(cfResolution.resolved);
    final renamed = <String, String>{};
    for (final r in resolution.entries) {
      if (merged.sectionEntries(r.section).containsKey(r.slug) ||
          cfEntries.containsKey(r.slug)) {
        continue;
      }
      for (final cf in cfEntries.values.toList()) {
        if (merged.sectionEntries(cf.section).containsKey(cf.slug) ||
            resolution.entries.any((e) => e.slug == cf.slug)) {
          continue;
        }
        final outcome = scanForMatchingPair(
          mrCandidates: versionsPerSlug[r.slug] ?? [r.version],
          cfCandidates: cf.candidates,
          hashScanDepth: 10,
          allowHashMismatch: false,
        );
        if (outcome is! HashMatched) {
          if (r.section == cf.section &&
              reportedSyntheticPairs.add('${r.slug}/${cf.slug}')) {
            console.message(
              "Transitive dependencies '${r.slug}' (Modrinth) and '${cf.slug}' (CurseForge) have no hash match within hash_scan_depth. If they are the same project, declare a top-level entry with modrinth: ${r.slug} and curseforge: ${cf.project.slug}; otherwise they remain separate.",
            );
          }
          continue;
        }
        if (r.section != cf.section) {
          throw ValidationError(
            'Hash-identical transitive dependencies ${r.slug} and ${cf.slug} resolve to different content types; declare a top-level entry in its intended section.',
          );
        }
        cfEntries.remove(cf.slug);
        renamed[cf.slug] = r.slug;
        cfEntries[r.slug] = CfResolvedEntry(
          slug: r.slug,
          section: cf.section,
          project: cf.project,
          file: cf.file,
          candidates: cf.candidates,
          transitive: true,
          requiredBy: cf.requiredBy,
        );
        break;
      }
    }
    cfResolution = CfResolution(
      resolved: {
        for (final e in cfEntries.entries)
          e.key: CfResolvedEntry(
            slug: e.value.slug,
            section: e.value.section,
            project: e.value.project,
            file: e.value.file,
            candidates: e.value.candidates,
            discoveredViaSearch: e.value.discoveredViaSearch,
            transitive: e.value.transitive,
            requiredBy: {
              for (final parent in e.value.requiredBy)
                renamed[parent] ?? parent,
            }.toList()..sort(),
          ),
      },
      notFound: cfResolution.notFound,
    );
  }

  if (!offline) mergeSyntheticIdentities();

  // Slug fallback requires a resolved peer as the hash anchor.
  if (!offline) {
    final resolvedCf = Map<String, CfResolvedEntry>.from(cfResolution.resolved);
    final remaining = <CfNotFound>[];
    for (final missing in cfResolution.notFound) {
      final entry = manifestForResolution.sectionEntries(
        missing.section,
      )[missing.slug];
      final mrEntries = resolution.entries
          .where((r) => r.slug == missing.slug)
          .toList();
      CfResolvedEntry? found;
      if (missing.reason == 'slug-not-found' &&
          entry != null &&
          mrEntries.isNotEmpty) {
        found = await search.findCurseforge(
          slug: missing.slug,
          section: missing.section,
          entry: entry,
          anchors: [
            mrEntries.single.version,
            if (!overridePins.containsKey(missing.slug))
              ...eligibleModrinthVersions(
                versionsPerSlug[missing.slug] ?? [],
                entry,
              ).where((v) => v.id != mrEntries.single.version.id),
          ],
        );
      }
      if (found == null) {
        remaining.add(missing);
      } else {
        resolvedCf[missing.slug] = found;
      }
    }
    cfResolution = CfResolution(resolved: resolvedCf, notFound: remaining);
  }

  // Aggregate "missing on a requested platform" failures into a single
  // ValidationError. Modrinth-side: a slug whose effective sources
  // include Modrinth but which the resolver never decided
  // (slugs requested but `versionsPerSlug[slug]` is empty / absent).
  final mrNotFoundSlugs = <String>{};
  final decidedSlugs = {for (final r in resolution.entries) r.slug};
  for (final slug in modrinthSlugs) {
    if (decidedSlugs.contains(slug)) continue;
    if (overridePins.containsKey(slug)) continue;
    final entry = merged.sectionEntries(
      slugToSection[slug] ?? Section.mods,
    )[slug];
    if (entry == null) continue;
    if (isAnyGitrinthMarker(entry.constraintRaw)) continue;
    final mrCandidates = versionsPerSlug[slug];
    if (mrCandidates == null || mrCandidates.isEmpty) {
      mrNotFoundSlugs.add(slug);
    }
  }
  final missingMessage = formatCrossPlatformMissingError(
    manifest: merged,
    mrNotFoundSlugs: mrNotFoundSlugs,
    cfResolution: cfResolution,
    allowedMissingSlugs: {
      for (final slug in allowMissingSourcesForSlugs)
        if (decidedSlugs.contains(slug) ||
            cfResolution.resolved.containsKey(slug))
          slug,
    },
  );
  if (missingMessage != null) {
    throw ValidationError(
      [missingMessage, ...search.diagnostics.values].join('\n'),
    );
  }

  // Hash-scan dual-source entries. For each slug with both Modrinth
  // and CurseForge resolution, compare SHA1s and optionally scan
  // older pairs per `hash_scan_depth`. Skipped under --offline: the
  // synthesized CF resolution carries a single locked candidate per
  // slug, so a scan would either be a no-op or falsely report
  // HashSingleSided.
  final hashOutcomes = <String, HashOutcome>{};

  if (!offline) {
    var passes = 0;
    while (true) {
      if (++passes > 100) {
        throw const ValidationError(
          'Cross-platform hash selection did not converge; pin peer versions explicitly.',
        );
      }
      await refreshCfPeers();
      mergeSyntheticIdentities();
      if (await promoteCfSynthetics()) {
        resolution = await resolver.resolve(
          manifestForResolution,
          existingLock: lockForResolution,
          overridePins: overridePins,
          modrinthSlugs: modrinthSlugs,
          requiredVersionIds: hashVersionIds,
        );
        continue;
      }
      mergeSyntheticIdentities();
      hashOutcomes.clear();
      var needsResolve = false;
      for (final r in resolution.entries) {
        var cf = cfResolution.resolved[r.slug];
        if (cf == null) continue;
        if (r.section != cf.section) {
          throw ValidationError(
            'Transitive ${r.slug} resolves to different content types across platforms; declare a top-level entry in its intended section.',
          );
        }
        final entry = manifestForResolution.sectionEntries(r.section)[r.slug];
        final depth = entry?.hashScanDepth ?? 10;
        final allow = entry?.allowHashMismatch ?? false;
        final allowed = eligibleModrinthVersions(
          versionsPerSlug[r.slug] ?? [r.version],
          entry,
        );
        final mrCandidates = [
          r.version,
          if (!overridePins.containsKey(r.slug))
            ...allowed.where((v) => v.id != r.version.id),
        ];
        var outcome = scanForMatchingPair(
          mrCandidates: mrCandidates,
          cfCandidates: cf.candidates,
          hashScanDepth: depth,
          allowHashMismatch: allow,
        );
        if (outcome is HashExhausted && entry != null) {
          final foundCf = await search.findCurseforge(
            slug: r.slug,
            section: r.section,
            entry: entry,
            anchors: mrCandidates,
            excludeProject: cf.project.id,
          );
          if (foundCf != null) {
            cf = foundCf;
            cfResolution = CfResolution(
              resolved: {...cfResolution.resolved, r.slug: cf},
              notFound: cfResolution.notFound,
            );
          } else if (!overridePins.containsKey(r.slug)) {
            final foundMr = await search.findModrinth(
              slug: r.slug,
              section: r.section,
              entry: entry,
              anchor: cf,
              excludeProject: r.version.projectId,
            );
            if (foundMr != null) searchedMrVersions[r.slug] = foundMr;
          }
          outcome = scanForMatchingPair(
            mrCandidates: searchedMrVersions[r.slug] ?? mrCandidates,
            cfCandidates: cf.candidates,
            hashScanDepth: depth,
            allowHashMismatch: allow,
          );
        }
        final matchedMr = switch (outcome) {
          HashMatched(:final modrinthVersion) => modrinthVersion,
          HashAcceptedMismatch(:final modrinthVersion) => modrinthVersion,
          _ => null,
        };
        final matchedCf = switch (outcome) {
          HashMatched(:final curseforgeFile) => curseforgeFile,
          HashAcceptedMismatch(:final curseforgeFile) => curseforgeFile,
          _ => null,
        };
        if (matchedCf != null) selectedCfFiles[cf.project.id] = matchedCf.id;
        if (matchedMr != null && matchedMr.id != r.version.id) {
          hashVersionIds[r.slug] = matchedMr.id;
          needsResolve = true;
        }
        hashOutcomes[r.slug] = outcome;
        if (outcome is HashAcceptedMismatch) {
          console.warn(
            '${r.slug}: SHA1 mismatch between Modrinth (${outcome.modrinthVersion.versionNumber}) '
            'and CurseForge (file ${outcome.curseforgeFile.fileName}); '
            'accepting because allow_hash_mismatch: true.',
          );
        } else if (outcome is HashExhausted) {
          throw ValidationError(
            '${r.slug}: SHA1 mismatch between Modrinth and CurseForge.\n'
            '  Modrinth (project ${outcome.newestModrinth.projectId}, version '
            '${outcome.newestModrinth.versionNumber}): '
            '${outcome.newestModrinth.primaryFile?.hashes['sha1']}\n'
            '  CurseForge (project ${cf.project.id}, file '
            '${outcome.newestCurseforge.id}): '
            '${outcome.newestCurseforge.sha1Hash}\n'
            '  Scanned ${outcome.depthExamined} older versions on both '
            'platforms; no match found.\n'
            'Resolution options:\n'
            '  - Set `allow_hash_mismatch: true` on this entry to accept '
            'the divergence\n'
            '  - Restrict to a single platform: `sources: [modrinth]` or '
            '`sources: [curseforge]`\n'
            '  - Pin per-platform versions explicitly in mods.yaml\n'
            '${search.diagnostics[r.slug] ?? ''}',
          );
        }
      }
      // Rewalk selected CF files on the next pass before accepting a graph.
      if (cfResolution.resolved.values.any(
        (cf) =>
            selectedCfFiles.containsKey(cf.project.id) &&
            selectedCfFiles[cf.project.id] != cf.file.id,
      )) {
        needsResolve = true;
      }
      if (!needsResolve) break;
      resolution = await resolver.resolve(
        manifestForResolution,
        existingLock: lockForResolution,
        overridePins: overridePins,
        modrinthSlugs: modrinthSlugs,
        requiredVersionIds: hashVersionIds,
      );
    }
  }

  if (offline && existingLock != null) {
    var graphManifest = merged;
    if (merged.gitrinth.isPlatformEnabled(SourceKind.curseforge)) {
      for (final r in resolution.entries) {
        if (merged.sectionEntries(r.section).containsKey(r.slug)) continue;
        graphManifest = _withResolutionEntry(
          graphManifest,
          r.section,
          ModEntry(slug: r.slug, sources: const {SourceKind.curseforge}),
        );
      }
    }
    cfResolution = synthesizeCfResolutionFromLock(
      existingLock,
      manifest: graphManifest,
    );
  }

  final newLock = buildLock(
    hostFor: (section, slug) => offline
        ? existingLock?.sectionFor(section)[slug]?.modrinth?.host
        : (entryHost(section, slug, null) == defaultBaseUrl
              ? null
              : entryHost(section, slug, null)),
    manifest: merged,
    resolution: resolution,
    cfResolution: cfResolution,
    hashOutcomes: hashOutcomes,
    modrinthSearchSlugs: offline
        ? {
            for (final section in Section.values)
              for (final e
                  in existingLock?.sectionFor(section).entries ??
                      <MapEntry<String, LockedEntry>>[])
                if (e.value.modrinth?.discoveredViaSearch ?? false) e.key,
          }
        : search.modrinthSearchSlugs,
    resolvedModLoaderVersion: resolvedModLoaderVersion,
    resolvedPluginLoaderVersion: resolvedPluginLoaderVersion,
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
  persistVersionMetadata(
    resolution,
    cache,
    console,
    (r) => entryHost(r.section, r.slug, null),
  );

  final fetchResult = await downloadArtifacts(
    lock: newLock,
    cache: cache,
    downloader: downloader,
    console: console,
    io: io,
    hostFor: (section, slug) => entryHost(section, slug, null),
  );
  final downloaded = fetchResult.downloaded;
  final hits = fetchResult.hits;
  final fetchErrors = fetchResult.errors;
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

/// Rebuilds a [CfResolution] from the CurseForge source blocks already
/// recorded in [lock]. Used by the offline path so [buildLock] re-emits
/// every prior `curseforge:` block byte-for-byte without a network walk.
///
/// The synthesized [CfResolvedEntry.project] / [CfResolvedEntry.file]
/// only populate the fields the lock builder actually reads
/// (`project.id`, `project.slug`, `project.allowModDistribution`,
/// `file.id`, `file.fileName`, `file.downloadUrl`, `file.sha1Hash`,
/// `file.gameVersions`); other fields carry placeholder values.
/// `candidates` holds the single locked file — the offline path skips
/// the hash-scan loop, so the list is never walked beyond `.first`.
CfResolution synthesizeCfResolutionFromLock(
  ModsLock lock, {
  ModsYaml? manifest,
}) {
  final resolved = <String, CfResolvedEntry>{};
  final retained = <String>{};
  if (manifest != null) {
    for (final section in Section.values) {
      for (final e in manifest.sectionEntries(section).entries) {
        if (e.value.source is ModrinthEntrySource &&
            !isAnyGitrinthMarker(e.value.constraintRaw) &&
            effectiveSources(
              manifest,
              e.value,
              section,
            ).contains(SourceKind.curseforge)) {
          retained.add(e.key);
        }
      }
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final e in lock.allEntries) {
        if (e.value.dependency != LockedDependencyKind.transitive ||
            e.value.curseforge == null) {
          continue;
        }
        if (e.value.requiredBy.any(retained.contains) && retained.add(e.key)) {
          changed = true;
        }
      }
    }
  }
  for (final section in Section.values) {
    for (final entry in lock.sectionFor(section).entries) {
      final slug = entry.key;
      if (manifest != null) {
        final declared = manifest.sectionEntries(section)[slug];
        if (!retained.contains(slug) ||
            (declared != null &&
                (declared.source is! ModrinthEntrySource ||
                    isAnyGitrinthMarker(declared.constraintRaw) ||
                    !effectiveSources(
                      manifest,
                      declared,
                      section,
                    ).contains(SourceKind.curseforge)))) {
          continue;
        }
      }
      final cf = entry.value.curseforge;
      if (cf == null) continue;
      final sha1 = cf.file.sha1;
      final synthFile = ModFile(
        id: cf.fileId,
        modId: cf.projectId,
        displayName: entry.value.modrinth == null
            ? entry.value.version ?? cf.file.name
            : cf.file.name,
        fileName: cf.file.name,
        releaseType: 1,
        fileDate: '',
        gameVersions: List<String>.from(cf.gameVersions),
        hashes: sha1 == null ? const [] : [FileHash(value: sha1, algoCode: 1)],
        dependencies: const [],
        downloadUrl: cf.file.url,
      );
      final synthMod = Mod(
        id: cf.projectId,
        gameId: kCurseForgeGameIdMinecraft,
        name: cf.slug ?? slug,
        slug: cf.slug ?? slug,
        classId: 0,
        latestFiles: [synthFile],
        allowModDistribution: cf.allowModDistribution,
      );
      resolved[slug] = CfResolvedEntry(
        slug: slug,
        section: section,
        project: synthMod,
        file: synthFile,
        candidates: [synthFile],
        discoveredViaSearch: cf.discoveredViaSearch,
        requiredBy: entry.value.requiredBy
            .where((p) => manifest == null || retained.contains(p))
            .toList(),
        transitive: entry.value.dependency == LockedDependencyKind.transitive,
      );
    }
  }
  return CfResolution(resolved: resolved, notFound: const []);
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

ModsYaml _withResolutionEntry(
  ModsYaml manifest,
  Section section,
  ModEntry entry,
) {
  final entries = {...manifest.sectionEntries(section), entry.slug: entry};
  return manifest.withSectionEntries(section, entries);
}

ModsYaml _withoutResolutionEntry(
  ModsYaml manifest,
  Section section,
  String slug,
) {
  final entries = {...manifest.sectionEntries(section)}..remove(slug);
  return manifest.withSectionEntries(section, entries);
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
  return merged.mapSectionEntries((_, entries) => relaxSection(entries));
}
