import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/mrpack_index.dart';
import '../service/cache.dart';
import 'build_assembler.dart';

/// Which side of a modpack a single `.mrpack` artifact targets.
///
/// `client` and `server` packs strip out files irrelevant to that side
/// (server-only mods don't ship in the client pack and vice versa).
/// `combined` produces the older single-artifact behavior — every file
/// in one zip, partitioned at install time by the per-file `env` map.
enum PackTarget { client, server, combined }

/// Returns true when an entry with [env] should be included in the
/// `files[]` / overrides of a pack targeting [target]. `combined` keeps
/// everything; `client` and `server` drop the opposite side's
/// dedicated entries but always keep `Environment.both`.
bool _includeForTarget(Environment env, PackTarget target) {
  switch (target) {
    case PackTarget.combined:
      return true;
    case PackTarget.client:
      return env != Environment.server;
    case PackTarget.server:
      return env != Environment.client;
  }
}

/// One file to copy into the `overrides/` tree of the produced `.mrpack`.
/// Generated for any non-modrinth source (url/path), since the mrpack
/// `files[]` list can only carry Modrinth CDN URLs.
class OverridePlan {
  final String slug;
  final Section section;

  /// Source kind, lowercase: `url` or `path`. Surfaced in user messages
  /// so the permissions warning can name what to seek permission for.
  final String sourceKind;

  /// Absolute filesystem path to the source bytes (cached artifact for
  /// `url:`, resolved disk path for `path:`).
  final String sourcePath;

  /// Path inside the zip, e.g. `overrides/mods/local-mod.jar`.
  final String zipPath;

  const OverridePlan({
    required this.slug,
    required this.section,
    required this.sourceKind,
    required this.sourcePath,
    required this.zipPath,
  });
}

/// Result of [collectOverrides]: the planned overrides plus a flag
/// indicating whether any of them are mod-section entries (used by the
/// `pack` command to decide whether to print the permissions warning
/// and to gate `--publishable`).
class OverridesPlan {
  final List<OverridePlan> entries;
  final bool hasModOverrides;

  const OverridesPlan({required this.entries, required this.hasModOverrides});
}

/// Builds the `modrinth.index.json` payload from a resolved [lock].
///
/// Only modrinth-source entries land in `files[]`; url/path entries are
/// routed to [collectOverrides] and packed loose under `overrides/`.
///
/// When [publishable] is true and any url/path entry exists in
/// [Section.mods], throws [ValidationError] listing every offending
/// slug. Other sections (resource packs, data packs, shaders) are
/// allowed under `--publishable` because Modrinth's permission policy
/// targets executable code only.
MrpackIndex buildIndex({
  required ModsYaml yaml,
  required ModsLock lock,
  required PackTarget target,
  required bool publishable,
}) {
  // Loader version is required by the format. Phase 1 stores it in
  // ModsLock.loader.modsVersion (defaults to "stable" for legacy locks
  // never re-resolved).
  final loaderVersion = lock.loader.modsVersion;
  if (loaderVersion == 'stable' || loaderVersion == 'latest') {
    throw const ValidationError(
      'mods.lock has no concrete loader version (still on `:stable` / '
      '`:latest`). Re-run `gitrinth get` to resolve and lock it before '
      'packing.',
    );
  }

  if (publishable) {
    // --publishable is global, not per-target: even a server-only mod
    // is published via the same Modrinth pipeline as the client pack.
    final offenders = <String>[];
    for (final entry in lock.mods.values) {
      if (entry.sourceKind != LockedSourceKind.modrinth) {
        offenders.add('${entry.slug} (${entry.sourceKind.name})');
      }
    }
    if (offenders.isNotEmpty) {
      offenders.sort();
      throw ValidationError(
        '--publishable refused: the following mods use a non-Modrinth '
        'source and cannot be referenced by a publishable .mrpack:\n'
        '${offenders.map((o) => '  - $o').join('\n')}\n'
        'Re-run without --publishable to bundle them as loose files '
        'under overrides/, or remove them from mods.yaml.',
      );
    }
  }

  final files = <MrpackFile>[];
  for (final section in Section.values) {
    final subdir = outputSubdirFor(section);
    for (final entry in lock.sectionFor(section).values) {
      if (entry.sourceKind != LockedSourceKind.modrinth) continue;
      if (!_includeForTarget(entry.env, target)) continue;
      files.add(_modrinthFileFor(entry, subdir));
    }
  }

  return MrpackIndex(
    versionId: yaml.version,
    name: yaml.name,
    summary: yaml.description,
    files: files,
    dependencies: {
      'minecraft': lock.mcVersion,
      mrpackLoaderKey(lock.loader.mods): loaderVersion,
    },
  );
}

MrpackFile _modrinthFileFor(LockedEntry entry, String subdir) {
  final file = entry.file;
  if (file == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" is a modrinth source but has no '
      '`file` block. Re-run `gitrinth get` to repopulate.',
    );
  }
  if (file.sha512 == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" is missing sha512. Re-run '
      '`gitrinth get` to repopulate.',
    );
  }
  if (file.sha1 == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" is missing sha1. Re-run '
      '`gitrinth get` to repopulate (sha1 was added in a recent '
      'gitrinth version).',
    );
  }
  if (file.size == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" is missing file size. Re-run '
      '`gitrinth get` to repopulate.',
    );
  }
  final downloadUrl = file.url ?? _canonicalModrinthUrl(entry, file);
  return MrpackFile(
    path: '$subdir/${file.name}',
    hashes: {'sha1': file.sha1!, 'sha512': file.sha512!},
    env: mrpackEnv(entry.env),
    downloads: [downloadUrl],
    fileSize: file.size!,
  );
}

String _canonicalModrinthUrl(LockedEntry entry, LockedFile file) {
  if (entry.projectId == null || entry.versionId == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" has no download url and is missing '
      'projectId/versionId; cannot synthesize a Modrinth CDN URL.',
    );
  }
  final encodedName = Uri.encodeComponent(file.name);
  return 'https://cdn.modrinth.com/data/${entry.projectId}/versions/'
      '${entry.versionId}/$encodedName';
}

/// Collects `overrides/<subdir>/<filename>` plans for every url/path
/// entry across all sections. The mrpack `files[]` list can't reference
/// these, so they're packed as loose bytes inside the archive.
///
/// Per the Modrinth pack spec there are three loose-files roots:
///   - `overrides/`         — installed on client + server
///   - `client-overrides/`  — installed on client only
///   - `server-overrides/`  — installed on server only
///
/// We route by [LockedEntry.env]: `both → overrides/`, `client →
/// client-overrides/`, `server → server-overrides/`. Shaders are parsed
/// with `forcedEnv: Environment.client`, so they naturally land in
/// `client-overrides/shaderpacks/` without a special case.
///
/// When [target] is `client`, server-only entries are dropped entirely
/// (a server-only override has nothing to do in a client pack); same
/// goes the other way. `combined` keeps all three roots.
OverridesPlan collectOverrides({
  required ModsLock lock,
  required GitrinthCache cache,
  required String projectDir,
  required PackTarget target,
}) {
  final entries = <OverridePlan>[];
  var hasModOverrides = false;

  for (final section in Section.values) {
    final subdir = outputSubdirFor(section);
    for (final entry in lock.sectionFor(section).values) {
      if (entry.sourceKind == LockedSourceKind.modrinth) continue;
      if (!_includeForTarget(entry.env, target)) continue;
      final sourcePath = resolveSourcePath(
        cache,
        entry,
        projectDir: projectDir,
      );
      final destName = destFilenameFor(entry);
      entries.add(
        OverridePlan(
          slug: entry.slug,
          section: section,
          sourceKind: entry.sourceKind.name,
          sourcePath: sourcePath,
          zipPath: p.posix.join(_overridesRootFor(entry.env), subdir, destName),
        ),
      );
      if (section == Section.mods) hasModOverrides = true;
    }
  }

  return OverridesPlan(entries: entries, hasModOverrides: hasModOverrides);
}

String _overridesRootFor(Environment env) {
  switch (env) {
    case Environment.both:
      return 'overrides';
    case Environment.client:
      return 'client-overrides';
    case Environment.server:
      return 'server-overrides';
  }
}
