import 'package:pub_semver/pub_semver.dart';

import '../manifest/mods_yaml.dart';

/// Platform-agnostic dependency-edge classification consumed by the
/// solver. Modrinth's `optional` / `embedded` are dropped at adapter
/// time — they have no effect on resolution.
enum SolverDependencyType { required, incompatible }

/// Platform-agnostic dependency edge. Adapter implementations populate
/// the relevant identifier field (`targetSlug` for direct slug pins,
/// `targetProjectId` for indirect lookups via
/// `resolveSlugForProjectId`). `targetVersionId` (Modrinth-style
/// floor hint) stays optional and may be null on platforms where
/// version-id pinning isn't expressible.
class SolverDependency {
  final String? targetSlug;
  final String? targetProjectId;
  final String? targetVersionId;
  final SolverDependencyType type;

  const SolverDependency({
    this.targetSlug,
    this.targetProjectId,
    this.targetVersionId,
    required this.type,
  });
}

/// Platform-agnostic version surface consumed by [PubGrubSolver].
/// One adapter implementation lives per platform — see
/// `modrinth_solver_adapter.dart` for the Modrinth wrapper.
abstract interface class SolverVersion {
  /// Stable per-platform version identifier (Modrinth `id`, CurseForge
  /// `fileId.toString()`). Used for `targetVersionId` cross-references
  /// and for platform-specific debugging.
  String get id;

  /// Raw version-number string as published by the platform. Used for
  /// lock-suggestion equality checks and failure messages — the solver
  /// does no parsing on it directly.
  String get versionNumber;

  /// Pre-parsed semver of [versionNumber]. Adapters compute this once
  /// (best-effort, falling back to `0.0.0-<sanitised>`) so the solver
  /// can match constraints without re-parsing.
  Version get parsedVersion;

  /// Stability channel (release/beta/alpha) used for the channel-floor
  /// filter inside the solver.
  Channel get channel;

  /// Edges to other slugs (required + incompatible only). Optional and
  /// embedded deps are dropped at adapter time.
  List<SolverDependency> get dependencies;
}
