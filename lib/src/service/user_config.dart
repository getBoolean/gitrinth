import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

import '../app/env.dart';
import '../app/runner_settings.dart';
import '../cli/exceptions.dart';
import 'modrinth_url.dart';

/// User-level config. Holds per-host Modrinth tokens keyed by
/// [normalizeServerKey]; mutate via [withToken] / [withoutToken].
class UserConfig {
  /// Normalized server URL → personal access token.
  final Map<String, String> tokens;

  const UserConfig({this.tokens = const {}});

  factory UserConfig.fromYaml(Object? raw) {
    if (raw is! Map) return const UserConfig();
    final tokensRaw = raw['tokens'];
    final tokens = <String, String>{};
    if (tokensRaw is Map) {
      for (final entry in tokensRaw.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is String && v is String) {
          tokens[k] = v;
        }
      }
    }
    return UserConfig(tokens: tokens);
  }

  /// Copy with [token] stored under `normalizeServerKey(serverUrl)`.
  UserConfig withToken(String serverUrl, String token) {
    final key = normalizeServerKey(serverUrl);
    final next = Map<String, String>.from(tokens);
    next[key] = token;
    return UserConfig(tokens: next);
  }

  /// Copy without the entry for `normalizeServerKey(serverUrl)`.
  UserConfig withoutToken(String serverUrl) {
    final key = normalizeServerKey(serverUrl);
    if (!tokens.containsKey(key)) return this;
    final next = Map<String, String>.from(tokens)..remove(key);
    return UserConfig(tokens: next);
  }

  /// Stored token for [serverUrl] after normalization, or null.
  String? tokenFor(String serverUrl) {
    final key = normalizeServerKey(serverUrl);
    return tokens[key];
  }

  String toYamlString() {
    final buf = StringBuffer();
    if (tokens.isEmpty) {
      buf.writeln('tokens: {}');
    } else {
      buf.writeln('tokens:');
      for (final entry in tokens.entries) {
        buf.writeln('  ${entry.key}: ${entry.value}');
      }
    }
    return buf.toString();
  }
}

/// Resolves the user config file path:
///   1. [override] (typically `--config <path>`).
///   2. `GITRINTH_CONFIG` env var.
///   3. `<home>/.gitrinth/config.yaml` (USERPROFILE on Windows, HOME elsewhere).
String resolveUserConfigPath(Map<String, String> env, {String? override}) {
  if (override != null && override.isNotEmpty) {
    return p.normalize(p.absolute(override));
  }
  final fromEnv = env['GITRINTH_CONFIG'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return p.normalize(p.absolute(fromEnv));
  }
  final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  if (home == null || home.isEmpty) {
    throw const UserError(
      'Unable to locate a home directory for the gitrinth user config. '
      'Pass --config <path> or set GITRINTH_CONFIG.',
    );
  }
  return p.normalize(p.join(home, '.gitrinth', 'config.yaml'));
}

class UserConfigStore {
  final String path;

  UserConfigStore(this.path);

  UserConfig read() {
    final file = File(path);
    if (!file.existsSync()) return const UserConfig();
    final raw = loadYaml(file.readAsStringSync());
    return UserConfig.fromYaml(raw);
  }

  /// Persists [config]. POSIX: best-effort `chmod 600`. Windows:
  /// ACLs are not normalized.
  void write(UserConfig config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(config.toYamlString());
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', ['600', path]);
      } on Object {
        // chmod unavailable; file mode left as-is.
      }
    }
  }
}

final userConfigPathProvider = Provider<String>((ref) {
  final settings = ref.watch(runnerSettingsProvider);
  final env = ref.read(environmentProvider);
  return resolveUserConfigPath(env, override: settings.configPath);
});

final userConfigStoreProvider = Provider<UserConfigStore>(
  (ref) => UserConfigStore(ref.watch(userConfigPathProvider)),
);

final userConfigProvider = Provider<UserConfig>(
  (ref) => ref.watch(userConfigStoreProvider).read(),
);
