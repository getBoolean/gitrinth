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
Future<ResolveSyncResult> resolveAndSync({
  required ManifestIo io,
  required Console console,
  required ModrinthApi api,
  required GitrinthCache cache,
  required Downloader downloader,
  required bool verbose,
  bool dryRun = false,
  bool enforce = false,
}) async {
  final reporter = SolveReporter(console);

  final manifest = io.readModsYaml();
  final overrides = io.readOverrides();
  final merged = applyOverrides(manifest, overrides);
  final existingLock = io.readModsLock();

  if (enforce) {
    _checkUserEntriesPresentInLock(merged, existingLock);
  }

  final loaderConfig = merged.loader;
  final mc = merged.mcVersion;
  final slugCache = <String, String?>{};

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
        final list = await api.listVersions(
          slug,
          loadersJson: loaderFilter == null
              ? null
              : encodeFilterArray(loaderFilter),
          gameVersionsJson: encodeFilterArray([mc]),
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
  final resolution = await resolver.resolve(merged, existingLock: existingLock);

  final newLock = _buildLock(merged, resolution);
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

ModsLock _buildLock(ModsYaml manifest, ResolutionResult resolution) {
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
        sha512: r.file.sha512,
        size: r.file.size,
      ),
      env: r.env,
      auto: r.auto,
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
        );
      } else if (src is PathEntrySource) {
        byKind[section]![slug] = LockedEntry(
          slug: slug,
          sourceKind: LockedSourceKind.path,
          path: src.path,
          env: entry.env,
        );
      }
    });
  }
  return ModsLock(
    gitrinthVersion: packageVersion,
    loader: manifest.loader,
    mcVersion: manifest.mcVersion,
    mods: byKind[Section.mods]!,
    resourcePacks: byKind[Section.resourcePacks]!,
    dataPacks: byKind[Section.dataPacks]!,
    shaders: byKind[Section.shaders]!,
  );
}

String _filenameFromUrl(String url) {
  final uri = Uri.parse(url);
  if (uri.pathSegments.isEmpty) return 'artifact.jar';
  return uri.pathSegments.last;
}
