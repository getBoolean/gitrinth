import 'package:pub_semver/pub_semver.dart';

import '../../cli/exceptions.dart';
import '../manifest/mods_yaml.dart';
import '../modrinth/dependency.dart';
import '../modrinth/version.dart' as modrinth;
import 'constraint.dart';

typedef ListVersions = Future<List<modrinth.Version>> Function(String slug);
typedef ResolveSlug = Future<String?> Function(String projectId);

/// Pure-data root constraint (no Modrinth lookups required).
class RootConstraint {
  final String slug;
  final VersionConstraint constraint;
  final Channel channel;
  final bool isUserDeclared;
  const RootConstraint({
    required this.slug,
    required this.constraint,
    required this.isUserDeclared,
    this.channel = Channel.alpha,
  });
}

/// One pinned decision PubGrub will preserve unless contradicted.
class LockSuggestion {
  final String slug;
  final String versionNumber;
  const LockSuggestion(this.slug, this.versionNumber);
}

class PubGrubResult {
  /// slug -> chosen version
  final Map<String, modrinth.Version> decisions;

  /// slug -> true if this slug was added transitively (not in roots).
  final Map<String, bool> auto;

  const PubGrubResult({required this.decisions, required this.auto});
}

/// Minimal PubGrub-style resolver tuned for a single Minecraft loader+version
/// pair. We don't implement the full conflict-driven backtracking spec — we
/// implement a backtracking depth-first search with version-list caching that
/// preserves locked decisions where they remain compatible.
///
/// This is sufficient for `gitrinth get`'s MVP scope: typical modpack graphs
/// are small, mod versions usually carry no inter-mod ranges (`required`
/// dependencies are presence-only on Modrinth's side), and conflict cases
/// fall back to a clear error message.
class PubGrubSolver {
  final ListVersions listVersions;
  final ResolveSlug resolveSlugForProjectId;
  final List<LockSuggestion> lockSuggestions;
  final Map<String, List<modrinth.Version>> _versionCache = {};

  PubGrubSolver({
    required this.listVersions,
    required this.resolveSlugForProjectId,
    this.lockSuggestions = const [],
  });

  Future<PubGrubResult> solve(List<RootConstraint> roots) async {
    final state = _SolverState(
      lockSuggestions: {
        for (final s in lockSuggestions) s.slug: s.versionNumber,
      },
      userSlugs: roots
          .where((r) => r.isUserDeclared)
          .map((r) => r.slug)
          .toSet(),
    );
    for (final r in roots) {
      state.addConstraint(r.slug, r.constraint);
      state.addChannel(r.slug, r.channel);
    }
    if (await _solveStep(state)) {
      return PubGrubResult(
        decisions: Map.unmodifiable(state.decisions),
        auto: {
          for (final slug in state.decisions.keys)
            slug: !state.userSlugs.contains(slug),
        },
      );
    }
    throw ValidationError(state.failureExplanation());
  }

  Future<List<modrinth.Version>> _versionsFor(String slug) async {
    final cached = _versionCache[slug];
    if (cached != null) return cached;
    final list = await listVersions(slug);
    _versionCache[slug] = list;
    return list;
  }

  Future<bool> _solveStep(_SolverState state) async {
    // Pick a slug with constraints but no decision yet.
    final undecided = state.constraints.keys
        .where((s) => !state.decisions.containsKey(s))
        .toList();
    if (undecided.isEmpty) return true;

    // Prefer user-declared roots first, then alphabetical.
    undecided.sort((a, b) {
      final aUser = state.userSlugs.contains(a) ? 0 : 1;
      final bUser = state.userSlugs.contains(b) ? 0 : 1;
      if (aUser != bUser) return aUser - bUser;
      return a.compareTo(b);
    });
    final slug = undecided.first;
    final constraint = state.constraints[slug]!;
    final channel = state.channels[slug] ?? Channel.alpha;
    final allowed = allowedVersionTypes(channel);

    final allVersions = await _versionsFor(slug);
    if (allVersions.isEmpty) {
      state.recordConflict(
        slug,
        'no published versions match the loader/mc-version pair',
      );
      return false;
    }

    // Collect (parsed_version, modrinth_version) candidates.
    final candidates = <_Candidate>[];
    for (final v in allVersions) {
      final vt = v.versionType ?? 'release';
      if (!allowed.contains(vt)) continue;
      try {
        // Best-effort: truly-weird Modrinth version strings fall back
        // to `Version(0.0.0-<sanitised>)` so an exact-pin constraint on
        // the same raw string can still match. Pure-symbol versions
        // (empty after sanitisation) still throw and get skipped.
        final parsed = parseModrinthVersionBestEffort(v.versionNumber);
        if (constraint.allows(parsed)) {
          candidates.add(_Candidate(parsed, v));
        }
      } on FormatException {
        // Skip versions we cannot parse — recorded for diagnosis on failure.
        state.unparseableVersions
            .putIfAbsent(slug, () => <String>[])
            .add(v.versionNumber);
      }
    }
    if (candidates.isEmpty) {
      state.recordConflict(
        slug,
        'no version satisfies $constraint on channel ${channel.name} '
        '(saw ${allVersions.length} candidates).',
      );
      return false;
    }

    // Lock-suggestion preference: if the current lock pin satisfies, try it first.
    candidates.sort((a, b) => b.parsed.compareTo(a.parsed)); // desc
    final pin = state.lockSuggestions[slug];
    if (pin != null) {
      final pinIdx = candidates.indexWhere(
        (c) => c.modrinthVersion.versionNumber == pin,
      );
      if (pinIdx > 0) {
        final pinned = candidates.removeAt(pinIdx);
        candidates.insert(0, pinned);
      }
    }

    for (final cand in candidates) {
      // Snapshot state so we can backtrack.
      final snapshot = state.snapshot();
      state.decisions[slug] = cand.modrinthVersion;
      var ok = true;
      for (final dep in cand.modrinthVersion.dependencies) {
        if (dep.dependencyType == DependencyType.required) {
          final depProjectId = dep.projectId;
          if (depProjectId == null) continue;
          final depSlug = await resolveSlugForProjectId(depProjectId);
          if (depSlug == null) {
            // Cannot resolve transitive dependency to a slug — skip.
            // The user can pin it explicitly if desired.
            continue;
          }
          // Add an "any" constraint plus a version pin if dep.versionId given.
          state.addConstraint(depSlug, VersionConstraint.any);
          // Transitive deps inherit the permissive default (all
          // version_types admitted). A user who wants to pin the stability
          // floor of a transitive must declare it explicitly as a direct
          // entry.
          state.addChannel(depSlug, Channel.alpha);
          // versionId-pinned deps will be enforced when we recurse.
        } else if (dep.dependencyType == DependencyType.incompatible) {
          final depProjectId = dep.projectId;
          if (depProjectId == null) continue;
          final depSlug = await resolveSlugForProjectId(depProjectId);
          if (depSlug == null) continue;
          // Treat as: the slug must NOT be present. If it's already decided,
          // this branch fails immediately.
          if (state.decisions.containsKey(depSlug)) {
            ok = false;
            state.recordConflict(
              slug,
              'requires ${cand.modrinthVersion.versionNumber} which is incompatible with $depSlug',
            );
            break;
          }
          state.incompatibleSlugs.add(depSlug);
        }
      }
      if (!ok) {
        state.restore(snapshot);
        continue;
      }
      // Also check no decided slug is in the incompatible set.
      bool anyIncompat = false;
      for (final s in state.incompatibleSlugs) {
        if (state.decisions.containsKey(s)) {
          anyIncompat = true;
          break;
        }
      }
      if (anyIncompat) {
        state.restore(snapshot);
        continue;
      }

      if (await _solveStep(state)) return true;
      state.restore(snapshot);
    }
    state.recordConflict(slug, 'all candidate versions led to conflicts');
    return false;
  }
}

class _Candidate {
  final Version parsed;
  final modrinth.Version modrinthVersion;
  const _Candidate(this.parsed, this.modrinthVersion);
}

class _SolverState {
  final Map<String, VersionConstraint> constraints = {};
  final Map<String, Channel> channels = {};
  final Map<String, modrinth.Version> decisions = {};
  final Set<String> incompatibleSlugs = {};
  final Map<String, String> lockSuggestions;
  final Set<String> userSlugs;
  final Map<String, List<String>> unparseableVersions = {};
  final List<String> conflicts = [];

  _SolverState({required this.lockSuggestions, required this.userSlugs});

  void addConstraint(String slug, VersionConstraint c) {
    final existing = constraints[slug];
    if (existing == null) {
      constraints[slug] = c;
    } else {
      constraints[slug] = existing.intersect(c);
    }
  }

  /// Merge a channel declaration with any existing one for [slug], keeping
  /// the **more permissive** (lower-stability) floor. Conflicting declarations
  /// (e.g. top-level beta + entry-level release-after-override, or a second
  /// declaration via mods_overrides) widen rather than narrow — narrowing
  /// would surprise users whose intent when declaring a channel is "at least
  /// this stable."
  void addChannel(String slug, Channel c) {
    final existing = channels[slug];
    if (existing == null) {
      channels[slug] = c;
      return;
    }
    channels[slug] = _widerChannel(existing, c);
  }

  static Channel _widerChannel(Channel a, Channel b) {
    // alpha > beta > release in permissiveness.
    int rank(Channel ch) => switch (ch) {
      Channel.release => 0,
      Channel.beta => 1,
      Channel.alpha => 2,
    };
    return rank(a) >= rank(b) ? a : b;
  }

  void recordConflict(String slug, String why) {
    conflicts.add('  - $slug: $why');
  }

  String failureExplanation() {
    final buf = StringBuffer('Resolution failed.');
    if (conflicts.isNotEmpty) {
      buf.writeln('\nConflicts:');
      for (final c in conflicts.take(20)) {
        buf.writeln(c);
      }
    }
    if (unparseableVersions.isNotEmpty) {
      buf.writeln(
        '\nNote: some Modrinth version strings could not be parsed and were skipped:',
      );
      unparseableVersions.forEach((slug, versions) {
        buf.writeln('  - $slug: ${versions.join(', ')}');
      });
      buf.writeln('Pin an exact version in mods.yaml as a workaround.');
    }
    return buf.toString();
  }

  _Snapshot snapshot() {
    return _Snapshot(
      constraints: Map.of(constraints),
      channels: Map.of(channels),
      decisions: Map.of(decisions),
      incompatibleSlugs: Set.of(incompatibleSlugs),
    );
  }

  void restore(_Snapshot s) {
    constraints
      ..clear()
      ..addAll(s.constraints);
    channels
      ..clear()
      ..addAll(s.channels);
    decisions
      ..clear()
      ..addAll(s.decisions);
    incompatibleSlugs
      ..clear()
      ..addAll(s.incompatibleSlugs);
  }
}

class _Snapshot {
  final Map<String, VersionConstraint> constraints;
  final Map<String, Channel> channels;
  final Map<String, modrinth.Version> decisions;
  final Set<String> incompatibleSlugs;
  _Snapshot({
    required this.constraints,
    required this.channels,
    required this.decisions,
    required this.incompatibleSlugs,
  });
}
