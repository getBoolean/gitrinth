import 'package:pub_semver/pub_semver.dart';

import '../manifest/mods_yaml.dart';
import '../modrinth/dependency.dart';
import '../modrinth/version.dart' as modrinth;
import 'constraint.dart';
import 'version_selection.dart';
import 'version_solver_types.dart';

/// [SolverVersion] implementation that wraps a [modrinth.Version].
/// Eagerly computes [parsedVersion] via [parseModrinthVersionBestEffort]
/// and projects [dependencies] to required/incompatible edges only —
/// `optional` and `embedded` Modrinth deps are dropped here so the
/// solver's edge handling stays platform-agnostic.
class ModrinthSolverVersion implements SolverVersion {
  /// The wrapped Modrinth version. Exposed so the resolver boundary
  /// can downcast and unwrap when projecting back to [ResolvedEntry]s.
  final modrinth.Version raw;

  @override
  final Version parsedVersion;

  @override
  final Channel channel;

  @override
  final List<SolverDependency> dependencies;

  ModrinthSolverVersion(this.raw)
    : parsedVersion = _safeParse(raw.versionNumber),
      channel = _channelFor(raw.versionType),
      dependencies = _projectDependencies(raw.dependencies);

  @override
  String get id => raw.id;

  @override
  String get versionNumber => raw.versionNumber;

  static Version _safeParse(String raw) {
    try {
      return parseModrinthVersionBestEffort(raw);
    } on FormatException {
      // Fully-unparseable raws (pure-symbol after sanitization). Use a
      // unique placeholder so the solver can still iterate; constraint
      // matching will fall through to the candidate filter.
      return Version(0, 0, 0, pre: 'unparseable');
    }
  }

  static Channel _channelFor(String? versionType) {
    switch (versionType) {
      case 'release':
        return Channel.release;
      case 'beta':
        return Channel.beta;
      case 'alpha':
        return Channel.alpha;
      default:
        return Channel.release;
    }
  }

  static List<SolverDependency> _projectDependencies(List<Dependency> deps) {
    final out = <SolverDependency>[];
    for (final d in deps) {
      final t = switch (d.dependencyType) {
        DependencyType.required => SolverDependencyType.required,
        DependencyType.incompatible => SolverDependencyType.incompatible,
        DependencyType.optional || DependencyType.embedded => null,
      };
      if (t == null) continue;
      out.add(
        SolverDependency(
          targetProjectId: d.projectId,
          targetVersionId: d.versionId,
          type: t,
        ),
      );
    }
    return out;
  }
}

/// Selection-order comparator passed into [PubGrubSolver.selectionOrder].
/// Delegates to the existing Modrinth comparator for date_published →
/// parsed-semver ordering. Throws `StateError` if either argument
/// isn't a [ModrinthSolverVersion] — the resolver wires only Modrinth
/// adapters into this comparator today.
int compareModrinthSolverOrder(SolverVersion a, SolverVersion b) {
  if (a is! ModrinthSolverVersion || b is! ModrinthSolverVersion) {
    throw StateError(
      'compareModrinthSolverOrder requires ModrinthSolverVersion, '
      'got ${a.runtimeType} vs ${b.runtimeType}',
    );
  }
  return compareModrinthSelectionOrder(
    a.raw,
    a.parsedVersion,
    b.raw,
    b.parsedVersion,
  );
}
