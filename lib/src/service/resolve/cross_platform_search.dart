import 'dart:convert';

import '../../commands/version_picker.dart';
import '../../model/curseforge/cf_constants.dart';
import '../../model/curseforge/cf_mod.dart';
import '../../model/manifest/mods_yaml.dart';
import '../../model/manifest/source_eligibility.dart';
import '../../model/modrinth/project.dart';
import '../../model/modrinth/version.dart' as mr;
import '../../model/resolver/constraint.dart';
import '../../model/resolver/version_selection.dart';
import '../console.dart';
import '../curseforge/curseforge_api.dart';
import '../curseforge/curseforge_filters.dart';
import '../modrinth/modrinth_api.dart';
import '../modrinth/modrinth_api_source.dart';
import '../source_identity.dart';
import 'curseforge_resolver.dart';

/// Session-scoped search caches retain host and all compatibility filters.
/// Only a unique project with an identical SHA1 can be selected automatically.
class CrossPlatformSearch {
  final ModsYaml manifest;
  final ModrinthApiSource mrFactory;
  final CurseForgeApi cfApi;
  final Console console;
  final bool disabled;
  final Set<LocalEntryKey> modrinthSearchSlugs = {};
  final Map<String, Future<List<Mod>>> _cfQueries = {};
  final Map<LocalEntryKey, String> diagnostics = {};

  CrossPlatformSearch({
    required this.manifest,
    required this.mrFactory,
    required this.cfApi,
    required this.console,
    this.disabled = false,
  });

  bool enabled(ModEntry entry, Section section) =>
      !disabled &&
      !entry.noCrossPlatformSearch &&
      effectiveSources(manifest, entry, section).length == 2 &&
      !(section == Section.mods && manifest.loader.mods == ModLoader.vanilla);

  Future<CfResolvedEntry?> findCurseforge({
    required String slug,
    required Section section,
    required ModEntry entry,
    required List<mr.Version> anchors,
    int? excludeProject,
  }) async {
    if (!enabled(entry, section) || anchors.isEmpty) return null;
    final query = entry.curseforgeSlug ?? slug;
    final versions = {manifest.mcVersion, ...entry.acceptsMc}.toList();
    final key = jsonEncode([
      query,
      section.name,
      manifest.loader.toMap(),
      versions,
    ]);
    final projects = await _cfQueries.putIfAbsent(
      key,
      () async => (await cfApi.searchMods(
        gameId: kCurseForgeGameIdMinecraft,
        classId: section.cfClassId,
        searchFilter: query,
        pageSize: 20,
      )).data,
    );
    final candidates = <_Candidate<CfResolvedEntry>>[];
    final anchorHashes = _mrHashes(anchors, entry.hashScanDepth ?? 10);
    Project? anchorProject;
    final anchorAuthors = <String>[];
    final host = manifest.effectiveModrinthHost(
      entry,
      mrFactory.defaultBaseUrl,
    );
    try {
      anchorProject = await mrFactory
          .forHost(host)
          .getProject(anchors.first.projectId);
    } on Object {
      /* Hash evidence does not require project metadata. */
    }
    try {
      final members =
          (await mrFactory
                  .forHost(host)
                  .getProjectMembers(anchors.first.projectId))
              .data;
      if (members is List) {
        for (final member in members) {
          if (member is Map && member['user'] is Map) {
            final name = member['user']['username'];
            if (name is String) anchorAuthors.add(name);
          }
        }
      }
    } on Object {
      /* Ranking remains useful without optional authors. */
    }
    for (final project in projects) {
      if (project.id == excludeProject ||
          project.classId != section.cfClassId) {
        continue;
      }
      final files = await listCompatibleFiles(
        api: cfApi,
        projectId: project.id,
        section: section,
        modLoader: section == Section.mods ? manifest.loader.mods : null,
        pluginLoader: manifest.loader.plugins,
        gameVersions: versions,
        channel: entry.channel ?? Channel.alpha,
        diagnoseUnavailable: false,
      );
      if (files.isEmpty) continue;
      final matches = files
          .take((entry.hashScanDepth ?? 10) + 1)
          .where((f) => f.sha1Hash != null && anchorHashes.contains(f.sha1Hash))
          .toList();
      candidates.add(
        _Candidate(
          value: CfResolvedEntry(
            slug: slug,
            section: section,
            project: project,
            file: matches.isEmpty ? files.first : matches.first,
            candidates: files,
            discoveredViaSearch: true,
          ),
          hashMatch: matches.isNotEmpty,
          title: project.name,
          slug: project.slug,
          authors: project.authors
              .map((a) => a['name']?.toString() ?? '')
              .toList(),
          categories: project.categories
              .map((c) => c['name']?.toString() ?? '')
              .toList(),
          version: files.first.displayName,
        ),
      );
    }
    final selected = _select(
      LocalEntryKey(section, slug),
      'CurseForge',
      candidates,
      anchorProject?.title ?? slug,
      anchorAuthors,
      anchorProject?.categories ?? const [],
    );
    if (selected != null) {
      _notice(slug, 'CurseForge', selected.project.slug, 'curseforge');
    }
    return selected;
  }

  Future<List<mr.Version>?> findModrinth({
    required String slug,
    required Section section,
    required ModEntry entry,
    required CfResolvedEntry anchor,
    String? excludeProject,
  }) async {
    if (!enabled(entry, section)) return null;
    final apiHost = manifest.effectiveModrinthHost(
      entry,
      mrFactory.defaultBaseUrl,
    );
    final api = mrFactory.forHost(apiHost);
    final query = entry.modrinthSlug ?? slug;
    final versions = {manifest.mcVersion, ...entry.acceptsMc}.toList();
    final loaders = filterLoadersForSection(manifest.loader, section);
    final type = switch (section) {
      Section.mods => 'mod',
      Section.resourcePacks => 'resourcepack',
      Section.shaders => 'shader',
      Section.dataPacks => 'datapack',
      Section.plugins => 'plugin',
    };
    final facets = jsonEncode([
      [
        'project_type:$type',
        if (section == Section.dataPacks || section == Section.plugins)
          'project_type:mod',
      ],
      [for (final v in versions) 'versions:$v'],
      if (loaders != null) [for (final l in loaders) 'categories:$l'],
    ]);
    final response = await api.searchProjects(query: query, facets: facets);
    final data = response.data;
    final hits = data is Map && data['hits'] is List
        ? data['hits'] as List
        : [];
    final anchorHashes = anchor.candidates
        .take((entry.hashScanDepth ?? 10) + 1)
        .map((f) => f.sha1Hash)
        .whereType<String>()
        .toSet();
    final candidates = <_Candidate<List<mr.Version>>>[];
    for (final raw in hits) {
      if (raw is! Map ||
          raw['project_id'] is! String ||
          raw['project_id'] == excludeProject) {
        continue;
      }
      final legacyMod =
          raw['project_type'] == 'mod' &&
          (section == Section.dataPacks || section == Section.plugins);
      if (raw['project_type'] != type && !legacyMod) continue;
      final list = await api.listVersions(
        raw['project_id'] as String,
        loadersJson: loaders == null ? null : encodeFilterArray(loaders),
        gameVersionsJson: encodeFilterArray(versions),
      );
      final compatible = list
          .where(
            (v) =>
                v.primaryFile != null &&
                v.gameVersions.any(versions.contains) &&
                (loaders == null || v.loaders.any(loaders.contains)),
          )
          .toList();
      // Respect the manifest constraint and channel before considering a hash.
      final eligible = eligibleModrinthVersions(compatible, entry);
      if (eligible.isEmpty) continue;
      final matches = eligible.take((entry.hashScanDepth ?? 10) + 1).where((v) {
        final hash = v.primaryFile?.hashes['sha1']?.toLowerCase();
        return hash != null && anchorHashes.contains(hash);
      }).toList();
      candidates.add(
        _Candidate(
          value: matches,
          hashMatch: matches.isNotEmpty,
          title: raw['title']?.toString() ?? '',
          slug: raw['slug']?.toString() ?? '',
          authors: [raw['author']?.toString() ?? ''],
          categories: (raw['categories'] as List? ?? [])
              .map((v) => v.toString())
              .toList(),
          version: eligible.first.versionNumber,
        ),
      );
    }
    final selected = _select(
      LocalEntryKey(section, slug),
      'Modrinth',
      candidates,
      anchor.project.name,
      anchor.project.authors.map((a) => a['name']?.toString() ?? '').toList(),
      anchor.project.categories
          .map((c) => c['name']?.toString() ?? '')
          .toList(),
    );
    if (selected != null) {
      modrinthSearchSlugs.add(LocalEntryKey(section, slug));
      final project = candidates.firstWhere(
        (c) => identical(c.value, selected),
      );
      _notice(slug, 'Modrinth', project.slug, 'modrinth');
    }
    return selected;
  }

  Set<String> _mrHashes(List<mr.Version> versions, int depth) => versions
      .take(depth + 1)
      .map((v) => v.primaryFile?.hashes['sha1']?.toLowerCase())
      .whereType<String>()
      .toSet();

  T? _select<T>(
    LocalEntryKey node,
    String platform,
    List<_Candidate<T>> candidates,
    String title,
    List<String> authors,
    List<String> categories,
  ) {
    candidates.sort((a, b) {
      final hash = (b.hashMatch ? 1 : 0).compareTo(a.hashMatch ? 1 : 0);
      if (hash != 0) return hash;
      final name = _similarity(
        b.title,
        title,
      ).compareTo(_similarity(a.title, title));
      if (name != 0) return name;
      final author = _overlap(
        b.authors,
        authors,
      ).compareTo(_overlap(a.authors, authors));
      if (author != 0) return author;
      final category = _overlap(
        b.categories,
        categories,
      ).compareTo(_overlap(a.categories, categories));
      return category != 0 ? category : a.slug.compareTo(b.slug);
    });
    final matches = candidates.where((c) => c.hashMatch).toList();
    if (matches.length == 1) return matches.single.value;
    final reason = matches.length > 1
        ? 'found ambiguous hash matches'
        : 'found no unique hash match';
    final details = candidates
        .take(5)
        .map((c) {
          final authors = c.authors.where((a) => a.isNotEmpty).join(', ');
          return '  - ${c.title} (${c.slug}), author: $authors, version: ${c.version}';
        })
        .join('\n');
    final message =
        '$platform search $reason. '
        '${candidates.isEmpty ? "No candidates." : "Candidates:\n$details"}';
    diagnostics.update(
      node,
      (previous) => '$previous\n$message',
      ifAbsent: () => message,
    );
    return null;
  }

  void _notice(
    String slug,
    String platform,
    String peer,
    String field,
  ) => console.message(
    '$slug: resolved on $platform via search as \'$peer\' (SHA1 match). '
    'Consider adding `$field: $peer` to mods.yaml to skip search on future runs.',
  );
}

/// The hash window contains only versions admissible for this manifest entry.
List<mr.Version> eligibleModrinthVersions(
  List<mr.Version> versions,
  ModEntry? entry,
) {
  final constraint = parseConstraint(entry?.constraintRaw);
  final channel = entry?.channel ?? Channel.alpha;
  return versions
      .where((v) => pickHighestMatching([v], constraint, channel) != null)
      .toList()
    ..sort(
      (a, b) => compareModrinthSelectionOrder(
        a,
        parseModrinthVersionBestEffort(a.versionNumber),
        b,
        parseModrinthVersionBestEffort(b.versionNumber),
      ),
    );
}

class _Candidate<T> {
  final T value;
  final bool hashMatch;
  final String title, slug, version;
  final List<String> authors, categories;
  const _Candidate({
    required this.value,
    required this.hashMatch,
    required this.title,
    required this.slug,
    required this.version,
    required this.authors,
    required this.categories,
  });
}

Set<String> _words(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((s) => s.isNotEmpty)
    .toSet();
double _similarity(String a, String b) {
  final left = _words(a), right = _words(b);
  final union = left.union(right);
  return union.isEmpty ? 0 : left.intersection(right).length / union.length;
}

int _overlap(List<String> a, List<String> b) => a
    .map((v) => v.toLowerCase())
    .toSet()
    .intersection(b.map((v) => v.toLowerCase()).toSet())
    .where((v) => v.isNotEmpty)
    .length;
