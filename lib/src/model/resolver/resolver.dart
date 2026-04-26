import '../../cli/exceptions.dart';
import '../manifest/mods_lock.dart';
import '../manifest/mods_yaml.dart';
import 'constraint.dart';
import 'pubgrub.dart';
import 'result.dart';

/// Resolves the merged [manifest] into a [ResolutionResult] using the supplied
/// version-listing callback. Pure: no service/ imports.
///
/// [existingLock] (if any) is used as a soft pin: any locked version that is
/// still satisfied by its entry's constraint stays pinned.
///
/// [resolveSlugForProjectId] is given the chance to resolve transitive
/// dependencies' Modrinth project IDs back to slugs. If a transitive dep
/// cannot be resolved to a slug (returns null), it is skipped — it will not
/// participate in conflict resolution.
class Resolver {
  final ListVersions listVersions;
  final ResolveSlug resolveSlugForProjectId;

  Resolver({required this.listVersions, required this.resolveSlugForProjectId});

  Future<ResolutionResult> resolve(
    ModsYaml manifest, {
    ModsLock? existingLock,
  }) async {
    final roots = <RootConstraint>[];
    final entryBySection = <String, Section>{};
    final entryBySlug = <String, ModEntry>{};

    for (final section in Section.values) {
      final entries = manifest.sectionEntries(section);
      entries.forEach((slug, entry) {
        if (entry.source is! ModrinthEntrySource) {
          // url:/path: sources don't take part in resolution.
          return;
        }
        if (isAnyGitrinthMarker(entry.constraintRaw)) {
          // Skipped: a `gitrinth:` marker (`not-found` or
          // `disabled-by-conflict`) takes the entry out of resolution
          // until the user re-runs `migrate` / `upgrade --major-versions`.
          return;
        }
        // Permissive default: an entry with no explicit channel accepts
        // every Modrinth `version_type`. Users narrow to `release`/`beta`
        // only when they want a stricter stability floor.
        final effectiveChannel = entry.channel ?? Channel.alpha;
        roots.add(
          RootConstraint(
            slug: slug,
            constraint: parseConstraint(entry.constraintRaw),
            channel: effectiveChannel,
            isUserDeclared: true,
          ),
        );
        entryBySection[slug] = section;
        entryBySlug[slug] = entry;
      });
    }

    if (roots.isEmpty) return const ResolutionResult([]);

    final pins = <LockSuggestion>[];
    if (existingLock != null) {
      for (final section in Section.values) {
        existingLock.sectionFor(section).forEach((slug, locked) {
          final v = locked.version;
          if (v != null) pins.add(LockSuggestion(slug, v));
        });
      }
    }

    final solver = PubGrubSolver(
      listVersions: listVersions,
      resolveSlugForProjectId: resolveSlugForProjectId,
      lockSuggestions: pins,
    );
    final result = await solver.solve(roots);

    final entries = <ResolvedEntry>[];
    final sortedSlugs = result.decisions.keys.toList()..sort();
    for (final slug in sortedSlugs) {
      final v = result.decisions[slug]!;
      final file = v.primaryFile;
      if (file == null) {
        throw ValidationError(
          'Resolved $slug version ${v.versionNumber} has no downloadable file.',
        );
      }
      final section = entryBySection[slug] ?? Section.mods;
      final declared = entryBySlug[slug];
      final defaults = defaultSidesFor(section);
      final client = declared?.client ?? defaults.client;
      final server = declared?.server ?? defaults.server;
      final dependency = (result.auto[slug] ?? true)
          ? LockedDependencyKind.transitive
          : LockedDependencyKind.direct;
      entries.add(
        ResolvedEntry(
          slug: slug,
          section: section,
          client: client,
          server: server,
          dependency: dependency,
          version: v,
          file: file,
        ),
      );
    }
    return ResolutionResult(entries);
  }
}
