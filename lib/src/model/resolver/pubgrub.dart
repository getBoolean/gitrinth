import 'package:pub_semver/pub_semver.dart';

import '../../cli/exceptions.dart';
import '../manifest/mods_yaml.dart';
import '../modrinth/dependency.dart';
import '../modrinth/version.dart' as modrinth;
import 'constraint.dart';
import 'version_selection.dart';

typedef ListVersions = Future<List<modrinth.Version>> Function(String slug);
typedef ResolveSlug = Future<String?> Function(String projectId);

/// Thrown when the solver can't satisfy the graph after exhausting every
/// candidate. Subclass of [ValidationError] so existing callers that catch
/// the parent type still work; new callers that want to disable the
/// conflicting entries (`gitrinth migrate`, `gitrinth upgrade --major-versions`)
/// downcast to read [conflictingUserSlugs] — the user-declared entries
/// implicated in any failure on the search path. Both endpoints of an
/// incompatible-deps pair land in this set, as does the user-controllable
/// ancestor of a deeper transitive failure.
class UnsatisfiableGraphError extends ValidationError {
  final Set<String> conflictingUserSlugs;
  UnsatisfiableGraphError(super.message, {required this.conflictingUserSlugs});
}

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

/// One sticky override decision passed to [PubGrubSolver]. Pre-seeds
/// `state.decisions` so the solver never lists, scores, or backtracks
/// past the chosen version.
///
/// Override pins are how `project_overrides:` declarations reach the
/// resolver. Their semantics differ from [LockSuggestion]: a lock pin
/// is a *preference* the solver may abandon if contradicted, an
/// override pin is a *guarantee* — constraints from other mods on an
/// overridden slug, and `incompatible:` edges that target an
/// overridden slug or originate from one, are silently dropped.
class OverridePin {
  final String slug;
  final modrinth.Version version;
  const OverridePin(this.slug, this.version);
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
  final List<OverridePin> overridePins;

  /// Selection direction — `get`/`upgrade` pick newest, `downgrade`
  /// picks oldest. `downgrade` also disables the lock-suggestion head
  /// promotion below: a downgrade is meant to ignore the existing pin.
  final SolveType solveType;

  final Map<String, List<modrinth.Version>> _versionCache = {};

  PubGrubSolver({
    required this.listVersions,
    required this.resolveSlugForProjectId,
    this.lockSuggestions = const [],
    this.overridePins = const [],
    this.solveType = SolveType.get,
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
    // Phase 1: seed sticky override decisions before any constraint
    // is added. The solver treats each pinned slug as already-decided
    // — _solveStep skips it (no entry in `constraints`), the
    // required-dep loop skips it, and the incompatible-dep loop drops
    // edges in either direction.
    for (final pin in overridePins) {
      state.overriddenSlugs.add(pin.slug);
      state.initialOverrideDecisions[pin.slug] = pin.version;
      state.decisions[pin.slug] = pin.version;
      // Treat the pinned version's own deps the same way the search
      // loop would for a chosen candidate, with two override-specific
      // bypasses:
      //   - skip required deps that target another overridden slug
      //   - drop ALL incompatible deps (the user takes responsibility
      //     for whatever incompatibilities the override mod declares)
      for (final dep in pin.version.dependencies) {
        if (dep.dependencyType == DependencyType.required) {
          final depProjectId = dep.projectId;
          if (depProjectId == null) continue;
          final depSlug = await resolveSlugForProjectId(depProjectId);
          if (depSlug == null) continue;
          if (state.overriddenSlugs.contains(depSlug)) continue;
          var depConstraint = VersionConstraint.any;
          final depVersionId = dep.versionId;
          if (depVersionId != null) {
            final depVersions = await _versionsFor(depSlug);
            modrinth.Version? pinned;
            for (final dv in depVersions) {
              if (dv.id == depVersionId) {
                pinned = dv;
                break;
              }
            }
            if (pinned != null) {
              try {
                final floor = parseModrinthVersion(pinned.versionNumber);
                depConstraint = VersionRange(min: floor, includeMin: true);
              } on FormatException {
                // Non-semver → fall back to `any`.
              }
            }
          }
          state.addConstraint(depSlug, depConstraint, parentSlug: pin.slug);
          state.addChannel(depSlug, Channel.alpha);
          state.recordIntroducer(depSlug, pin.slug, pin.version.versionNumber);
        }
        // DependencyType.incompatible deps from an override are
        // silently dropped — both endpoints. See spec case 6.
      }
    }
    for (final r in roots) {
      // Skip adding a root constraint for slugs the override pins
      // already decided. They have no candidate-search to drive.
      if (state.overriddenSlugs.contains(r.slug)) continue;
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
    final message = state.failureExplanation();
    final conflictingUserSlugs = _collectConflictingUserSlugs(state);
    if (conflictingUserSlugs.isEmpty) {
      // Defensive: every conflict path should reach at least one user
      // root. If extraction comes up empty (e.g. failure recorded
      // through an internal-only branch), fall back to the legacy
      // hard-fail signal so callers see the same exception they used to.
      throw ValidationError(message);
    }
    throw UnsatisfiableGraphError(
      message,
      conflictingUserSlugs: Set.unmodifiable(conflictingUserSlugs),
    );
  }

  /// User-declared slugs implicated in any failure on the search path.
  /// For each [_Failure], we add: (1) `slug` if it is itself a user root,
  /// (2) the outermost introducer (the user-declared ancestor) when the
  /// chain is non-empty, (3) the `counterpartSlug` of an incompatible-deps
  /// conflict, and (4) every user-root that contributed a constraint to
  /// the failed slug (so a version-pin conflict on a transitive cuts
  /// every pinning root). Together they ensure both endpoints of any
  /// conflict land in the disable set.
  Set<String> _collectConflictingUserSlugs(_SolverState state) {
    final out = <String>{};
    for (final f in state.specificFailures) {
      if (state.userSlugs.contains(f.slug)) {
        out.add(f.slug);
      }
      if (f.chain.isNotEmpty) {
        final root = f.chain.last.parentSlug;
        if (state.userSlugs.contains(root)) out.add(root);
      }
      final cp = f.counterpartSlug;
      if (cp != null && state.userSlugs.contains(cp)) out.add(cp);
      final parents = state.constraintParents[f.slug];
      if (parents != null) {
        for (final p in parents) {
          if (state.userSlugs.contains(p)) out.add(p);
        }
      }
    }
    // Override-pinned slugs are the user's deliberate choice — never
    // propose them for the auto-disable retry. If the only remaining
    // conflict participants are overridden, the throw site falls back
    // to plain ValidationError; the user has to edit the override.
    out.removeWhere(state.overriddenSlugs.contains);
    return out;
  }

  /// Walks the introducer chain from [slug] up to a user-declared root.
  /// When [slug] is itself a user root, returns it. When the chain
  /// dead-ends in a transitive (defensive — every transitive should
  /// trace back), returns the last reached node.
  String _userRootAncestorOf(String slug, _SolverState state) {
    if (state.userSlugs.contains(slug)) return slug;
    var current = slug;
    final visited = <String>{current};
    while (true) {
      final intro = state.introducers[current];
      if (intro == null) return current;
      if (!visited.add(intro.parentSlug)) return current;
      current = intro.parentSlug;
      if (state.userSlugs.contains(current)) return current;
    }
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
      state.recordSpecificFailure(
        slug,
        'no published version of $slug matches the configured '
        'loader/mc-version pair',
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
      state.recordSpecificFailure(
        slug,
        'no version of $slug matches $constraint on channel '
        '${channel.name} (saw ${allVersions.length} candidates)',
      );
      return false;
    }

    candidates.sort(
      (a, b) => compareModrinthSelectionOrder(
        a.modrinthVersion,
        a.parsed,
        b.modrinthVersion,
        b.parsed,
      ),
    );
    if (solveType == SolveType.downgrade) {
      // Downgrade reverses the candidate order so the oldest matching
      // version is tried first. Lock-pin promotion still runs below:
      // pins on slugs the user did NOT ask to downgrade (i.e. ones the
      // resolveAndSync layer left in `lockSuggestions`) should still be
      // honored. Slugs the user IS downgrading have their pins stripped
      // upstream via `freshSlugs`.
      final reversed = candidates.reversed.toList();
      candidates
        ..clear()
        ..addAll(reversed);
    }
    // Lock-suggestion preference: if the current lock pin satisfies, try it first.
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
      // The user-root ancestor of `slug` — used to attribute any
      // constraint this candidate's deps add on a transitive back to a
      // user-controllable disable target. Computed once per candidate
      // because every dep below shares the same ancestor.
      final ancestor = _userRootAncestorOf(slug, state);
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
          // Override-pinned slugs are decided up-front; constraints
          // from any other source on them are silently dropped (spec
          // cases 4 and 5).
          if (state.overriddenSlugs.contains(depSlug)) continue;
          // A `version_id` on the dep is a lower-bound hint: Modrinth
          // mods don't declare upper compatibility bounds, so two
          // parents pinning across majors should resolve to the higher
          // floor instead of conflicting.
          var depConstraint = VersionConstraint.any;
          final depVersionId = dep.versionId;
          if (depVersionId != null) {
            final depVersions = await _versionsFor(depSlug);
            modrinth.Version? pinned;
            for (final dv in depVersions) {
              if (dv.id == depVersionId) {
                pinned = dv;
                break;
              }
            }
            if (pinned != null) {
              try {
                final floor = parseModrinthVersion(pinned.versionNumber);
                depConstraint = VersionRange(min: floor, includeMin: true);
              } on FormatException {
                // Non-semver upstream version → fall back to `any`.
              }
            }
          }
          state.addConstraint(depSlug, depConstraint, parentSlug: ancestor);
          // Transitive deps inherit the permissive default (all
          // version_types admitted). A user who wants to pin the stability
          // floor of a transitive must declare it explicitly as a direct
          // entry.
          state.addChannel(depSlug, Channel.alpha);
          // Record who pulled this transitive in so failure messages
          // can narrate "every <slug> depends on <depSlug>" — backtracking
          // restores the previous introducer if this candidate is abandoned.
          state.recordIntroducer(
            depSlug,
            slug,
            cand.modrinthVersion.versionNumber,
          );
        } else if (dep.dependencyType == DependencyType.incompatible) {
          final depProjectId = dep.projectId;
          if (depProjectId == null) continue;
          final depSlug = await resolveSlugForProjectId(depProjectId);
          if (depSlug == null) continue;
          // Spec case 3: incompatible edges that target an override
          // slug are silently dropped. (Edges originating from an
          // override are already dropped at solve-start in the
          // pre-decision phase, so we only see edges from search-loop
          // candidates here.)
          if (state.overriddenSlugs.contains(depSlug)) continue;
          // Treat as: the slug must NOT be present. If it's already decided,
          // this branch fails immediately.
          if (state.decisions.containsKey(depSlug)) {
            ok = false;
            state.recordSpecificFailure(
              slug,
              '$slug ${cand.modrinthVersion.versionNumber} is '
              'incompatible with $depSlug, which is already in the modpack',
              counterpartSlug: depSlug,
            );
            break;
          }
          state.incompatibleSlugs.add(depSlug);
          state.incompatibleBy[depSlug] = slug;
        }
      }
      if (!ok) {
        state.restore(snapshot);
        continue;
      }
      // Also check no decided slug is in the incompatible set.
      String? incompatSlug;
      for (final s in state.incompatibleSlugs) {
        if (state.decisions.containsKey(s)) {
          incompatSlug = s;
          break;
        }
      }
      if (incompatSlug != null) {
        // Record both endpoints so the conflict-roots extraction can
        // name them in `UnsatisfiableGraphError.conflictingUserSlugs`.
        // Without this, the mutual-incompatibility scenario silently
        // backtracks past the conflict and the throw site has no
        // user-controllable slugs to report.
        final markedBy = state.incompatibleBy[incompatSlug];
        state.recordSpecificFailure(
          incompatSlug,
          markedBy == null
              ? '$incompatSlug is incompatible with another mod already in '
                    'the modpack'
              : '$incompatSlug and $markedBy declared each other '
                    'incompatible — they cannot coexist',
          counterpartSlug: markedBy,
        );
        state.restore(snapshot);
        continue;
      }

      if (await _solveStep(state)) return true;
      state.restore(snapshot);
    }
    // Don't record a cascade here — the deeper specific failure for a
    // child slug has already been captured via `recordSpecificFailure`,
    // and the dart-pub-style chain in `failureExplanation` will narrate
    // the parent → child relationship from the introducer trail. A
    // bookkeeping "all candidate versions led to conflicts" line at
    // every level only adds noise.
    return false;
  }
}

class _Candidate {
  final Version parsed;
  final modrinth.Version modrinthVersion;
  const _Candidate(this.parsed, this.modrinthVersion);
}

/// Records who introduced a transitive constraint on a slug. Used at
/// failure time to walk back from the failing leaf to the user-declared
/// root, producing a dart pub-style "Because X depends on Y..." chain.
class _Introducer {
  final String parentSlug;
  final String parentVersion;
  const _Introducer({required this.parentSlug, required this.parentVersion});
}

/// One specific resolver failure with the chain that led to it. Captured
/// the moment the failure is detected so the chain reflects the
/// then-current decision state — backtracking later won't change it.
class _Failure {
  final String slug;
  final String reason;
  final VersionConstraint slugConstraint;
  final Channel slugChannel;

  /// Innermost (slug's direct parent) → outermost (the user-declared
  /// root that pulled slug in). Empty when [slug] is itself a user root.
  final List<_Introducer> chain;

  /// The other endpoint of an incompatibility conflict, when the failure
  /// came from an `incompatible` dep encountering an already-decided slug.
  /// Both endpoints are user-controllable disable targets; we capture the
  /// counterpart at record time because backtracking will pop the
  /// already-decided slug out of `state.decisions` before the throw.
  final String? counterpartSlug;

  const _Failure({
    required this.slug,
    required this.reason,
    required this.slugConstraint,
    required this.slugChannel,
    required this.chain,
    this.counterpartSlug,
  });
}

class _SolverState {
  final Map<String, VersionConstraint> constraints = {};
  final Map<String, Channel> channels = {};
  final Map<String, modrinth.Version> decisions = {};
  final Set<String> incompatibleSlugs = {};

  /// Slugs decided at solve-start by an [OverridePin]. The solver
  /// never lists candidates for them, never adds constraints to them,
  /// and skips `incompatible:` edges that touch them in either
  /// direction. Backtracking does not erase override decisions —
  /// [restore] re-seats them from [initialOverrideDecisions].
  final Set<String> overriddenSlugs = {};

  /// Snapshot of override decisions taken at solve-start, used by
  /// [restore] to re-seat them after the search loop backtracks.
  /// Never mutated after `solve` populates it.
  final Map<String, modrinth.Version> initialOverrideDecisions = {};

  /// `incompatibleBy[depSlug] = parentSlug`: the slug whose dep loop
  /// added `depSlug` to [incompatibleSlugs]. Used at conflict-detection
  /// time to name both endpoints of an incompatibility.
  final Map<String, String> incompatibleBy = {};

  /// `constraintParents[depSlug] = {user-root, ...}`: every user-root
  /// that contributed any constraint on a child slug, captured at
  /// constraint-add time by walking up the introducer chain. Persists
  /// across backtracking — for the disable-set extraction to name every
  /// user-root that pinned a transitive at a conflicting version, we
  /// need the full set even after the search abandoned each branch.
  final Map<String, Set<String>> constraintParents = {};
  final Map<String, _Introducer> introducers = {};
  final Map<String, String> lockSuggestions;
  final Set<String> userSlugs;
  final Map<String, List<String>> unparseableVersions = {};

  /// Real-cause failures collected across the entire solve. Not part of
  /// snapshot/restore — failures persist past backtracking so we still
  /// have something to report when every branch ultimately fails.
  /// Deduplicated by `(slug, reason)` at format time.
  final List<_Failure> specificFailures = [];

  _SolverState({required this.lockSuggestions, required this.userSlugs});

  void addConstraint(String slug, VersionConstraint c, {String? parentSlug}) {
    final existing = constraints[slug];
    if (existing == null) {
      constraints[slug] = c;
    } else {
      constraints[slug] = existing.intersect(c);
    }
    if (parentSlug != null) {
      constraintParents.putIfAbsent(slug, () => <String>{}).add(parentSlug);
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

  /// Record that [parentSlug]@[parentVersion] introduced a constraint
  /// on [childSlug]. The most-recent introducer wins — chain walking
  /// follows whichever decision is currently live in the search tree,
  /// because snapshot/restore reverts entries added by an abandoned
  /// candidate.
  void recordIntroducer(
    String childSlug,
    String parentSlug,
    String parentVersion,
  ) {
    introducers[childSlug] = _Introducer(
      parentSlug: parentSlug,
      parentVersion: parentVersion,
    );
  }

  void recordSpecificFailure(
    String slug,
    String reason, {
    String? counterpartSlug,
  }) {
    specificFailures.add(
      _Failure(
        slug: slug,
        reason: reason,
        slugConstraint: constraints[slug] ?? VersionConstraint.any,
        slugChannel: channels[slug] ?? Channel.alpha,
        chain: _buildChain(slug),
        counterpartSlug: counterpartSlug,
      ),
    );
  }

  List<_Introducer> _buildChain(String slug) {
    final hops = <_Introducer>[];
    final visited = <String>{slug};
    var current = slug;
    while (true) {
      final intro = introducers[current];
      if (intro == null) break;
      hops.add(intro);
      if (!visited.add(intro.parentSlug)) break; // cycle guard
      current = intro.parentSlug;
    }
    return hops;
  }

  String failureExplanation() {
    // Dedupe (slug, reason) — the same leaf can be hit on multiple
    // backtrack paths and we only want one paragraph per real cause.
    final seen = <String>{};
    final unique = <_Failure>[];
    for (final f in specificFailures) {
      if (seen.add('${f.slug}::${f.reason}')) unique.add(f);
    }

    final buf = StringBuffer();
    if (unique.isEmpty) {
      // No specific failure recorded — fall back to a bare message.
      // Reachable only if `_solveStep` returns false for reasons we
      // don't currently surface (defensive).
      buf.writeln('Version solving failed.');
    } else {
      for (final f in unique) {
        buf.writeln(_formatFailure(f));
      }
      buf.writeln('Version solving failed.');
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
    return buf.toString().trimRight();
  }

  String _formatFailure(_Failure f) {
    final clauses = <String>[];
    if (f.chain.isEmpty) {
      // [f.slug] is itself a user-declared root.
      clauses.add(_dependsOnModpack(f.slug, f.slugConstraint));
    } else {
      // Outermost introducer is the user root; walk in narrative
      // order (root → ... → slug's direct parent → slug).
      final outermost = f.chain.last;
      final rootConstraint =
          constraints[outermost.parentSlug] ?? VersionConstraint.any;
      clauses.add(_dependsOnModpack(outermost.parentSlug, rootConstraint));
      // Intermediate hops: root → hop1 → hop2 → ... → slug.
      // Iterate from outermost to innermost, then add the leaf hop.
      for (var i = f.chain.length - 1; i >= 0; i--) {
        final hop = f.chain[i];
        final child = i == 0 ? f.slug : f.chain[i - 1].parentSlug;
        clauses.add('every ${hop.parentSlug} depends on $child');
      }
    }
    clauses.add(f.reason);
    return 'Because ${clauses.join(', ')}.';
  }

  String _dependsOnModpack(String slug, VersionConstraint c) {
    if (c.isAny) return 'the modpack depends on $slug';
    return 'the modpack depends on $slug ${_formatConstraint(c)}';
  }

  /// Compact, user-facing rendering of a [VersionConstraint]. The
  /// pub_semver `toString()` is good enough for ranges and carets;
  /// `SemverOnlyExactConstraint` already returns a bare version.
  String _formatConstraint(VersionConstraint c) {
    if (c.isAny) return 'any';
    return c.toString();
  }

  _Snapshot snapshot() {
    return _Snapshot(
      constraints: Map.of(constraints),
      channels: Map.of(channels),
      decisions: Map.of(decisions),
      incompatibleSlugs: Set.of(incompatibleSlugs),
      incompatibleBy: Map.of(incompatibleBy),
      introducers: Map.of(introducers),
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
    incompatibleBy
      ..clear()
      ..addAll(s.incompatibleBy);
    introducers
      ..clear()
      ..addAll(s.introducers);
    // Override decisions are sticky — re-seat them after every
    // backtracking restore so the search loop can never erase them.
    for (final entry in initialOverrideDecisions.entries) {
      decisions[entry.key] = entry.value;
    }
  }
}

class _Snapshot {
  final Map<String, VersionConstraint> constraints;
  final Map<String, Channel> channels;
  final Map<String, modrinth.Version> decisions;
  final Set<String> incompatibleSlugs;
  final Map<String, String> incompatibleBy;
  final Map<String, _Introducer> introducers;
  _Snapshot({
    required this.constraints,
    required this.channels,
    required this.decisions,
    required this.incompatibleSlugs,
    required this.incompatibleBy,
    required this.introducers,
  });
}
