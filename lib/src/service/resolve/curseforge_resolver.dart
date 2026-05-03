import '../../cli/exceptions.dart';
import '../../model/curseforge/cf_mod.dart';
import '../../model/curseforge/cf_mod_file.dart';
import '../../model/manifest/mods_yaml.dart';
import '../../model/manifest/source_eligibility.dart';
import '../console.dart';
import '../curseforge/curseforge_api.dart';
import '../curseforge/curseforge_filters.dart';

/// One CF entry that successfully resolved. The lock builder uses
/// these to populate per-entry [LockedCurseforgeSource] blocks.
///
/// [candidates] is the full newest-first list of compatible files
/// returned by [listCompatibleFiles] for this entry. The hash scan
/// step needs more than just the picked [file] when scanning older
/// pairs for a SHA1 match.
class CfResolvedEntry {
  final String slug;
  final Section section;
  final Mod project;
  final ModFile file;
  final List<ModFile> candidates;
  const CfResolvedEntry({
    required this.slug,
    required this.section,
    required this.project,
    required this.file,
    required this.candidates,
  });
}

/// One CF entry that failed to resolve. The aggregator turns these
/// into a single [ValidationError] after collecting both Modrinth and
/// CurseForge failures across the manifest.
class CfNotFound {
  final String slug;
  final Section section;

  /// Slug used to query CurseForge — entry's `curseforge:` peer slug
  /// override or the section-map key.
  final String slugUsed;

  /// `'slug-not-found'` (CF returned no project) or
  /// `'no-compatible-files'` (project found but no file matched the
  /// loader/MC/channel filter).
  final String reason;

  const CfNotFound({
    required this.slug,
    required this.section,
    required this.slugUsed,
    required this.reason,
  });
}

/// Aggregate result of a CurseForge resolution pass: per-entry
/// resolved blocks and per-entry not-found markers.
class CfResolution {
  final Map<String, CfResolvedEntry> resolved;
  final List<CfNotFound> notFound;
  const CfResolution({this.resolved = const {}, this.notFound = const []});

  /// Empty resolution — used when the CurseForge resolver is bypassed
  /// (offline mode, no entries request CurseForge, etc.).
  static const empty = CfResolution();
}

/// Walks the merged manifest and resolves every CurseForge-eligible
/// entry against [api]. Returns a [CfResolution] aggregating the
/// per-entry outcomes; never throws (resolution failures are aggregated
/// into [CfNotFound] markers and surfaced by the caller as a single
/// [ValidationError]).
///
/// Eligibility per entry follows [effectiveSources] — entries excluded
/// from CurseForge by `sources:` / matrix-ineligibility / pack-default
/// are silently skipped. Vanilla `mods:` entries are short-circuited
/// before any HTTP call (their `cfModLoaderType` would throw).
///
/// Inputs are kept boundary-pure: the manifest is the only spec, [api]
/// is the only HTTP surface, [console] receives best-effort warnings
/// when a CF lookup raises an unexpected error mid-walk.
Future<CfResolution> resolveCurseforgeEntries({
  required ModsYaml manifest,
  required CurseForgeApi api,
  required Console console,
}) async {
  final resolved = <String, CfResolvedEntry>{};
  final notFound = <CfNotFound>[];
  final mcVersions = <String>{manifest.mcVersion};

  for (final section in Section.values) {
    final entries = manifest.sectionEntries(section);
    for (final mapEntry in entries.entries) {
      final slug = mapEntry.key;
      final entry = mapEntry.value;
      // url:/path: sources never enter CF resolution.
      if (entry.source is! ModrinthEntrySource) continue;
      // Honor entry- and pack-level source restrictions before any
      // network call. Section/loader matrix-ineligibility silently
      // drops CF here; the `sources: curseforge` explicit-error path is
      // already enforced by the parser.
      final effective = effectiveSources(manifest, entry, section);
      if (!effective.contains(SourceKind.curseforge)) continue;
      // Vanilla packs have no mod-loader on the wire — CF would throw
      // a `StateError` from `cfModLoaderType`. Section.mods + vanilla
      // is incoherent with CurseForge anyway; short-circuit.
      if (section == Section.mods &&
          manifest.loader.mods == ModLoader.vanilla) {
        continue;
      }

      final slugUsed = entry.curseforgeSlug ?? slug;
      final gameVersions = <String>{...mcVersions, ...entry.acceptsMc}.toList();
      final channel = entry.channel ?? Channel.alpha;

      Mod? project;
      // Numeric `curseforge: 32274` short-form: skip the slug search
      // and resolve directly via getMod.
      final asInt = int.tryParse(slugUsed);
      try {
        if (asInt != null) {
          final envelope = await api.getMod(asInt);
          project = envelope.data;
        } else {
          project = await findModBySlug(api, slug: slugUsed, section: section);
        }
      } on Object catch (e) {
        console.warn(
          'curseforge: lookup for "$slug" failed: $e — '
          'treating as not found.',
        );
        notFound.add(
          CfNotFound(
            slug: slug,
            section: section,
            slugUsed: slugUsed,
            reason: 'slug-not-found',
          ),
        );
        continue;
      }
      if (project == null) {
        notFound.add(
          CfNotFound(
            slug: slug,
            section: section,
            slugUsed: slugUsed,
            reason: 'slug-not-found',
          ),
        );
        continue;
      }

      List<ModFile> files;
      try {
        files = await listCompatibleFiles(
          api: api,
          projectId: project.id,
          section: section,
          modLoader: section == Section.plugins ? null : manifest.loader.mods,
          pluginLoader: manifest.loader.plugins,
          gameVersions: gameVersions,
          channel: channel,
        );
      } on Object catch (e) {
        console.warn(
          'curseforge: listFiles for "$slug" (project ${project.id}) '
          'failed: $e — treating as no compatible files.',
        );
        notFound.add(
          CfNotFound(
            slug: slug,
            section: section,
            slugUsed: slugUsed,
            reason: 'no-compatible-files',
          ),
        );
        continue;
      }

      if (files.isEmpty) {
        notFound.add(
          CfNotFound(
            slug: slug,
            section: section,
            slugUsed: slugUsed,
            reason: 'no-compatible-files',
          ),
        );
        continue;
      }

      // CF version-constraint filtering is intentionally not applied
      // in Part 4 — CF version strings are semver-loose. The newest
      // candidate (per `listCompatibleFiles` sort order) is picked.
      resolved[slug] = CfResolvedEntry(
        slug: slug,
        section: section,
        project: project,
        file: files.first,
        candidates: files,
      );
    }
  }

  return CfResolution(resolved: resolved, notFound: notFound);
}
