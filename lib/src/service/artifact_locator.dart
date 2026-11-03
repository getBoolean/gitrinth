import 'package:path/path.dart' as p;
import '../cli/exceptions.dart';
import '../model/manifest/mods_lock.dart';
import 'cache.dart';

String resolveSourcePath(
  GitrinthCache cache,
  LockedEntry entry, {
  required String projectDir,
  required String modrinthHost,
}) => ArtifactLocator(
  cache: cache,
  projectDir: projectDir,
  defaultModrinthHost: modrinthHost,
).preferred(entry);

/// Cache and project locations shared by fetch, build, and loose overrides.
/// A missing locked host means the global source default, never a pack host.
final class ArtifactLocator {
  final GitrinthCache cache;
  final String projectDir;
  final String defaultModrinthHost;
  const ArtifactLocator({
    required this.cache,
    required this.projectDir,
    required this.defaultModrinthHost,
  });
  String preferred(LockedEntry entry) {
    switch (entry.kind) {
      case LockedEntryKind.resolved:
        final mr = entry.modrinth;
        if (mr != null) {
          return modrinth(mr);
        }
        final cf = entry.curseforge;
        if (cf != null) {
          return curseforge(cf);
        }
        throw ValidationError(
          'lockfile entry "${entry.slug}" has no source block to fetch.',
        );
      case LockedEntryKind.url:
        final file = entry.urlFile;
        if (file == null) {
          throw ValidationError(
            'lockfile entry "${entry.slug}" is missing url source fields.',
          );
        }
        return url(entry.slug, file);
      case LockedEntryKind.path:
        final raw = entry.path;
        if (raw == null) {
          throw ValidationError(
            'lockfile entry "${entry.slug}" is missing path source fields.',
          );
        }
        return path(raw);
    }
  }

  String modrinth(LockedModrinthSource source) => cache.modrinthPath(
    host: source.host ?? defaultModrinthHost,
    projectId: source.projectId,
    versionId: source.versionId,
    filename: source.file.name,
  );
  String curseforge(LockedCurseforgeSource source) => cache.curseforgePath(
    projectId: source.projectId,
    fileId: source.fileId,
    filename: source.file.name,
  );
  String url(String slug, LockedFile file) => file.sha512 == null
      ? cache.unverifiedUrlPath(slug, file.name)
      : cache.urlPath(sha512: file.sha512!, filename: file.name);
  String path(String raw) =>
      p.isAbsolute(raw) ? raw : p.normalize(p.join(projectDir, raw));
}
