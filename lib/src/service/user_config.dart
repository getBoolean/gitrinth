import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

import '../app/env.dart';
import '../app/runner_settings.dart';
import '../cli/exceptions.dart';

/// User-level config file. Currently only carries per-host Modrinth
/// tokens; consumers (`login`/`logout`/`token`) land later. The
/// stub exists so the `--config` flag and `GITRINTH_CONFIG` env var
/// resolve to a real path that the file can be written to lazily.
class UserConfig {
  /// Modrinth-compatible server URL → personal access token.
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

  void write(UserConfig config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(config.toYamlString());
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
