import '../model/modrinth/dependency.dart';
import '../model/resolver/result.dart';
import 'source_identity.dart';

/// Indexed dependency edges shared by live and cached resolution adapters.
final class DependencyGraph<T> {
  final _children = <T, Set<T>>{};
  final _parents = <T, Set<T>>{};

  void addNode(T node) {
    _children.putIfAbsent(node, () => {});
    _parents.putIfAbsent(node, () => {});
  }

  void addEdge(T parent, T child) {
    addNode(parent);
    addNode(child);
    _children[parent]!.add(child);
    _parents[child]!.add(parent);
  }

  Set<T> children(T node) => Set.unmodifiable(_children[node] ?? <T>{});
  Set<T> parents(T node) => Set.unmodifiable(_parents[node] ?? <T>{});

  Set<T> reachable(Iterable<T> seeds) {
    final visited = <T>{};
    final queue = seeds.toList();
    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      if (visited.add(node)) queue.addAll(_children[node] ?? <T>{});
    }
    return visited;
  }
}

DependencyGraph<LocalEntryKey> resolvedDependencyGraph(
  ResolutionResult resolution, {
  required String Function(LocalEntryKey node) hostFor,
}) {
  final identity = SourceIdentity();
  final graph = DependencyGraph<LocalEntryKey>();
  for (final entry in resolution.entries) {
    final node = LocalEntryKey(entry.section, entry.slug);
    identity.register(node, host: hostFor(node));
    identity.bind(
      node,
      ModrinthProjectKey(hostFor(node), entry.version.projectId),
    );
    graph.addNode(node);
  }
  for (final entry in resolution.entries) {
    final parent = LocalEntryKey(entry.section, entry.slug);
    for (final dependency in entry.version.dependencies) {
      if (dependency.dependencyType != DependencyType.required ||
          dependency.projectId == null) {
        continue;
      }
      for (final child in identity.aliases(
        ModrinthProjectKey(hostFor(parent), dependency.projectId!),
      )) {
        graph.addEdge(parent, child);
      }
    }
  }
  return graph;
}
