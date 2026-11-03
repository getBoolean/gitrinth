import '../model/manifest/mods_yaml.dart';
import '../model/manifest/mods_lock.dart';
import 'modrinth/modrinth_url.dart';

/// Whether a parent edge is possible on a shared platform and source host.
bool canRequireLockedSource(
  LockedEntry parent,
  LockedEntry child, {
  required String defaultModrinthHost,
}) {
  if (parent.curseforge != null && child.curseforge != null) return true;
  final parentMr = parent.modrinth;
  final childMr = child.modrinth;
  return parentMr != null &&
      childMr != null &&
      normalizeServerKey(parentMr.host ?? defaultModrinthHost) ==
          normalizeServerKey(childMr.host ?? defaultModrinthHost);
}

/// The manifest's local name is scoped to its content section.
final class LocalEntryKey {
  final Section section;
  final String localKey;
  const LocalEntryKey(this.section, this.localKey);
  @override
  bool operator ==(Object other) =>
      other is LocalEntryKey &&
      other.section == section &&
      other.localKey == localKey;
  @override
  int get hashCode => Object.hash(section, localKey);
  @override
  String toString() => '${section.name}/$localKey';
}

/// Platform identity, independent of any number of local aliases.
sealed class RemoteProjectKey {
  const RemoteProjectKey();
}

final class ModrinthProjectKey extends RemoteProjectKey {
  final String host;
  final String projectId;
  ModrinthProjectKey(String host, this.projectId)
    : host = normalizeServerKey(host);
  @override
  bool operator ==(Object other) =>
      other is ModrinthProjectKey &&
      other.host == host &&
      other.projectId == projectId;
  @override
  int get hashCode => Object.hash(host, projectId);
}

final class CurseforgeProjectKey extends RemoteProjectKey {
  final int projectId;
  const CurseforgeProjectKey(this.projectId);
  @override
  bool operator ==(Object other) =>
      other is CurseforgeProjectKey && other.projectId == projectId;
  @override
  int get hashCode => projectId.hashCode;
}

/// One resolution's local nodes and their source identities. Reverse lookups
/// deliberately preserve every alias instead of selecting a last writer.
final class SourceIdentity {
  final _nodes = <LocalEntryKey, ({String host, String projectSlug})>{};
  final _remote = <RemoteProjectKey, Set<LocalEntryKey>>{};
  final _names = <String, Set<LocalEntryKey>>{};
  final _solverKeys = <String, LocalEntryKey>{};
  final _keys = <LocalEntryKey, String>{};

  Iterable<LocalEntryKey> get nodes => _nodes.keys;
  void register(
    LocalEntryKey node, {
    required String host,
    String? projectSlug,
  }) {
    (_names[node.localKey] ??= {}).add(node);
    _nodes[node] = (
      host: normalizeServerKey(host),
      projectSlug: projectSlug ?? node.localKey,
    );
    _keys.putIfAbsent(node, () {
      final key = _solverKeys.containsKey(node.localKey)
          ? '\u0000${node.section.name}/${node.localKey}\u0000'
          : node.localKey;
      _solverKeys[key] = node;
      return key;
    });
  }

  void bind(LocalEntryKey node, RemoteProjectKey remote) =>
      _remote.putIfAbsent(remote, () => {}).add(node);
  Set<LocalEntryKey> aliases(RemoteProjectKey remote) =>
      Set.unmodifiable(_remote[remote] ?? const <LocalEntryKey>{});
  String host(LocalEntryKey node) => _nodes[node]!.host;
  String projectSlug(LocalEntryKey node) => _nodes[node]!.projectSlug;
  String solverKey(LocalEntryKey node) => _keys[node]!;
  LocalEntryKey nodeForSolverKey(String key) => _solverKeys[key]!;

  /// Opaque keys are delimited at both ends, so this cannot replace a
  /// fragment of another key or a user's ordinary local name.
  String displayMessage(String message) {
    for (final entry in _solverKeys.entries) {
      if (entry.key.startsWith('\u0000')) {
        message = message.replaceAll(entry.key, entry.value.localKey);
      }
    }
    return message;
  }

  Set<LocalEntryKey> nodesNamed(String localKey) =>
      Set.unmodifiable(_names[localKey] ?? const <LocalEntryKey>{});

  LocalEntryKey? find(String localKey, [Section? section]) {
    if (section != null) {
      final node = LocalEntryKey(section, localKey);
      return _nodes.containsKey(node) ? node : null;
    }
    final matches = nodesNamed(localKey);
    return matches.length == 1 ? matches.single : null;
  }
}
