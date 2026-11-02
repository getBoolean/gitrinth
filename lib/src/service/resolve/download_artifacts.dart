import 'dart:io';

import 'package:path/path.dart' as p;

import '../../cli/exceptions.dart';
import '../../model/manifest/mods_lock.dart';
import '../../model/manifest/mods_yaml.dart';
import '../cache.dart';
import '../console.dart';
import '../downloader.dart';
import '../manifest_io.dart';

/// Aggregate result of [downloadArtifacts]: per-section counts of
/// cache hits and downloads, plus any per-entry fetch errors that the
/// caller should surface as a single [ValidationError].
class DownloadArtifactsResult {
  final int downloaded;
  final int hits;
  final List<String> errors;
  const DownloadArtifactsResult({
    required this.downloaded,
    required this.hits,
    required this.errors,
  });
}

/// Walks every entry in [lock] and ensures its artifact(s) are present
/// in the cache. Per-platform source blocks fetch independently:
///   - `LockedEntryKind.resolved` with a Modrinth source → cached at
///     [GitrinthCache.modrinthPath] keyed by `(host, projectId,
///     versionId)`.
///   - `LockedEntryKind.resolved` with a CurseForge source → cached
///     at [GitrinthCache.curseforgePath] keyed by `(projectId, fileId)`.
///     When `cf.allowModDistribution == false` and `cf.file.url` is
///     null, the entry is skipped with an aggregated error (the user
///     has to download manually from the CurseForge project page).
///   - `LockedEntryKind.url` → cached at [GitrinthCache.urlPath] keyed
///     by sha512, or under [GitrinthCache.unverifiedUrlPath] when no
///     sha512 is recorded.
///   - `LockedEntryKind.path` → existence check against the project
///     directory (no fetch).
///
/// Pure plumbing: no policy, no manifest reads. The host for Modrinth
/// entries comes from [hostFor] (typically threaded through from the
/// effective-host chain in `resolveAndSync`).
Future<DownloadArtifactsResult> downloadArtifacts({
  required ModsLock lock,
  required GitrinthCache cache,
  required Downloader downloader,
  required Console console,
  required ManifestIo io,
  required String Function(Section section, String slug) hostFor,
}) async {
  var downloaded = 0;
  var hits = 0;
  final errors = <String>[];

  for (final section in Section.values) {
    for (final entry in lock.sectionFor(section).entries) {
      final locked = entry.value;
      try {
        switch (locked.kind) {
          case LockedEntryKind.resolved:
            final mr = locked.modrinth;
            if (mr != null) {
              final delta = await _fetchModrinth(
                cache: cache,
                downloader: downloader,
                console: console,
                slug: locked.slug,
                section: section,
                source: mr,
                hostFor: hostFor,
              );
              downloaded += delta.downloaded;
              hits += delta.hits;
            }
            final cf = locked.curseforge;
            if (cf != null) {
              final delta = _fetchCurseforgePrep(slug: locked.slug, source: cf);
              if (delta.error != null) {
                errors.add(delta.error!);
              } else if (delta.url != null) {
                final result = await _fetchCurseforge(
                  cache: cache,
                  downloader: downloader,
                  console: console,
                  slug: locked.slug,
                  source: cf,
                  url: delta.url!,
                );
                downloaded += result.downloaded;
                hits += result.hits;
              }
            }
          case LockedEntryKind.url:
            final delta = await _fetchUrl(
              cache: cache,
              downloader: downloader,
              slug: locked.slug,
              file: locked.urlFile,
            );
            downloaded += delta.downloaded;
            hits += delta.hits;
          case LockedEntryKind.path:
            _verifyPath(io: io, slug: locked.slug, raw: locked.path);
        }
      } on GitrinthException catch (e) {
        errors.add(e.message);
      }
    }
  }

  return DownloadArtifactsResult(
    downloaded: downloaded,
    hits: hits,
    errors: errors,
  );
}

class _Counts {
  final int downloaded;
  final int hits;
  const _Counts({this.downloaded = 0, this.hits = 0});
}

class _CfPrep {
  final String? url;
  final String? error;
  const _CfPrep({this.url, this.error});
}

Future<_Counts> _fetchModrinth({
  required GitrinthCache cache,
  required Downloader downloader,
  required Console console,
  required String slug,
  required Section section,
  required LockedModrinthSource source,
  required String Function(Section, String) hostFor,
}) async {
  final file = source.file;
  final url = file.url;
  if (url == null) return const _Counts();
  final dest = cache.modrinthPath(
    host: source.host ?? hostFor(section, slug),
    projectId: source.projectId,
    versionId: source.versionId,
    filename: file.name,
  );
  final existed = File(dest).existsSync();
  await downloader.downloadTo(
    url: url,
    destinationPath: dest,
    expectedSha512: file.sha512,
  );
  if (existed) {
    console.io('cache hit:  $slug -> $dest');
    return const _Counts(hits: 1);
  }
  console.io('downloaded: $slug -> $dest');
  return const _Counts(downloaded: 1);
}

_CfPrep _fetchCurseforgePrep({
  required String slug,
  required LockedCurseforgeSource source,
}) {
  final url = source.file.url;
  if (url == null) {
    if (!source.allowModDistribution) {
      return _CfPrep(
        error:
            '$slug: CurseForge does not allow third-party distribution '
            'for project ${source.projectId}; download manually from the '
            'CurseForge project page.',
      );
    }
    return const _CfPrep();
  }
  return _CfPrep(url: url);
}

Future<_Counts> _fetchCurseforge({
  required GitrinthCache cache,
  required Downloader downloader,
  required Console console,
  required String slug,
  required LockedCurseforgeSource source,
  required String url,
}) async {
  final file = source.file;
  final dest = cache.curseforgePath(
    projectId: source.projectId,
    fileId: source.fileId,
    filename: file.name,
  );
  final existed = File(dest).existsSync();
  await downloader.downloadTo(
    url: url,
    destinationPath: dest,
    expectedSha1: file.sha1,
  );
  if (existed) {
    console.io('cache hit:  $slug (cf) -> $dest');
    return const _Counts(hits: 1);
  }
  console.io('downloaded: $slug (cf) -> $dest');
  return const _Counts(downloaded: 1);
}

Future<_Counts> _fetchUrl({
  required GitrinthCache cache,
  required Downloader downloader,
  required String slug,
  required LockedFile? file,
}) async {
  if (file == null) return const _Counts();
  final url = file.url;
  if (url == null) return const _Counts();
  final sha512 = file.sha512;
  final dest = sha512 != null
      ? cache.urlPath(sha512: sha512, filename: file.name)
      : cache.unverifiedUrlPath(slug, file.name);
  final existed = File(dest).existsSync();
  await downloader.downloadTo(
    url: url,
    destinationPath: dest,
    expectedSha512: sha512,
  );
  if (existed) return const _Counts(hits: 1);
  return const _Counts(downloaded: 1);
}

void _verifyPath({
  required ManifestIo io,
  required String slug,
  required String? raw,
}) {
  if (raw == null) {
    throw FormatException(
      'lock entry "$slug" with kind=path has no path — mods.lock is '
      'malformed.',
    );
  }
  final resolved = p.isAbsolute(raw)
      ? raw
      : p.normalize(p.join(io.directory.path, raw));
  if (FileSystemEntity.typeSync(resolved) == FileSystemEntityType.notFound) {
    throw ValidationError(
      'path source for "$slug" points to a missing file: '
      '$raw (looked in $resolved)',
    );
  }
}
