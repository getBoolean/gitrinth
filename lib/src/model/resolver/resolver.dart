import '../../cli/exceptions.dart';
import '../manifest/mods_lock.dart';
import '../manifest/mods_yaml.dart';
import '../modrinth/version.dart' as modrinth;
import 'constraint.dart';
import 'modrinth_solver_adapter.dart';
import 'pubgrub.dart';
import 'result.dart';
import 'version_selection.dart';
import 'version_solver_types.dart';

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
///
/// [modrinthSlugs] (if non-null) restricts which user-declared slugs
/// participate in the Modrinth resolution roots. Slugs absent from the
/// set are skipped — they're handled by another platform's resolver
/// (today, only the CurseForge resolver). Transitive deps pulled in
/// by required-dep edges are unaffected. Pass null to include every
/// `ModrinthEntrySource` entry (legacy behavior).
///
/// The PubGrub solver underneath operates on a platform-agnostic
/// [SolverVersion] surface; [Resolver] only ever feeds it
/// [ModrinthSolverVersion] adapters today and unwraps decisions back
/// to Modrinth versions at the result boundary.
class Resolver {
  final ListVersions listVersions;
  final ResolveSlug resolveSlugForProjectId;
  final Future<String?> Function(String projectId, String parentSlug)?
  resolveDependencySlug;
  final Section Function(String slug)? sectionForSlug;
  final String Function(Section section, String slug)? nodeKeyFor;
  final String Function(String key)? localNameFor;
  final String Function(String message)? formatError;

  /// Selection direction passed through to [PubGrubSolver]. Defaults to
  /// [SolveType.get] so existing callers keep newest-first behavior.
  final SolveType solveType;

  Resolver({
    required this.listVersions,
    required this.resolveSlugForProjectId,
    this.resolveDependencySlug,
    this.sectionForSlug,
    this.nodeKeyFor,
    this.localNameFor,
    this.formatError,
    this.solveType = SolveType.get,
  });

  Future<ResolutionResult> resolve(
    ModsYaml manifest, {
    ModsLock? existingLock,
    Map<String, OverridePin> overridePins = const {},
    Set<String>? modrinthSlugs,
    Map<String, String> requiredVersionIds = const {},
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
        final key = nodeKeyFor?.call(section, slug) ?? slug;
        if (modrinthSlugs != null && !modrinthSlugs.contains(key)) {
          // Dispatch gate: the entry's effective sources exclude
          // Modrinth (e.g. `sources: [curseforge]` or pack-default
          // disable). Skip it here — the CurseForge resolver pass
          // handles it.
          return;
        }
        // The lock builder still needs to file an overridden slug
        // under the right section even though no RootConstraint is
        // built for it (the override pin pre-decides the version).
        entryBySection[key] = section;
        entryBySlug[key] = entry;
        if (overridePins.containsKey(key)) return;
        // Permissive default: an entry with no explicit channel accepts
        // every Modrinth `version_type`. Users narrow to `release`/`beta`
        // only when they want a stricter stability floor.
        final effectiveChannel = entry.channel ?? Channel.alpha;
        roots.add(
          RootConstraint(
            slug: key,
            constraint: parseConstraint(entry.constraintRaw),
            channel: effectiveChannel,
            isUserDeclared: true,
          ),
        );
      });
    }

    if (roots.isEmpty && overridePins.isEmpty) {
      return const ResolutionResult([]);
    }

    final pins = <LockSuggestion>[];
    if (existingLock != null) {
      for (final section in Section.values) {
        existingLock.sectionFor(section).forEach((slug, locked) {
          final v = locked.version;
          if (v != null) {
            pins.add(
              LockSuggestion(nodeKeyFor?.call(section, slug) ?? slug, v),
            );
          }
        });
      }
    }

    final solver = PubGrubSolver(
      listVersions: listVersions,
      resolveSlugForProjectId: resolveSlugForProjectId,
      resolveDependencySlug: resolveDependencySlug,
      selectionOrder: compareModrinthSolverOrder,
      lockSuggestions: pins,
      overridePins: overridePins.values.toList(),
      requiredVersionIds: requiredVersionIds,
      solveType: solveType,
    );
    final PubGrubResult result;
    try {
      result = await solver.solve(roots);
    } on UnsatisfiableGraphError catch (error) {
      throw UnsatisfiableGraphError(
        formatError?.call(error.message) ?? error.message,
        conflictingUserSlugs: {
          for (final key in error.conflictingUserSlugs)
            localNameFor?.call(key) ?? key,
        },
      );
    } on ValidationError catch (error) {
      throw ValidationError(formatError?.call(error.message) ?? error.message);
    }

    final entries = <ResolvedEntry>[];
    final sortedDecisions = result.decisions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final decision in sortedDecisions) {
      final slug = decision.key;
      final solverV = decision.value;
      // `Resolver` only ever feeds Modrinth adapters into the solver;
      // any other adapter type at this boundary is a bug in the caller.
      if (solverV is! ModrinthSolverVersion) {
        throw StateError(
          'Resolver expected ModrinthSolverVersion for $slug, got '
          '${solverV.runtimeType}',
        );
      }
      final v = solverV.raw;
      final file = v.primaryFile;
      if (file == null) {
        throw ValidationError(
          'Resolved $slug version ${v.versionNumber} has no downloadable file.',
        );
      }
      final section =
          entryBySection[slug] ?? sectionForSlug?.call(slug) ?? Section.mods;
      final declared = entryBySlug[slug];
      final defaults = defaultSidesFor(section);
      final client = declared?.client ?? defaults.client;
      final server = declared?.server ?? defaults.server;
      final dependency = (result.auto[slug] ?? true)
          ? LockedDependencyKind.transitive
          : LockedDependencyKind.direct;
      entries.add(
        ResolvedEntry(
          slug: localNameFor?.call(slug) ?? slug,
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

/// Type alias for callers that build a Modrinth-typed list-versions
/// callback and want to feed it into [Resolver]. Wraps each
/// [modrinth.Version] in a [ModrinthSolverVersion] before handing off
/// to PubGrub.
ListVersions modrinthListVersionsAdapter(
  Future<List<modrinth.Version>> Function(String slug) underlying,
) {
  return (slug) async {
    final mr = await underlying(slug);
    return mr.map(ModrinthSolverVersion.new).toList();
  };
}
