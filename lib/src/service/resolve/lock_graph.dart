import 'dart:convert';
import 'dart:io';

import '../../model/manifest/mods_lock.dart';
import '../../model/manifest/mods_yaml.dart';
import '../../cli/exceptions.dart';
import '../dependency_graph.dart';
import '../source_identity.dart';
import '../cache.dart';
import '../console.dart';

/// Reads the `dependencies` array out of the cached `version.json`
/// and returns the list of `project_id`s for entries whose
/// `dependency_type == "required"`. Returns null when the cache file
/// is missing or unparseable (cold cache); returns an empty list when
/// the version legitimately has no required deps.
List<String>? readCachedRequiredChildren(
  GitrinthCache cache,
  String host,
  String projectId,
  String versionId,
) {
  final path = cache.modrinthVersionMetadataPath(
    host: host,
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

/// Lock edges preserve section identity; the legacy bare required_by list is
/// used only when its parent can be identified without guessing.
final class LockedDependencyGraph {
  final graph = DependencyGraph<LocalEntryKey>();
  final identity = SourceIdentity();
  final entries = <LocalEntryKey, LockedEntry>{};
  final diagnostics = <String>[];
  var coldCacheCount = 0;

  LockedDependencyGraph(
    ModsLock lock,
    GitrinthCache cache, {
    required String defaultHost,
  }) {
    for (final section in Section.values) {
      for (final entry in lock.sectionFor(section).entries) {
        final node = LocalEntryKey(section, entry.key);
        final host = entry.value.modrinth?.host ?? defaultHost;
        entries[node] = entry.value;
        identity.register(node, host: host);
        graph.addNode(node);
        final mr = entry.value.modrinth;
        if (mr != null) {
          identity.bind(node, ModrinthProjectKey(host, mr.projectId));
        }
      }
    }
    for (final item in entries.entries) {
      final mr = item.value.modrinth;
      if (mr == null || mr.projectId.isEmpty || mr.versionId.isEmpty) continue;
      final children = readCachedRequiredChildren(
        cache,
        identity.host(item.key),
        mr.projectId,
        mr.versionId,
      );
      if (children == null) {
        coldCacheCount++;
        continue;
      }
      for (final project in children) {
        for (final child in identity.aliases(
          ModrinthProjectKey(identity.host(item.key), project),
        )) {
          graph.addEdge(item.key, child);
        }
      }
    }
    for (final item in entries.entries) {
      for (final parentName in item.value.requiredBy) {
        var candidates = identity.nodesNamed(parentName).toList();
        if (candidates.length > 1) {
          final knownParents = graph.parents(item.key);
          final metadataParents = candidates
              .where(knownParents.contains)
              .toList();
          if (metadataParents.isNotEmpty) {
            continue;
          }
        }
        final child = item.value;
        if (child.modrinth != null) {
          candidates = candidates.where((node) {
            final parent = entries[node]!;
            return (parent.modrinth != null &&
                    identity.host(node) == identity.host(item.key)) ||
                (parent.curseforge != null && child.curseforge != null);
          }).toList();
        }
        if (candidates.length == 1) {
          graph.addEdge(candidates.single, item.key);
        } else if (candidates.length > 1) {
          diagnostics.add(
            "Ambiguous required_by parent '$parentName' for ${item.key}; omitting that edge.",
          );
        }
      }
    }
  }
}

Set<String> walkTransitiveClosure(
  Set<String> seeds,
  ModsLock? lock,
  GitrinthCache cache, {
  required String defaultHost,
  Console? console,
  String verboseLabel = 'walkTransitiveClosure',
}) {
  if (lock == null) {
    console?.io(
      '$verboseLabel: no mods.lock found yet — falling back to the named entries.',
    );
    return seeds;
  }
  final indexed = LockedDependencyGraph(lock, cache, defaultHost: defaultHost);
  if (indexed.diagnostics.isNotEmpty) {
    throw UserError(indexed.diagnostics.join('\n'));
  }
  final nodes = <LocalEntryKey>[];
  for (final seed in seeds) {
    final matches = indexed.identity.nodesNamed(seed);
    if (matches.length > 1) {
      throw UserError(
        "Ambiguous entry '$seed' in mods.lock; cannot unlock its transitive closure.",
      );
    }
    nodes.addAll(matches);
  }
  if (indexed.coldCacheCount > 0) {
    console?.io(
      '$verboseLabel: no cached version.json for ${indexed.coldCacheCount} entries. Run `gitrinth get` to populate the cache.',
    );
  }
  final reachable = indexed.graph.reachable(nodes);
  for (final node in reachable) {
    if (indexed.identity.nodesNamed(node.localKey).length > 1) {
      throw UserError(
        "Ambiguous entry '${node.localKey}' in mods.lock; cannot unlock its transitive closure.",
      );
    }
  }
  return {...seeds, for (final node in reachable) node.localKey};
}
