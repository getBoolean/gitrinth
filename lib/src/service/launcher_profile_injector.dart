import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads, mutates, and writes the official Minecraft Launcher's
/// `launcher_profiles.json` file. Preserves unrelated entries (other
/// people's profiles, the launcher's own settings keys) and round-trips
/// the JSON via a temp+rename so a crash mid-write cannot corrupt it.
class LauncherProfileInjector {
  final File _file;

  LauncherProfileInjector({required File file}) : _file = file;

  /// Inserts (or updates in place) the profile keyed by [key]. The
  /// `created` timestamp is set on first insert and preserved across later
  /// upserts; `lastUsed` is bumped every call so the launcher highlights
  /// the gitrinth profile by default.
  Future<void> upsertProfile({
    required String key,
    required String displayName,
    required String lastVersionId,
    required Directory gameDir,
    String? javaArgs,
  }) async {
    final root = _readOrInit();
    final profiles = root.putIfAbsent('profiles', () => <String, dynamic>{})
        as Map<String, dynamic>;
    final now = DateTime.now().toUtc().toIso8601String();

    final existing = profiles[key];
    final created = existing is Map<String, dynamic>
        ? (existing['created'] as String? ?? now)
        : now;

    final next = <String, dynamic>{
      'name': displayName,
      'type': 'custom',
      'lastVersionId': lastVersionId,
      'gameDir': gameDir.absolute.path,
      'created': created,
      'lastUsed': now,
    };
    if (javaArgs != null) next['javaArgs'] = javaArgs;
    profiles[key] = next;

    _atomicWrite(root);
  }

  Map<String, dynamic> _readOrInit() {
    if (!_file.existsSync()) return <String, dynamic>{};
    try {
      final raw = jsonDecode(_file.readAsStringSync());
      if (raw is Map<String, dynamic>) return raw;
      return <String, dynamic>{};
    } on FormatException {
      // Treat corrupt JSON as if the file didn't exist; the launcher's own
      // recovery path does the same.
      return <String, dynamic>{};
    }
  }

  void _atomicWrite(Map<String, dynamic> root) {
    final dir = _file.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(root),
      flush: true,
    );
    if (_file.existsSync()) _file.deleteSync();
    tmp.renameSync(_file.path);
  }
}

/// Convenience that builds an injector pointed at the standard
/// `<dotMinecraft>/launcher_profiles.json` location.
LauncherProfileInjector launcherProfileInjectorFor(Directory dotMinecraftDir) {
  return LauncherProfileInjector(
    file: File(p.join(dotMinecraftDir.path, 'launcher_profiles.json')),
  );
}
