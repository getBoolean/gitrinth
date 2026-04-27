import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import 'cache.dart';
import 'console.dart';
import 'downloader.dart';

/// One leaf artifact in the cache. `version.json` siblings are not
/// represented — they are metadata for the Modrinth jars beside them,
/// not user-visible cached content.
class CachedArtifact {
  /// Either `'modrinth'` or `'url'`.
  final String source;
  final String location;
  final String filename;
  final int size;

  /// Modrinth-only.
  final String? projectId;
  final String? versionId;

  /// URL-only. Equals the second-to-last path segment under `url/`.
  final String? sha512;

  const CachedArtifact({
    required this.source,
    required this.location,
    required this.filename,
    required this.size,
    this.projectId,
    this.versionId,
    this.sha512,
  });

  Map<String, Object?> toJson() {
    return {
      'source': source,
      if (projectId != null) 'projectId': projectId,
      if (versionId != null) 'versionId': versionId,
      if (sha512 != null) 'sha512': sha512,
      'filename': filename,
      'size': size,
      'location': location,
    };
  }
}

class RepairOutcome {
  final int verified;
  final int redownloaded;
  final int deleted;
  final List<String> skippedOrphans;
  final List<String> stillCorrupt;

  const RepairOutcome({
    required this.verified,
    required this.redownloaded,
    required this.deleted,
    required this.skippedOrphans,
    required this.stillCorrupt,
  });
}

class CacheInspector {
  final GitrinthCache cache;

  const CacheInspector(this.cache);

  /// Yields every cached artifact under `modrinth/` and `url/`. Skips
  /// `tmp/` and any `version.json` siblings. Returns an empty iterable
  /// when the cache root does not yet exist.
  Iterable<CachedArtifact> walkArtifacts() sync* {
    final modrinthDir = Directory(cache.modrinthRoot);
    if (modrinthDir.existsSync()) {
      for (final entity in modrinthDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final filename = p.basename(entity.path);
        if (filename == 'version.json') continue;
        final rel = p.relative(entity.path, from: cache.modrinthRoot);
        final parts = p.split(rel);
        if (parts.length < 3) continue;
        yield CachedArtifact(
          source: 'modrinth',
          location: entity.path,
          filename: filename,
          size: entity.lengthSync(),
          projectId: parts[0],
          versionId: parts[1],
        );
      }
    }

    final urlDir = Directory(cache.urlRoot);
    if (urlDir.existsSync()) {
      for (final entity in urlDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: cache.urlRoot);
        final parts = p.split(rel);
        // <prefix>/<sha512>/<filename>
        if (parts.length < 3) continue;
        yield CachedArtifact(
          source: 'url',
          location: entity.path,
          filename: parts.last,
          size: entity.lengthSync(),
          sha512: parts[parts.length - 2],
        );
      }
    }
  }

  /// Total bytes occupied by [artifacts].
  int totalSize(Iterable<CachedArtifact> artifacts) {
    var sum = 0;
    for (final a in artifacts) {
      sum += a.size;
    }
    return sum;
  }

  /// Wipes everything inside the cache root except the root directory
  /// itself. Returns bytes freed (best-effort sum from before deletion).
  Future<int> wipe() async {
    var freed = 0;
    final root = Directory(cache.root);
    if (!root.existsSync()) return 0;
    for (final entity in root.listSync()) {
      try {
        if (entity is File) {
          freed += entity.lengthSync();
          entity.deleteSync();
        } else if (entity is Directory) {
          freed += _dirSize(entity);
          entity.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // Best-effort: a concurrent download into tmp/ is fine to skip.
      }
    }
    return freed;
  }

  /// Re-verifies every cached file. Re-downloads corrupt Modrinth files
  /// using the URL+sha512 stored in the sibling `version.json`. Deletes
  /// corrupt url-sourced files (their original URL is not in the cache,
  /// so the next `gitrinth get` will re-fetch from `mods.lock`). Throws
  /// [CacheCorruptionError] if anything remains corrupt after the run.
  Future<RepairOutcome> repair(
    Downloader downloader, {
    required Console console,
  }) async {
    var verified = 0;
    var redownloaded = 0;
    var deleted = 0;
    final skippedOrphans = <String>[];
    final stillCorrupt = <String>[];

    for (final artifact in walkArtifacts()) {
      if (artifact.source == 'modrinth') {
        final outcome = await _repairModrinth(
          artifact,
          downloader,
          console: console,
        );
        switch (outcome) {
          case _ModrinthRepair.verified:
            verified++;
          case _ModrinthRepair.redownloaded:
            redownloaded++;
          case _ModrinthRepair.skippedOrphan:
            skippedOrphans.add(artifact.location);
          case _ModrinthRepair.stillCorrupt:
            stillCorrupt.add(artifact.location);
        }
      } else if (artifact.source == 'url') {
        final outcome = _repairUrl(artifact, console: console);
        switch (outcome) {
          case _UrlRepair.verified:
            verified++;
          case _UrlRepair.deleted:
            deleted++;
          case _UrlRepair.skipped:
            skippedOrphans.add(artifact.location);
        }
      }
    }

    final result = RepairOutcome(
      verified: verified,
      redownloaded: redownloaded,
      deleted: deleted,
      skippedOrphans: skippedOrphans,
      stillCorrupt: stillCorrupt,
    );

    if (stillCorrupt.isNotEmpty) {
      throw CacheCorruptionError(
        'cache repair could not recover ${stillCorrupt.length} '
        '${stillCorrupt.length == 1 ? "file" : "files"}:\n  '
        '${stillCorrupt.join("\n  ")}',
      );
    }

    return result;
  }

  Future<_ModrinthRepair> _repairModrinth(
    CachedArtifact artifact,
    Downloader downloader, {
    required Console console,
  }) async {
    final projectId = artifact.projectId;
    final versionId = artifact.versionId;
    if (projectId == null || versionId == null) {
      console.warn(
        'cache repair: ${artifact.location}: missing projectId/versionId; '
        'skipping (cannot resolve metadata path)',
      );
      return _ModrinthRepair.skippedOrphan;
    }
    final metaPath = cache.modrinthVersionMetadataPath(
      projectId: projectId,
      versionId: versionId,
    );
    final metaFile = File(metaPath);
    if (!metaFile.existsSync()) {
      console.warn(
        'cache repair: ${artifact.location}: no version.json sibling; '
        'skipping (cannot verify without metadata)',
      );
      return _ModrinthRepair.skippedOrphan;
    }

    final Map<String, Object?> meta;
    try {
      final raw = jsonDecode(metaFile.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('not a JSON object');
      }
      meta = raw;
    } on Object catch (e) {
      console.warn(
        'cache repair: $metaPath: unparseable version.json '
        '($e); skipping',
      );
      return _ModrinthRepair.skippedOrphan;
    }

    final files = meta['files'];
    if (files is! List) {
      console.warn(
        'cache repair: $metaPath: version.json has no files array; '
        'skipping (older cache schema, run `gitrinth get` to refresh)',
      );
      return _ModrinthRepair.skippedOrphan;
    }

    Map<String, Object?>? matchedFile;
    for (final f in files) {
      if (f is! Map) continue;
      if (f['filename'] == artifact.filename) {
        matchedFile = f.cast<String, Object?>();
        break;
      }
    }
    if (matchedFile == null) {
      console.warn(
        'cache repair: ${artifact.location}: no matching entry in '
        '$metaPath; skipping',
      );
      return _ModrinthRepair.skippedOrphan;
    }

    final url = matchedFile['url'];
    final hashes = matchedFile['hashes'];
    final expectedSha512 = (hashes is Map) ? hashes['sha512'] : null;
    if (url is! String || expectedSha512 is! String) {
      console.warn(
        'cache repair: ${artifact.location}: version.json entry missing '
        'url or sha512; skipping',
      );
      return _ModrinthRepair.skippedOrphan;
    }

    try {
      await GitrinthCache.verifyFileSha512(
        File(artifact.location),
        expectedSha512,
      );
      console.io('cache repair: ${artifact.location}: OK');
      return _ModrinthRepair.verified;
    } on UserError {
      console.io(
        'cache repair: ${artifact.location}: corrupt — re-downloading',
      );
    }

    try {
      await downloader.downloadTo(
        url: url,
        destinationPath: artifact.location,
        expectedSha512: expectedSha512,
      );
      return _ModrinthRepair.redownloaded;
    } on Object catch (e) {
      console.error(
        'cache repair: ${artifact.location}: re-download failed: $e',
      );
      return _ModrinthRepair.stillCorrupt;
    }
  }

  _UrlRepair _repairUrl(CachedArtifact artifact, {required Console console}) {
    final expected = artifact.sha512;
    if (expected == null) {
      console.warn(
        'cache repair: ${artifact.location}: URL artifact has no expected '
        'sha512; skipping (cannot verify, leaving file in place)',
      );
      return _UrlRepair.skipped;
    }
    try {
      final bytes = File(artifact.location).readAsBytesSync();
      GitrinthCache.verifySha512(bytes, expected);
      console.io('cache repair: ${artifact.location}: OK');
      return _UrlRepair.verified;
    } on UserError {
      console.io(
        'cache repair: ${artifact.location}: corrupt — deleting '
        '(next `gitrinth get` will refetch from mods.lock)',
      );
      try {
        File(artifact.location).deleteSync();
      } on FileSystemException catch (e) {
        console.warn('cache repair: failed to delete ${artifact.location}: $e');
      }
      _pruneEmptyParents(artifact.location, stopAt: cache.urlRoot);
      return _UrlRepair.deleted;
    }
  }

  void _pruneEmptyParents(String filePath, {required String stopAt}) {
    var dir = Directory(p.dirname(filePath));
    final stop = p.normalize(stopAt);
    while (p.normalize(dir.path) != stop && dir.existsSync()) {
      try {
        if (dir.listSync().isNotEmpty) return;
        dir.deleteSync();
      } on FileSystemException {
        return;
      }
      dir = dir.parent;
    }
  }

  int _dirSize(Directory dir) {
    var sum = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            sum += e.lengthSync();
          } on FileSystemException {
            // ignore vanished files
          }
        }
      }
    } on FileSystemException {
      // ignore
    }
    return sum;
  }
}

enum _ModrinthRepair { verified, redownloaded, skippedOrphan, stillCorrupt }

enum _UrlRepair { verified, deleted, skipped }
