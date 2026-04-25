import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/cache.dart';

enum BuildEnv { client, server }

String envDirName(BuildEnv env) => switch (env) {
  BuildEnv.client => 'client',
  BuildEnv.server => 'server',
};

List<BuildEnv> targetEnvironments(String? envFlag) {
  switch (envFlag) {
    case 'client':
      return const [BuildEnv.client];
    case 'server':
      return const [BuildEnv.server];
    case null:
    case 'both':
      return const [BuildEnv.client, BuildEnv.server];
    default:
      throw UsageError(
        'invalid environment "$envFlag" (expected client, server, or both)',
      );
  }
}

/// Returns the install state for [entry] on [env]'s side, or
/// [SideEnv.unsupported] if the entry isn't installed on that side.
SideEnv sideForBuildEnv(LockedEntry entry, BuildEnv env) =>
    entry.sideFor(env == BuildEnv.client);

/// Loose-file build subdir for [entry] in the given [section] and [env],
/// or null when the entry doesn't install on that side. Data and resource
/// packs route by per-side install state into the `global_packs/*` tree
/// the `globalpacks` mod loads from; mods and shaders keep their static
/// subdirs.
String? buildSubdirFor(Section section, BuildEnv env, LockedEntry entry) {
  final side = sideForBuildEnv(entry, env);
  if (side == SideEnv.unsupported) return null;
  final isOptional = side == SideEnv.optional;
  switch (section) {
    case Section.mods:
      return 'mods';
    case Section.shaders:
      return 'shaderpacks';
    case Section.dataPacks:
      return isOptional
          ? 'global_packs/optional_data'
          : 'global_packs/required_data';
    case Section.resourcePacks:
      return isOptional
          ? 'global_packs/optional_resources'
          : 'global_packs/required_resources';
  }
}

/// `.mrpack` `files[]` and `overrides/` paths. Independent of build env
/// and per-side install state — Modrinth pack consumers expect the
/// historical `datapacks/` and `resourcepacks/` subdirs.
String mrpackSubdirFor(Section section) => switch (section) {
  Section.mods => 'mods',
  Section.resourcePacks => 'resourcepacks',
  Section.dataPacks => 'datapacks',
  Section.shaders => 'shaderpacks',
};

String resolveSourcePath(
  GitrinthCache cache,
  LockedEntry entry, {
  required String projectDir,
}) {
  switch (entry.sourceKind) {
    case LockedSourceKind.modrinth:
      final file = entry.file;
      if (file == null || entry.projectId == null || entry.versionId == null) {
        throw ValidationError(
          'lockfile entry "${entry.slug}" is missing modrinth source fields.',
        );
      }
      return cache.modrinthPath(
        projectId: entry.projectId!,
        versionId: entry.versionId!,
        filename: file.name,
      );
    case LockedSourceKind.url:
      final file = entry.file;
      if (file == null) {
        throw ValidationError(
          'lockfile entry "${entry.slug}" is missing url source fields.',
        );
      }
      // When sha512 is known, the artifact lives at its sha-addressed
      // path; otherwise the downloader stashed it under `_unverified`
      // keyed by slug (same fallback resolve_and_sync uses). Mirroring
      // that here avoids forcing callers to re-run `get` just to
      // populate a hash they may never need.
      if (file.sha512 != null) {
        return cache.urlPath(sha512: file.sha512!, filename: file.name);
      }
      return p.join(cache.urlRoot, '_unverified', entry.slug, file.name);
    case LockedSourceKind.path:
      final raw = entry.path;
      if (raw == null) {
        throw ValidationError(
          'lockfile entry "${entry.slug}" is missing path source fields.',
        );
      }
      return p.isAbsolute(raw) ? raw : p.normalize(p.join(projectDir, raw));
  }
}

String destFilenameFor(LockedEntry entry) {
  final file = entry.file;
  if (file != null) return file.name;
  final path = entry.path;
  if (path != null) return p.basename(path);
  throw ValidationError(
    'lockfile entry "${entry.slug}" has no filename to derive.',
  );
}
