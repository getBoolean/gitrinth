import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../cli/base_command.dart';
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
import '../service/manifest_io.dart';
import '../service/modrinth_api.dart';
import '../service/solve_report.dart';
import '../version.dart';

class GetCommand extends GitrinthCommand {
  @override
  String get name => 'get';

  @override
  String get description =>
      'Resolve mods.yaml, write mods.lock, download artifacts.';

  @override
  String get invocation => 'gitrinth get [arguments]';

  GetCommand() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Resolve without writing. Exits non-zero if the lockfile would change.',
      )
      ..addFlag(
        'enforce-lockfile',
        negatable: false,
        help:
            'Fail if mods.lock would change. Also forbids missing lockfile entries.',
      );
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final dryRun = results['dry-run'] as bool;
    final enforce = results['enforce-lockfile'] as bool;

    final api = read(modrinthApiProvider);
    final cache = read(cacheProvider);
    final downloader = read(downloaderProvider);
    final reporter = SolveReporter(console);

    final io = ManifestIo();
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
        case Section.dataPacks:
          return null;
      }
    }

    // Captured list of loader+mc-compatible Modrinth versions per slug,
    // populated as the resolver asks for them. Reused after resolution to
    // report a "(X available)" hint when the chosen version isn't the newest.
    final versionsPerSlug = <String, List<modrinth.Version>>{};

    final resolver = Resolver(
      listVersions: (slug) async {
        try {
          final section = slugToSection[slug] ?? Section.mods;
          final loaderFilter = filterForSection(section);
          final list = await api.listVersions(
            slug,
            loadersJson:
                loaderFilter == null ? null : encodeFilterArray(loaderFilter),
            gameVersionsJson: encodeFilterArray([mc]),
          );
          versionsPerSlug[slug] = list;
          return list;
        } on Object catch (e) {
          // ModrinthErrorInterceptor wraps HTTP failures in a DioException
          // whose .error is a GitrinthException with a user-friendly message
          // (including the 404 "project not found" case). Surface it as-is
          // rather than prefixing "failed to list versions for $slug:".
          final err = (e is DioException) ? e.error : e;
          if (err is GitrinthException) throw err;
          throw UserError('failed to list versions for $slug: $e');
        }
      },
      resolveSlugForProjectId: (projectId) async {
        if (slugCache.containsKey(projectId)) return slugCache[projectId];
        try {
          final Project p = await api.getProject(projectId);
          slugCache[projectId] = p.slug;
          return p.slug;
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

    if (gitrinthRunner.verbose) {
      reporter.printSimpleDiff(diff, verbose: gitrinthRunner.verbose);
    }

    if (enforce && diff.isNotEmpty) {
      throw ValidationError(
        'mods.lock is out of date (--enforce-lockfile). '
        '${diff.length} change(s) would be applied.',
      );
    }

    if (dryRun) {
      reporter.printSimpleDiff(diff, verbose: gitrinthRunner.verbose, force: true);
      if (diff.isNotEmpty) {
        return exitValidationError;
      }
      return exitOk;
    }

    final newLockText = emitModsLock(newLock);
    io.writeModsLock(newLockText);

    // `merged.overrides` is the union of in-file `overrides:` and the
    // standalone mods_overrides.yaml file — i.e., every slug whose source or
    // version pin was redirected away from its section declaration.
    reporter.printReport(
      newLock: newLock,
      diff: diff,
      versionsPerSlug: versionsPerSlug,
      overriddenSlugs: merged.overrides.keys.toSet(),
    );

    // Second pass — actually fetch/validate artifacts. Errors are collected
    // rather than thrown so a single run surfaces every problem; we throw
    // the aggregated ValidationError after the loop finishes.
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
              // url-source caching is keyed by sha512; if we don't have one
              // (first download) we use a slug-stable filename under the
              // unverified prefix.
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
              // Nothing to fetch, but the file must exist — otherwise the
              // modpack would build/publish with a phantom mod. Paths are
              // resolved relative to the pack directory (where mods.yaml
              // lives) so the manifest stays portable.
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
    reporter.printSummary(changeCount: changeCount, outdated: outdated);
    console.detail(
      'Locked $changeCount change(s); $downloaded downloaded, $hits cache hit(s).',
    );

    return exitOk;
  }

  void _checkUserEntriesPresentInLock(ModsYaml manifest, ModsLock? lock) {
    if (lock == null) {
      throw const ValidationError(
        'mods.lock is missing (--enforce-lockfile).',
      );
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
    // url: and path: entries from the manifest.
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
}
