import '../../model/curseforge/cf_mod_file.dart';
import '../../model/modrinth/version.dart' as modrinth;

/// Outcome of [scanForMatchingPair]. Sealed so callers must handle every
/// case at the switch boundary; the lock-builder differentiates between
/// a true SHA1 match, an accepted mismatch (locked at the newest pair),
/// and a depth-exhausted failure (which the caller turns into a
/// [ValidationError]).
sealed class HashOutcome {
  const HashOutcome();
}

/// SHA1s matched — either the newest pair or an older pair found via
/// the depth scan. The lock builder uses [modrinthVersion] +
/// [curseforgeFile] verbatim.
class HashMatched extends HashOutcome {
  final modrinth.Version modrinthVersion;
  final ModFile curseforgeFile;
  const HashMatched({
    required this.modrinthVersion,
    required this.curseforgeFile,
  });
}

/// SHA1s differed but the user opted in via `allow_hash_mismatch: true`.
/// Lock the newest pair anyway and emit a console warning. Carrier of
/// the same fields as [HashMatched] for caller convenience.
class HashAcceptedMismatch extends HashOutcome {
  final modrinth.Version modrinthVersion;
  final ModFile curseforgeFile;
  const HashAcceptedMismatch({
    required this.modrinthVersion,
    required this.curseforgeFile,
  });
}

/// Scan window exhausted with no SHA1 match and `allow_hash_mismatch`
/// not set. The caller throws a [ValidationError] naming the newest
/// pair and the depth examined.
class HashExhausted extends HashOutcome {
  final modrinth.Version newestModrinth;
  final ModFile newestCurseforge;
  final int depthExamined;
  const HashExhausted({
    required this.newestModrinth,
    required this.newestCurseforge,
    required this.depthExamined,
  });
}

/// Only one platform produced a candidate. There's nothing to compare;
/// the lock builder uses whichever block exists. Hash scan does not run
/// in this case (callers short-circuit), so this case exists for
/// completeness — callers may pre-filter and never see it.
class HashSingleSided extends HashOutcome {
  final modrinth.Version? modrinthVersion;
  final ModFile? curseforgeFile;
  const HashSingleSided({this.modrinthVersion, this.curseforgeFile});
}

/// Compares the newest Modrinth/CurseForge candidates' SHA1s and
/// optionally scans `[hashScanDepth]` additional pairs looking for a
/// match. Pure: no I/O, no Console, no async — the caller threads
/// candidates in newest-first order and decides what to do with the
/// returned [HashOutcome].
///
/// Algorithm (`hash_scan_depth: N` counts **additional** pairs beyond
/// the newest pair; default 10; `0` disables):
///   1. If either side empty, return [HashSingleSided].
///   2. Compare newest Modrinth SHA1 vs newest CurseForge SHA1.
///   3. Match → [HashMatched] on the newest pair.
///   4. Mismatch + [allowHashMismatch] → [HashAcceptedMismatch] on
///      the newest pair.
///   5. Mismatch + depth > 0:
///        cfWindow = take(depth + 1) of [cfCandidates]
///        cfBySha = { f.sha1.lower() → f for f in cfWindow if f.sha1 != null }
///        for mr in take(depth + 1) of [mrCandidates]:
///          if mr.sha1 in cfBySha: return matched(mr, cfBySha[mr.sha1])
///        return [HashExhausted].
///   6. Mismatch + depth == 0 → [HashExhausted] (depthExamined == 0).
HashOutcome scanForMatchingPair({
  required List<modrinth.Version> mrCandidates,
  required List<ModFile> cfCandidates,
  required int hashScanDepth,
  required bool allowHashMismatch,
}) {
  if (mrCandidates.isEmpty || cfCandidates.isEmpty) {
    return HashSingleSided(
      modrinthVersion: mrCandidates.isEmpty ? null : mrCandidates.first,
      curseforgeFile: cfCandidates.isEmpty ? null : cfCandidates.first,
    );
  }

  final newestMr = mrCandidates.first;
  final newestCf = cfCandidates.first;
  final newestMrSha = _modrinthSha1(newestMr);
  final newestCfSha = newestCf.sha1Hash;

  if (newestMrSha != null &&
      newestCfSha != null &&
      newestMrSha == newestCfSha) {
    return HashMatched(modrinthVersion: newestMr, curseforgeFile: newestCf);
  }

  if (hashScanDepth > 0) {
    // Index CF candidates within the window by their lowercase SHA1.
    final windowSize = hashScanDepth + 1;
    final cfWindow = cfCandidates.take(windowSize);
    final cfBySha = <String, ModFile>{};
    for (final f in cfWindow) {
      final sha = f.sha1Hash;
      if (sha != null) cfBySha[sha] = f;
    }
    // Walk Modrinth newest→older within the same window for hits.
    for (final mr in mrCandidates.take(windowSize)) {
      final sha = _modrinthSha1(mr);
      if (sha == null) continue;
      final cfHit = cfBySha[sha];
      if (cfHit != null) {
        return HashMatched(modrinthVersion: mr, curseforgeFile: cfHit);
      }
    }
  }

  if (allowHashMismatch) {
    return HashAcceptedMismatch(
      modrinthVersion: newestMr,
      curseforgeFile: newestCf,
    );
  }

  return HashExhausted(
    newestModrinth: newestMr,
    newestCurseforge: newestCf,
    depthExamined: hashScanDepth,
  );
}

/// Reads the SHA1 (lowercase) from the primary file of a Modrinth
/// version. Modrinth stores hashes per-file in the `hashes` map; the
/// solver-level resolver always picks the primary file.
String? _modrinthSha1(modrinth.Version v) {
  final f = v.primaryFile;
  if (f == null) return null;
  final sha = f.hashes['sha1'];
  return sha?.toLowerCase();
}
