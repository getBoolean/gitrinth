import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';

/// Spawns a process and returns its exit code. Implementations should inherit
/// stdio so the user sees installer output. Tests inject a fake to avoid
/// spawning real Java.
typedef ProcessRunner = Future<int> Function(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
  bool runInShell,
});

/// Turns a cached loader binary (Forge/NeoForge installer JAR or
/// fabric-server-launch JAR) into a runnable server tree under [outputDir].
/// Idempotent via a sentinel marker file so re-runs of `gitrinth build` are
/// fast.
class ServerInstaller {
  final ProcessRunner _runProcess;
  final Map<String, String> _environment;

  ServerInstaller({
    ProcessRunner? runProcess,
    Map<String, String>? environment,
  }) : _runProcess = runProcess ?? _defaultRunProcess,
       _environment = environment ?? Platform.environment;

  Future<void> installServer({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
    required Directory outputDir,
    required File installerOrServerJar,
    required bool offline,
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
        final java = _resolveJava();
        final exitCode = await _runProcess(
          java,
          [
            '-jar',
            installerOrServerJar.path,
            '--installServer',
            outputDir.path,
          ],
          workingDirectory: outputDir,
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

  String _resolveJava() {
    final javaHome = _environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      final candidate = p.join(
        javaHome,
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      );
      if (File(candidate).existsSync()) return candidate;
    }
    return Platform.isWindows ? 'java.exe' : 'java';
  }
}

Future<int> _defaultRunProcess(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
  bool runInShell = false,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory?.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: runInShell,
  );
  return process.exitCode;
}
