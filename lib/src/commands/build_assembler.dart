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
        'invalid --env value: $envFlag (expected client, server, or both)',
      );
  }
}

bool shouldIncludeEntry(Section section, LockedEntry entry, BuildEnv env) {
  if (section == Section.shaders) {
    return env == BuildEnv.client;
  }
  switch (entry.env) {
    case Environment.both:
      return true;
    case Environment.client:
      return env == BuildEnv.client;
    case Environment.server:
      return env == BuildEnv.server;
  }
}

String outputSubdirFor(Section section) => switch (section) {
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
      if (file.sha512 == null) {
        throw ValidationError(
          'lockfile entry "${entry.slug}" has a url source with no sha512; '
          're-run `gitrinth get` to repopulate.',
        );
      }
      return cache.urlPath(sha512: file.sha512!, filename: file.name);
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
