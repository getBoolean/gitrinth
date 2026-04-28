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

/// Returns true when an entry should be included in the `files[]` /
/// overrides of a pack targeting [target]. `combined` keeps everything;
/// `client` drops server-only entries (server marked as required/optional
/// while client is unsupported) and `server` drops client-only entries.
bool _includeForTarget(LockedEntry entry, PackTarget target) {
  switch (target) {
    case PackTarget.combined:
      return entry.client.includes || entry.server.includes;
    case PackTarget.client:
      return entry.client.includes;
    case PackTarget.server:
      return entry.server.includes;
  }
}

/// `LockedFileEntry`-typed analogue of [_includeForTarget]. Same
/// vocabulary, different parameter type — `files:` entries don't
/// share the [LockedEntry] hierarchy.
bool _includeForFileTarget(LockedFileEntry entry, PackTarget target) {
  switch (target) {
    case PackTarget.combined:
      return entry.client.includes || entry.server.includes;
    case PackTarget.client:
      return entry.client.includes;
    case PackTarget.server:
      return entry.server.includes;
  }
}

/// One file to copy into the `overrides/` tree of the produced `.mrpack`.
/// Generated for any non-modrinth source (url/path), since the mrpack
/// `files[]` list can only carry Modrinth CDN URLs.
class OverridePlan {
  /// Identifier surfaced in user-facing warnings. For mod/pack entries
  /// this is the Modrinth slug; for `files:` entries it's the
  /// destination path (the natural identifier in the manifest).
  final String slug;

  /// Manifest section the entry came from, or `null` for `files:`
  /// entries which live outside the [Section] taxonomy. Callers that
  /// care about section (the `--publishable` warning text, the
  /// mod-overrides counter) treat `null` as "not a mod section".
  final Section? section;

  /// Source kind, lowercase: `url`, `path`, or `file`. Surfaced in
  /// user messages so the permissions warning can name what to seek
  /// permission for. `file` entries (loose configs from the `files:`
  /// section) never need Modrinth permission and never trip the
  /// `--publishable` rejection.
  final String sourceKind;

  /// Absolute filesystem path to the source bytes (cached artifact for
  /// `url:`, resolved disk path for `path:` and `files:`).
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
  // Loader version is required by mrpack's `dependencies` block —
  // unless the pack has no mod runtime (vanilla), in which case the
  // mod-loader entry is omitted entirely.
  final modsLoaderVersion = lock.loader.modsLoaderVersion;
  if (lock.loader.hasModRuntime &&
      (modsLoaderVersion == 'stable' ||
          modsLoaderVersion == 'latest' ||
          modsLoaderVersion == null)) {
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
    final subdir = mrpackSubdirFor(section);
    for (final entry in lock.sectionFor(section).values) {
      if (entry.sourceKind != LockedSourceKind.modrinth) continue;
      if (!_includeForTarget(entry, target)) continue;
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
      // hasModRuntime + concrete modsLoaderVersion is enforced above; the
      // null branch is unreachable for non-vanilla packs, but the
      // collection-if also lets the loader entry drop cleanly when
      // the pack is vanilla.
      if (lock.loader.hasModRuntime && modsLoaderVersion != null)
        mrpackLoaderKey(lock.loader.mods): modsLoaderVersion,
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
  final sha512 = file.sha512;
  if (sha512 == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" is missing sha512. Re-run '
      '`gitrinth get` to repopulate.',
    );
  }
  final sha1 = file.sha1;
  if (sha1 == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" is missing sha1. Re-run '
      '`gitrinth get` to repopulate (sha1 was added in a recent '
      'gitrinth version).',
    );
  }
  final size = file.size;
  if (size == null) {
    throw ValidationError(
      'lockfile entry "${entry.slug}" is missing file size. Re-run '
      '`gitrinth get` to repopulate.',
    );
  }
  final downloadUrl = file.url ?? _canonicalModrinthUrl(entry, file);
  return MrpackFile(
    path: '$subdir/${file.name}',
    hashes: {'sha1': sha1, 'sha512': sha512},
    env: mrpackEnvFor(entry.client, entry.server),
    downloads: [downloadUrl],
    fileSize: size,
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
/// We route by per-side install state: both sides installed → `overrides/`,
/// client-only → `client-overrides/`, server-only → `server-overrides/`.
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
    final subdir = mrpackSubdirFor(section);
    for (final entry in lock.sectionFor(section).values) {
      if (entry.sourceKind == LockedSourceKind.modrinth) continue;
      if (!_includeForTarget(entry, target)) continue;
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
          zipPath: p.posix.join(
            _overridesRootFor(entry.client, entry.server),
            subdir,
            destName,
          ),
        ),
      );
      if (section == Section.mods) hasModOverrides = true;
    }
  }

  // `files:` entries: loose configs/scripts that route through the same
  // overrides tree but live outside the [Section] taxonomy. Their
  // destination key already carries the full sub-path
  // (e.g. `config/sodium-options.json`), so there is no `subdir` to
  // join — only the per-side overrides root prefix. Loose configs are
  // explicitly permitted by Modrinth's policy (only mod jars under
  // `mods/` need permission), so `files:` entries never set
  // `hasModOverrides` and never trip `--publishable`.
  for (final entry in lock.files.values) {
    if (!_includeForFileTarget(entry, target)) continue;
    // Re-assert destination-path safety here as defense-in-depth: the
    // schema/parser already reject `..` and absolute keys, but a
    // malicious or stale lock could still reach this point.
    if (entry.destination.isEmpty ||
        entry.destination.startsWith('/') ||
        entry.destination.startsWith(r'\') ||
        entry.destination.contains(r'\')) {
      throw ValidationError(
        'files: entry "${entry.destination}" has an unsafe destination '
        'path; refusing to include in the .mrpack archive.',
      );
    }
    for (final seg in p.posix.split(entry.destination)) {
      if (seg == '..' || seg == '.' || seg.isEmpty) {
        throw ValidationError(
          'files: entry "${entry.destination}" contains a `..`/`.` '
          'segment; refusing to include in the .mrpack archive.',
        );
      }
    }
    final sourcePath = p.isAbsolute(entry.sourcePath)
        ? entry.sourcePath
        : p.normalize(p.join(projectDir, entry.sourcePath));
    entries.add(
      OverridePlan(
        slug: entry.destination,
        section: null,
        sourceKind: 'file',
        sourcePath: sourcePath,
        zipPath: p.posix.join(
          _overridesRootFor(entry.client, entry.server),
          entry.destination,
        ),
      ),
    );
  }

  return OverridesPlan(entries: entries, hasModOverrides: hasModOverrides);
}

String _overridesRootFor(SideEnv client, SideEnv server) {
  if (client.includes && server.includes) return 'overrides';
  if (client.includes) return 'client-overrides';
  return 'server-overrides';
}
