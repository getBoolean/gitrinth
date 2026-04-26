part of 'resolve_and_sync.dart';

/// Builds the new `ModsLock` from the resolved Modrinth versions plus the
/// manifest's url:/path: entries (which never enter the resolver) and
/// `files:` entries (which are manifest-only).
ModsLock _buildLock(
  ModsYaml manifest,
  ResolutionResult resolution,
  String resolvedLoaderVersion,
) {
  final byKind = <Section, Map<String, LockedEntry>>{
    for (final s in Section.values) s: <String, LockedEntry>{},
  };
  for (final r in resolution.entries) {
    final entry = manifest.sectionEntries(r.section)[r.slug];
    byKind[r.section]![r.slug] = LockedEntry(
      slug: r.slug,
      sourceKind: LockedSourceKind.modrinth,
      version: r.version.versionNumber,
      projectId: r.version.projectId,
      versionId: r.version.id,
      file: LockedFile(
        name: r.file.filename,
        url: r.file.url,
        sha1: r.file.hashes['sha1'],
        sha512: r.file.sha512,
        size: r.file.size,
      ),
      client: r.client,
      server: r.server,
      dependency: r.dependency,
      gameVersions: List.unmodifiable(r.version.gameVersions),
      acceptsMc: List.unmodifiable(entry?.acceptsMc ?? const <String>[]),
    );
  }
  for (final section in Section.values) {
    final entries = manifest.sectionEntries(section);
    entries.forEach((slug, entry) {
      final src = entry.source;
      if (src is UrlEntrySource) {
        byKind[section]![slug] = LockedEntry(
          slug: slug,
          sourceKind: LockedSourceKind.url,
          file: LockedFile(name: _filenameFromUrl(src.url), url: src.url),
          client: entry.client,
          server: entry.server,
        );
      } else if (src is PathEntrySource) {
        byKind[section]![slug] = LockedEntry(
          slug: slug,
          sourceKind: LockedSourceKind.path,
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
    modsVersion: resolvedLoaderVersion,
    shaders: manifest.loader.shaders,
    plugins: manifest.loader.plugins,
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
    mods: byKind[Section.mods]!,
    resourcePacks: byKind[Section.resourcePacks]!,
    dataPacks: byKind[Section.dataPacks]!,
    shaders: byKind[Section.shaders]!,
    files: lockedFiles,
  );
}

/// Writes a `version.json` next to each resolved Modrinth artifact in
/// the cache, capturing the full Modrinth `Version` payload — its
/// `dependencies` array (consumed by `upgrade --unlock-transitive`) and
/// its `files` array (consumed by `cache repair` to verify and refetch
/// corrupt artifacts). Best effort: a write failure logs a warn but
/// doesn't abort the resolve, because the artifact download is the
/// user-visible contract.
void _persistVersionMetadata(
  ResolutionResult resolution,
  GitrinthCache cache,
  Console console,
) {
  for (final r in resolution.entries) {
    final pid = r.version.projectId;
    final vid = r.version.id;
    if (pid.isEmpty || vid.isEmpty) continue;
    final path = cache.modrinthVersionMetadataPath(
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

String _filenameFromUrl(String url) {
  final uri = Uri.parse(url);
  if (uri.pathSegments.isEmpty) return 'artifact.jar';
  return uri.pathSegments.last;
}
