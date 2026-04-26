import 'dart:convert';
import 'dart:io';

import '../model/manifest/mods_lock.dart';
import 'cache.dart';
import 'console.dart';

/// Reads the `dependencies` array out of the cached `version.json`
/// and returns the list of `project_id`s for entries whose
/// `dependency_type == "required"`. Returns null when the cache file
/// is missing or unparseable (cold cache); returns an empty list when
/// the version legitimately has no required deps.
List<String>? readCachedRequiredChildren(
  GitrinthCache cache,
  String projectId,
  String versionId,
) {
  final path = cache.modrinthVersionMetadataPath(
    projectId: projectId,
    versionId: versionId,
  );
  final file = File(path);
  if (!file.existsSync()) return null;
  final dynamic raw;
  try {
    raw = jsonDecode(file.readAsStringSync());
  } on Object {
    return null;
  }
  if (raw is! Map) return null;
  final deps = raw['dependencies'];
  if (deps is! List) return const [];
  final out = <String>[];
  for (final d in deps) {
    if (d is! Map) continue;
    if (d['dependency_type'] != 'required') continue;
    final pid = d['project_id'];
    if (pid is String && pid.isNotEmpty) out.add(pid);
  }
  return out;
}

/// BFS over the dep graph to compute the transitive closure of
/// [seeds]. Edges are read from the artifact cache's per-version
/// `version.json` (mirrors dart pub's "graph in cache" architecture
/// — see [GitrinthCache.modrinthVersionMetadataPath]).
///
/// Cold-cache entries (a slug whose `version.json` hasn't been written
/// yet) are reported via `console.detail` (gated on the optional
/// [verboseLabel] for caller-specific phrasing) and their children are
/// skipped; subsequent runs populate the cache.
///
/// When [lock] is null, the closure is just [seeds]: there is no
/// graph to walk yet.
Set<String> walkTransitiveClosure(
  Set<String> seeds,
  ModsLock? lock,
  GitrinthCache cache, {
  Console? console,
  String verboseLabel = 'walkTransitiveClosure',
}) {
  if (lock == null) {
    console?.io(
      '$verboseLabel: no mods.lock found yet — '
      'falling back to the named entries.',
    );
    return seeds;
  }

  final lookup = <String, LockedEntry>{};
  final projectIdToSlug = <String, String>{};
  for (final entry in lock.allEntries) {
    lookup[entry.key] = entry.value;
    final pid = entry.value.projectId;
    if (pid != null) projectIdToSlug[pid] = entry.key;
  }

  final closure = <String>{...seeds};
  final queue = <String>[...seeds];
  while (queue.isNotEmpty) {
    final slug = queue.removeLast();
    final entry = lookup[slug];
    if (entry == null) {
      console?.io(
        "$verboseLabel: '$slug' not in mods.lock; skipping.",
      );
      continue;
    }
    if (entry.sourceKind != LockedSourceKind.modrinth) continue;
    final pid = entry.projectId;
    final vid = entry.versionId;
    if (pid == null || vid == null) continue;

    final children = readCachedRequiredChildren(cache, pid, vid);
    if (children == null) {
      console?.io(
        "$verboseLabel: no cached version.json for "
        "'$slug' ($pid/$vid); skipping its transitive children. "
        'Run `gitrinth get` to populate the cache.',
      );
      continue;
    }
    for (final childPid in children) {
      final childSlug = projectIdToSlug[childPid];
      if (childSlug == null) continue;
      if (closure.add(childSlug)) queue.add(childSlug);
    }
  }
  return closure;
}
