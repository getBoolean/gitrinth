import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import 'java_runtime_resolver.dart';

/// Spawns a process and returns its exit code. Implementations should inherit
/// stdio so the user sees installer output. Tests inject a fake to avoid
/// spawning real Java.
///
/// [environment], when non-null, replaces the inherited process environment
/// for the spawned child. Callers that want to *augment* the parent
/// environment (e.g. to prepend a chosen JDK's `bin/` to `PATH`) must
/// build the merged map themselves and pass it here — semantics match
/// `Process.start`'s `environment` parameter.
typedef ProcessRunner = Future<int> Function(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
  bool runInShell,
  Map<String, String>? environment,
});

/// Turns a cached loader binary (Forge/NeoForge installer JAR or
/// fabric-server-launch JAR) into a runnable server tree under [outputDir].
/// Idempotent via a sentinel marker file so re-runs of `gitrinth build` are
/// fast.
class ServerInstaller {
  final ProcessRunner _runProcess;
  final Map<String, String> _environment;
  final JavaRuntimeResolver? _resolver;

  ServerInstaller({
    ProcessRunner? runProcess,
    Map<String, String>? environment,
    JavaRuntimeResolver? resolver,
  }) : _runProcess = runProcess ?? _defaultRunProcess,
       _environment = environment ?? Platform.environment,
       _resolver = resolver;

  Future<void> installServer({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
    required Directory outputDir,
    required File installerOrServerJar,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
  }) async {
    outputDir.createSync(recursive: true);

    final marker = File(
      p.join(
        outputDir.path,
        '.gitrinth-installed-${loader.name}-$loaderVersion',
      ),
    );
    if (marker.existsSync()) return;

    switch (loader) {
      case Loader.fabric:
        installerOrServerJar.copySync(
          p.join(outputDir.path, 'fabric-server-launch.jar'),
        );
      case Loader.forge:
      case Loader.neoforge:
        if (offline) {
          throw UserError(
            '${loader.name} server install requires running its installer '
            '(network) and --offline was set; rerun without --offline once, '
            'then --offline will reuse the installed tree.',
          );
        }
        final java = await _resolveJava(
          mcVersion: mcVersion,
          javaPath: javaPath,
          allowManagedJava: allowManagedJava,
          offline: offline,
        );
        final exitCode = await _runProcess(
          java.path,
          [
            '-jar',
            installerOrServerJar.path,
            '--installServer',
            outputDir.path,
          ],
          workingDirectory: outputDir,
          environment: _spawnEnvironment(java.path),
        );
        if (exitCode != 0) {
          throw UserError(
            '${loader.name} installer exited with code $exitCode '
            '(see installer output above).',
          );
        }
    }

    marker.writeAsStringSync(DateTime.now().toIso8601String());
  }

  Future<File> _resolveJava({
    required String mcVersion,
    required String? javaPath,
    required bool allowManagedJava,
    required bool offline,
  }) async {
    final r = _resolver;
    if (r != null) {
      return r.resolve(
        mcVersion: mcVersion,
        explicitPath: javaPath,
        allowManaged: allowManagedJava,
        offline: offline,
      );
    }
    // Fallback for tests that don't inject a resolver: legacy
    // JAVA_HOME-or-PATH lookup, no version validation.
    final javaHome = _environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      final candidate = File(
        p.join(javaHome, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
      );
      if (candidate.existsSync()) return candidate;
    }
    return File(Platform.isWindows ? 'java.exe' : 'java');
  }

  /// Builds the spawn environment so `java -jar` resolves to [javaPath]
  /// even when child processes (the installer's own forks) consult
  /// `PATH` or `JAVA_HOME`.
  Map<String, String> _spawnEnvironment(String javaPath) {
    final pathSep = Platform.isWindows ? ';' : ':';
    final binDir = p.dirname(javaPath);
    return {
      ..._environment,
      'PATH': '$binDir$pathSep${_environment['PATH'] ?? ''}',
      'JAVA_HOME': p.dirname(binDir),
    };
  }
}

Future<int> _defaultRunProcess(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
  bool runInShell = false,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory?.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: runInShell,
    environment: environment,
  );
  return process.exitCode;
}
