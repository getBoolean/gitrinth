import 'package:pub_semver/pub_semver.dart';

import '../manifest/mods_yaml.dart';
import '../modrinth/version.dart' as modrinth;
import 'constraint.dart';

/// Direction the resolver should pick candidates in. Mirrors dart pub's
/// `SolveType { get, upgrade, downgrade }`. `get` and `upgrade` both
/// pick the **newest** matching version per slug; `downgrade` picks
/// the **oldest**. The split exists so `gitrinth downgrade` reuses the
/// same plumbing as `get`/`upgrade` and to leave the door open for
/// future per-type behavior.
enum SolveType { get, upgrade, downgrade }

/// Picks the highest Modrinth version that satisfies [constraint] under
/// the stability floor implied by [channel]. Returns null when no
/// published version qualifies. When [solveType] is
/// [SolveType.downgrade], picks the **lowest** matching version
/// instead.
///
/// Mirrors the candidate selection PubGrub performs internally
/// ([compareModrinthSelectionOrder] sort over channel-eligible
/// candidates, take the head — or tail under downgrade). Extracted so
/// the override-promotion step in `resolve_and_sync` can pin a
/// `project_overrides:` entry to the same version PubGrub would pick
/// if the slug had been declared as a normal root.
modrinth.Version? pickHighestMatching(
  List<modrinth.Version> versions,
  VersionConstraint constraint,
  Channel channel, {
  SolveType solveType = SolveType.get,
}) {
  final allowed = allowedVersionTypes(channel);
  final candidates = <_Candidate>[];
  for (final v in versions) {
    final vt = v.versionType ?? 'release';
    if (!allowed.contains(vt)) continue;
    try {
      final parsed = parseModrinthVersionBestEffort(v.versionNumber);
      if (constraint.allows(parsed)) {
        candidates.add(_Candidate(parsed, v));
      }
    } on FormatException {
      // Skip versions we cannot parse — this mirrors PubGrub's
      // behavior. The override caller surfaces the empty-result
      // case with its own error.
      continue;
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort(
    (a, b) => compareModrinthSelectionOrder(
      a.modrinthVersion,
      a.parsed,
      b.modrinthVersion,
      b.parsed,
    ),
  );
  return solveType == SolveType.downgrade
      ? candidates.last.modrinthVersion
      : candidates.first.modrinthVersion;
}

class _Candidate {
  final Version parsed;
  final modrinth.Version modrinthVersion;
  const _Candidate(this.parsed, this.modrinthVersion);
}
