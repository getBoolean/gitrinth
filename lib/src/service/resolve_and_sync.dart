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
import '../model/resolver/resolver.dart';
import '../model/resolver/result.dart';
import '../version.dart';
import 'cache.dart';
import 'console.dart';
import 'downloader.dart';
import 'loader_version_resolver.dart';
import 'manifest_io.dart';
import 'modrinth_api.dart';
import 'solve_report.dart';

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
Future<ResolveSyncResult> resolveAndSync({
  required ManifestIo io,
  required Console console,
  required ModrinthApi api,
  required GitrinthCache cache,
  required Downloader downloader,
  required LoaderVersionResolver loaderResolver,
  required bool verbose,
  bool dryRun = false,
  bool enforce = false,
  Set<String> freshSlugs = const {},
  Set<String> relaxConstraints = const {},
}) async {
  final reporter = SolveReporter(console);

  final manifest = io.readModsYaml();
  final overrides = io.readOverrides();
  final merged = applyOverrides(manifest, overrides);
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
  final slugCache = <String, String?>{};

  // One-shot mc-version validation: only call /tag/game_version when the
  // mc-version differs from what mods.lock already records. The pairing
  // was already validated when it was first locked, so a stable lock is
  // proof enough.
  if (existingLock?.mcVersion != mc) {
    await _validateGameVersion(api: api, mcVersion: mc);
  }

  // Loader-tag resolution. Concrete tags pass through unchanged with no
  // network call; `stable` / `latest` always re-resolve (those tags exist
  // precisely to drift). For concrete tags that already match the lock,
  // skip even the passthrough — the lock is the cache.
  final resolvedLoaderVersion = await _resolveLoaderVersion(
    loaderResolver: loaderResolver,
    loaderConfig: loaderConfig,
    mcVersion: mc,
    existingLock: existingLock,
  );

  final slugToSection = <String, Section>{};
  for (final section in Section.values) {
    for (final slug in merged.sectionEntries(section).keys) {
      slugToSection[slug] = section;
    }
  }

  List<String>? filterForSection(Section section) {
    switch (section) {
      case Section.mods:
        return [loaderConfig.mods.name];
      case Section.shaders:
        return [loaderConfig.shaders!.name];
      case Section.resourcePacks:
        return const ['minecraft'];
      case Section.dataPacks:
        return const ['datapack'];
    }
  }

  final versionsPerSlug = <String, List<modrinth.Version>>{};

  final resolver = Resolver(
    listVersions: (slug) async {
      try {
        final section = slugToSection[slug] ?? Section.mods;
        final loaderFilter = filterForSection(section);
        final entry = merged.sectionEntries(section)[slug];
        final gameVersions = <String>{mc, ...?entry?.acceptsMc}.toList();
        final list = await api.listVersions(
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
        final Project proj = await api.getProject(projectId);
        slugCache[projectId] = proj.slug;
        return proj.slug;
      } on Object {
        slugCache[projectId] = null;
        return null;
      }
    },
  );

  console.info('Resolving dependencies...');
  console.detail(
    'Resolving with loader.mods=${loaderConfig.mods.name} mc=$mc...',
  );
  final resolution = await resolver.resolve(
    manifestForResolution,
    existingLock: lockForResolution,
  );

  final newLock = _buildLock(merged, resolution, resolvedLoaderVersion);
  final diff = diffLocks(existingLock, newLock);

  if (verbose) {
    reporter.printSimpleDiff(diff, verbose: verbose);
  }

  if (enforce && diff.isNotEmpty) {
    throw ValidationError(
      'mods.lock is out of date (--enforce-lockfile). '
      '${diff.length} change(s) would be applied.',
    );
  }

  if (dryRun) {
    reporter.printSimpleDiff(diff, verbose: verbose, force: true);
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
    overriddenSlugs: merged.overrides.keys.toSet(),
  );

  // Persist each resolved Modrinth version's dependency list to the
  // artifact cache, sibling to the .jar. Mirrors dart pub's
  // "graph-in-cache" architecture: `mods.lock` no longer carries
  // forward edges; future `gitrinth upgrade --unlock-transitive`
  // recomputes the closure from these JSON files. Failure here warns
  // but doesn't abort — the artifact download is the contract.
  _persistVersionMetadata(resolution, cache, console);

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
            if (file == null || file.url == null) continue;
            final dest = cache.modrinthPath(
              projectId: locked.projectId!,
              versionId: locked.versionId!,
              filename: file.name,
            );
            final existed = File(dest).existsSync();
            await downloader.downloadTo(
              url: file.url!,
              destinationPath: dest,
              expectedSha512: file.sha512,
            );
            if (existed) {
              hits++;
              console.detail('cache hit:  ${locked.slug} -> $dest');
            } else {
              downloaded++;
              console.detail('downloaded: ${locked.slug} -> $dest');
            }
            break;
          case LockedSourceKind.url:
            final file = locked.file;
            if (file == null || file.url == null) continue;
            final dest = file.sha512 != null
                ? cache.urlPath(sha512: file.sha512!, filename: file.name)
                : p.join(cache.urlRoot, '_unverified', locked.slug, file.name);
            final existed = File(dest).existsSync();
            await downloader.downloadTo(
              url: file.url!,
              destinationPath: dest,
              expectedSha512: file.sha512,
            );
            if (existed) {
              hits++;
            } else {
              downloaded++;
            }
            break;
          case LockedSourceKind.path:
            final rawPath = locked.path!;
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
  console.detail(
    'Locked $changeCount change(s); $downloaded downloaded, $hits cache hit(s).',
  );

  return ResolveSyncResult(
    newLock: newLock,
    diff: diff,
    changeCount: changeCount,
    outdated: outdated,
    exitCode: exitOk,
  );
}

void _checkUserEntriesPresentInLock(ModsYaml manifest, ModsLock? lock) {
  if (lock == null) {
    throw const ValidationError('mods.lock is missing (--enforce-lockfile).');
  }
  final missing = <String>[];
  for (final section in Section.values) {
    final entries = manifest.sectionEntries(section);
    final lockSection = lock.sectionFor(section);
    for (final slug in entries.keys) {
      if (!lockSection.containsKey(slug)) missing.add(slug);
    }
  }
  if (missing.isNotEmpty) {
    throw ValidationError(
      'mods.lock is missing user-declared entries (--enforce-lockfile): '
      '${missing.join(', ')}',
    );
  }
}

ModsLock _buildLock(
  ModsYaml manifest,
  ResolutionResult resolution,
  String resolvedLoaderVersion,
) {
  final byKind = <Section, Map<String, LockedEntry>>{
    for (final s in Section.values) s: <String, LockedEntry>{},
  };
  for (final r in resolution.entries) {
    byKind[r.section]![r.slug] = LockedEntry(
      slug: r.slug,
      sourceKind: LockedSourceKind.modrinth,
      version: r.version.versionNumber,
      projectId: r.version.projectId,
      versionId: r.version.id,
      file: LockedFile(
        name: r.file.filename,
        url: r.file.url,
        sha1: r.file.hashes['sha1'],
        sha512: r.file.sha512,
        size: r.file.size,
      ),
      env: r.env,
      dependency: r.dependency,
      gameVersions: List.unmodifiable(r.version.gameVersions),
      optional: r.optional,
    );
  }
  for (final section in Section.values) {
    final entries = manifest.sectionEntries(section);
    entries.forEach((slug, entry) {
      final src = entry.source;
      if (src is UrlEntrySource) {
        byKind[section]![slug] = LockedEntry(
          slug: slug,
          sourceKind: LockedSourceKind.url,
          file: LockedFile(name: _filenameFromUrl(src.url), url: src.url),
          env: entry.env,
          optional: entry.optional,
        );
      } else if (src is PathEntrySource) {
        byKind[section]![slug] = LockedEntry(
          slug: slug,
          sourceKind: LockedSourceKind.path,
          path: src.path,
          env: entry.env,
          optional: entry.optional,
        );
      }
    });
  }
  // Bake the resolved concrete loader version into the lock's LoaderConfig.
  final lockedLoader = LoaderConfig(
    mods: manifest.loader.mods,
    modsVersion: resolvedLoaderVersion,
    shaders: manifest.loader.shaders,
    plugins: manifest.loader.plugins,
  );
  return ModsLock(
    gitrinthVersion: packageVersion,
    loader: lockedLoader,
    mcVersion: manifest.mcVersion,
    mods: byKind[Section.mods]!,
    resourcePacks: byKind[Section.resourcePacks]!,
    dataPacks: byKind[Section.dataPacks]!,
    shaders: byKind[Section.shaders]!,
  );
}

/// Writes a `version.json` next to each resolved Modrinth artifact in
/// the cache, capturing that version's `dependencies` array. The file
/// is the on-disk source of truth for transitive-dep walking — the
/// gitrinth analogue of pub's per-package `pubspec.yaml` cache. Best
/// effort: a write failure logs a warn but doesn't abort the resolve,
/// because the artifact download is the user-visible contract.
void _persistVersionMetadata(
  ResolutionResult resolution,
  GitrinthCache cache,
  Console console,
) {
  for (final r in resolution.entries) {
    final pid = r.version.projectId;
    final vid = r.version.id;
    if (pid.isEmpty || vid.isEmpty) continue;
    final path = cache.modrinthVersionMetadataPath(
      projectId: pid,
      versionId: vid,
    );
    try {
      Directory(p.dirname(path)).createSync(recursive: true);
      final body = <String, dynamic>{
        'dependencies': [
          for (final d in r.version.dependencies)
            <String, dynamic>{
              'project_id': d.projectId,
              'version_id': d.versionId,
              'dependency_type': d.dependencyType.name,
            },
        ],
      };
      File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(body));
    } on Object catch (e) {
      console.warn(
        'cache: failed to persist version metadata for ${r.slug} '
        '(${r.version.versionNumber}): $e',
      );
    }
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
    if (e is GitrinthException) rethrow;
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
Future<String> _resolveLoaderVersion({
  required LoaderVersionResolver loaderResolver,
  required LoaderConfig loaderConfig,
  required String mcVersion,
  required ModsLock? existingLock,
}) async {
  final tag = loaderConfig.modsVersion;
  final lockedSameLoader = existingLock?.loader.mods == loaderConfig.mods;
  final lockedVersion = existingLock?.loader.modsVersion;
  final tagIsConcrete = tag != 'stable' && tag != 'latest';
  if (tagIsConcrete && lockedSameLoader && lockedVersion == tag) {
    return tag;
  }
  return loaderResolver.resolve(
    loader: loaderConfig.mods,
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
  );
}

String _filenameFromUrl(String url) {
  final uri = Uri.parse(url);
  if (uri.pathSegments.isEmpty) return 'artifact.jar';
  return uri.pathSegments.last;
}
