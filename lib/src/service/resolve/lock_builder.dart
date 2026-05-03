import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../model/curseforge/cf_mod_file.dart';
import '../../model/manifest/mods_lock.dart';
import '../../model/manifest/mods_yaml.dart';
import '../../model/manifest/source_eligibility.dart';
import '../../model/modrinth/version.dart' as modrinth;
import '../../model/resolver/result.dart';
import '../../version.dart';
import '../cache.dart';
import '../console.dart';
import 'curseforge_resolver.dart';
import 'hash_scan.dart';

/// Builds the new `ModsLock` from the resolved Modrinth versions plus
/// CurseForge resolution + hash-scan outcomes plus the manifest's
/// url:/path: entries (which never enter the resolver) and `files:`
/// entries (which are manifest-only).
///
/// For dual-source slugs (both [resolution] and [cfResolution] resolved
/// the entry), the [hashOutcomes] map carries the per-slug
/// [HashOutcome] result. When the outcome is [HashMatched] /
/// [HashAcceptedMismatch], both source blocks are populated; the
/// Modrinth block uses the matched/accepted Modrinth version and the
/// CurseForge block uses the matched/accepted CurseForge file.
ModsLock buildLock({
  required ModsYaml manifest,
  required ResolutionResult resolution,
  required CfResolution cfResolution,
  required Map<String, HashOutcome> hashOutcomes,
  required String? resolvedModLoaderVersion,
  required String? resolvedPluginLoaderVersion,
}) {
  final mods = <String, LockedEntry>{};
  final resourcePacks = <String, LockedEntry>{};
  final dataPacks = <String, LockedEntry>{};
  final shaders = <String, LockedEntry>{};
  final plugins = <String, LockedEntry>{};
  final byKind = <Section, Map<String, LockedEntry>>{
    Section.mods: mods,
    Section.resourcePacks: resourcePacks,
    Section.dataPacks: dataPacks,
    Section.shaders: shaders,
    Section.plugins: plugins,
  };

  // Index Modrinth resolutions by slug to merge with CF resolution.
  final mrBySlug = <String, ResolvedEntry>{
    for (final r in resolution.entries) r.slug: r,
  };

  // Walk every Modrinth-resolved slug, applying any matching CF block
  // and hash outcome. Modrinth-only entries pass through unchanged.
  for (final r in resolution.entries) {
    final sectionMap = byKind[r.section];
    if (sectionMap == null) {
      throw StateError('lock_builder: unknown section ${r.section}');
    }
    final entry = manifest.sectionEntries(r.section)[r.slug];
    final cf = cfResolution.resolved[r.slug];
    final outcome = hashOutcomes[r.slug];
    sectionMap[r.slug] = _buildResolvedEntry(
      slug: r.slug,
      manifestEntry: entry,
      mrEntry: r,
      cfEntry: cf,
      hashOutcome: outcome,
    );
  }

  // CF-only entries: a slug that resolved on CF but not on Modrinth
  // (for example `sources: [curseforge]`). These have no Modrinth
  // ResolvedEntry, so they wouldn't appear in the loop above.
  for (final cf in cfResolution.resolved.values) {
    if (mrBySlug.containsKey(cf.slug)) continue;
    final sectionMap = byKind[cf.section];
    if (sectionMap == null) continue;
    final entry = manifest.sectionEntries(cf.section)[cf.slug];
    sectionMap[cf.slug] = _buildResolvedEntry(
      slug: cf.slug,
      manifestEntry: entry,
      mrEntry: null,
      cfEntry: cf,
      hashOutcome: null,
    );
  }

  for (final section in Section.values) {
    final sectionMap = byKind[section];
    if (sectionMap == null) {
      throw StateError('lock_builder: unknown section $section');
    }
    final entries = manifest.sectionEntries(section);
    entries.forEach((slug, entry) {
      final src = entry.source;
      if (src is UrlEntrySource) {
        sectionMap[slug] = LockedEntry(
          slug: slug,
          kind: LockedEntryKind.url,
          url: src.url,
          urlFile: LockedFile(name: filenameFromUrl(src.url), url: src.url),
          client: entry.client,
          server: entry.server,
        );
      } else if (src is PathEntrySource) {
        sectionMap[slug] = LockedEntry(
          slug: slug,
          kind: LockedEntryKind.path,
          path: src.path,
          client: entry.client,
          server: entry.server,
        );
      }
    });
  }
  // Bake the resolved concrete loader version into the lock's LoaderConfig.
  final lockedLoader = LoaderConfig(
    mods: manifest.loader.mods,
    modLoaderVersion: resolvedModLoaderVersion,
    shaders: manifest.loader.shaders,
    plugins: manifest.loader.plugins,
    pluginLoaderVersion: resolvedPluginLoaderVersion,
  );
  // Forward `files:` entries verbatim. `files:` is manifest-only — no
  // pubgrub resolution, no Modrinth round-trip — so the lock entry is
  // a 1:1 mirror of the FileEntry. Source-existence is verified later
  // in the artifact-fetch loop (mirrors `path:` mod entries).
  final lockedFiles = <String, LockedFileEntry>{
    for (final e in manifest.files.entries)
      e.key: LockedFileEntry(
        destination: e.value.destination,
        sourcePath: e.value.sourcePath,
        client: e.value.client,
        server: e.value.server,
        preserve: e.value.preserve,
      ),
  };
  return ModsLock(
    gitrinthVersion: packageVersion,
    loader: lockedLoader,
    mcVersion: manifest.mcVersion,
    mods: mods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
    plugins: plugins,
    files: lockedFiles,
  );
}

LockedEntry _buildResolvedEntry({
  required String slug,
  required ModEntry? manifestEntry,
  required ResolvedEntry? mrEntry,
  required CfResolvedEntry? cfEntry,
  required HashOutcome? hashOutcome,
}) {
  // For dual-source entries, prefer the (mrPicked, cfPicked) returned
  // by the hash scan when it found a match (or accepted a mismatch).
  // For single-source entries, the resolver's pick is the only one.
  modrinth.Version? finalMr;
  ModFile? finalCf;
  if (hashOutcome is HashMatched) {
    finalMr = hashOutcome.modrinthVersion;
    finalCf = hashOutcome.curseforgeFile;
  } else if (hashOutcome is HashAcceptedMismatch) {
    finalMr = hashOutcome.modrinthVersion;
    finalCf = hashOutcome.curseforgeFile;
  } else {
    // No outcome (single-source entry) or HashSingleSided / unhandled.
    finalMr = mrEntry?.version;
    finalCf = cfEntry?.file;
  }

  LockedModrinthSource? mrSource;
  if (finalMr != null && mrEntry != null) {
    final file = mrEntry.file;
    mrSource = LockedModrinthSource(
      projectId: finalMr.projectId,
      versionId: finalMr.id,
      versionNumber: finalMr.versionNumber,
      file: LockedFile(
        name: file.filename,
        url: file.url,
        sha1: file.hashes['sha1']?.toLowerCase(),
        sha512: file.sha512,
        size: file.size,
      ),
      gameVersions: List.unmodifiable(finalMr.gameVersions),
    );
  }

  LockedCurseforgeSource? cfSource;
  if (finalCf != null && cfEntry != null) {
    cfSource = LockedCurseforgeSource(
      projectId: cfEntry.project.id,
      fileId: finalCf.id,
      slug: cfEntry.project.slug,
      file: LockedFile(
        name: finalCf.fileName,
        url: finalCf.downloadUrl,
        sha1: finalCf.sha1Hash,
        size: null,
      ),
      gameVersions: List.unmodifiable(finalCf.gameVersions),
      allowModDistribution: cfEntry.project.allowModDistribution,
    );
  }

  // Joint label: Modrinth's versionNumber when present, else
  // CurseForge's fileName. Used for the human-facing `version:` line.
  final jointLabel = mrSource?.versionNumber ?? cfSource?.file.name;

  // Sides + dependency follow Modrinth's resolved entry when present,
  // else fall back to manifest defaults (CF-only entries don't go
  // through PubGrub).
  final defaults = defaultSidesFor(
    mrEntry?.section ?? cfEntry?.section ?? Section.mods,
  );
  final client = mrEntry?.client ?? manifestEntry?.client ?? defaults.client;
  final server = mrEntry?.server ?? manifestEntry?.server ?? defaults.server;
  final dependency = mrEntry?.dependency ?? LockedDependencyKind.direct;

  return LockedEntry(
    slug: slug,
    kind: LockedEntryKind.resolved,
    version: jointLabel,
    modrinth: mrSource,
    curseforge: cfSource,
    client: client,
    server: server,
    dependency: dependency,
    acceptsMc: List.unmodifiable(manifestEntry?.acceptsMc ?? const <String>[]),
  );
}

/// Aggregates Modrinth + CurseForge "missing on a requested platform"
/// outcomes into a single [Map] keyed by slug. Used by the caller to
/// produce one [ValidationError] per resolve, not one per entry.
///
/// `mrNotFoundSlugs` is the set of Modrinth slugs that returned no
/// versions. `cfResolution` carries the per-slug CurseForge failures.
/// The aggregation walks the merged manifest's effective-source set
/// per entry: a slug fails when ANY of its requested eligible sources
/// is missing.
String? formatCrossPlatformMissingError({
  required ModsYaml manifest,
  required Set<String> mrNotFoundSlugs,
  required CfResolution cfResolution,
}) {
  final cfNotFoundBySlug = {for (final f in cfResolution.notFound) f.slug: f};
  final lines = <String>[];

  for (final section in Section.values) {
    final entries = manifest.sectionEntries(section);
    for (final mapEntry in entries.entries) {
      final slug = mapEntry.key;
      final entry = mapEntry.value;
      if (entry.source is! ModrinthEntrySource) continue;
      final effective = effectiveSources(manifest, entry, section);
      final missing = <String>[];
      if (effective.contains(SourceKind.modrinth) &&
          mrNotFoundSlugs.contains(slug)) {
        missing.add('Modrinth');
      }
      if (effective.contains(SourceKind.curseforge) &&
          cfNotFoundBySlug.containsKey(slug)) {
        final cf = cfNotFoundBySlug[slug]!;
        missing.add('CurseForge (${cf.reason}, queried "${cf.slugUsed}")');
      }
      if (missing.isNotEmpty) {
        lines.add('  $slug: not found on ${missing.join(', ')}');
      }
    }
  }

  if (lines.isEmpty) return null;
  return [
    'The following entries are missing on one or more requested platforms:',
    ...lines,
    'Resolution options:',
    '  - If the slug differs across platforms, add `modrinth:` / '
        '`curseforge:` peer slug overrides',
    '  - If the entry only exists on one platform, restrict via '
        '`sources: [modrinth]` or `sources: [curseforge]`',
    '  - Run `gitrinth migrate <target>` to mark the entry not-found in '
        'the manifest if you intentionally moved off a platform',
  ].join('\n');
}

/// Writes a `version.json` next to each resolved Modrinth artifact in
/// the cache, capturing the full Modrinth `Version` payload — its
/// `dependencies` array (consumed by `upgrade --unlock-transitive`) and
/// its `files` array (consumed by `cache repair` to verify and refetch
/// corrupt artifacts). Best effort: a write failure logs a warn but
/// doesn't abort the resolve, because the artifact download is the
/// user-visible contract.
void persistVersionMetadata(
  ResolutionResult resolution,
  GitrinthCache cache,
  Console console,
  String Function(ResolvedEntry) hostFor,
) {
  for (final r in resolution.entries) {
    final pid = r.version.projectId;
    final vid = r.version.id;
    if (pid.isEmpty || vid.isEmpty) continue;
    final path = cache.modrinthVersionMetadataPath(
      host: hostFor(r),
      projectId: pid,
      versionId: vid,
    );
    try {
      Directory(p.dirname(path)).createSync(recursive: true);
      File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(r.version.toMap()),
      );
    } on Object catch (e) {
      console.warn(
        'cache: failed to persist version metadata for ${r.slug} '
        '(${r.version.versionNumber}): $e',
      );
    }
  }
}

String filenameFromUrl(String url) {
  final uri = Uri.parse(url);
  if (uri.pathSegments.isEmpty) return 'artifact.jar';
  return uri.pathSegments.last;
}
