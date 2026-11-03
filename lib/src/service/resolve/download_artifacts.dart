import 'dart:io';

import '../../cli/exceptions.dart';
import '../../model/manifest/mods_lock.dart';
import '../../model/manifest/mods_yaml.dart';
import '../cache.dart';
import '../artifact_locator.dart';
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
/// entries uses the locked source host or [defaultModrinthHost].
Future<DownloadArtifactsResult> downloadArtifacts({
  required ModsLock lock,
  required GitrinthCache cache,
  required Downloader downloader,
  required Console console,
  required ManifestIo io,
  required String defaultModrinthHost,
}) async {
  final locator = ArtifactLocator(
    cache: cache,
    projectDir: io.directory.path,
    defaultModrinthHost: defaultModrinthHost,
  );
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
                downloader: downloader,
                console: console,
                slug: locked.slug,
                source: mr,
                locator: locator,
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
                  locator: locator,
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
              locator: locator,
              downloader: downloader,
              slug: locked.slug,
              file: locked.urlFile,
            );
            downloaded += delta.downloaded;
            hits += delta.hits;
          case LockedEntryKind.path:
            _verifyPath(locator: locator, slug: locked.slug, raw: locked.path);
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
  required Downloader downloader,
  required Console console,
  required String slug,
  required LockedModrinthSource source,
  required ArtifactLocator locator,
}) async {
  final file = source.file;
  final url = file.url;
  if (url == null) return const _Counts();
  final dest = locator.modrinth(source);
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
  required ArtifactLocator locator,
  required Downloader downloader,
  required Console console,
  required String slug,
  required LockedCurseforgeSource source,
  required String url,
}) async {
  final file = source.file;
  final dest = locator.curseforge(source);
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
  required ArtifactLocator locator,
  required Downloader downloader,
  required String slug,
  required LockedFile? file,
}) async {
  if (file == null) return const _Counts();
  final url = file.url;
  if (url == null) return const _Counts();
  final sha512 = file.sha512;
  final dest = locator.url(slug, file);
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
  required ArtifactLocator locator,
  required String slug,
  required String? raw,
}) {
  if (raw == null) {
    throw FormatException(
      'lock entry "$slug" with kind=path has no path — mods.lock is '
      'malformed.',
    );
  }
  final resolved = locator.path(raw);
  if (FileSystemEntity.typeSync(resolved) == FileSystemEntityType.notFound) {
    throw ValidationError(
      'path source for "$slug" points to a missing file: '
      '$raw (looked in $resolved)',
    );
  }
}
