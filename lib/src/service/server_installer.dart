import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import 'console.dart';
import 'java_environment.dart' as java_env;
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
typedef ProcessRunner =
    Future<int> Function(
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
  final ProcessRunner? _runProcess;
  final Map<String, String> _environment;
  final JavaRuntimeResolver? _resolver;
  final Console _console;

  ServerInstaller({
    ProcessRunner? runProcess,
    Map<String, String>? environment,
    JavaRuntimeResolver? resolver,
    Console? console,
  }) : _runProcess = runProcess,
       _environment = environment ?? Platform.environment,
       _resolver = resolver,
       _console = console ?? const Console();

  Future<void> installServer({
    required ModLoader loader,
    required String mcVersion,
    required String? modsLoaderVersion,
    required Directory outputDir,
    required File installerOrServerJar,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
    bool verbose = false,
    File? pluginServerJar,
    String? pluginInstallMarker,
  }) async {
    // Plugin-loader installs don't use [loader] / [modsLoaderVersion]; the
    // mod-loader path requires both. Caller must guard with
    // LoaderConfig.hasModRuntime — these throws are the last line of
    // defense and fire in release builds (where `assert` is stripped).
    if (pluginServerJar == null) {
      if (loader == ModLoader.vanilla) {
        throw StateError(
          'installServer: mod-loader path entered with vanilla loader; '
          'gate on LoaderConfig.hasModRuntime.',
        );
      }
      if (modsLoaderVersion == null) {
        throw StateError(
          'installServer: mod-loader install requires a concrete '
          'modsLoaderVersion (gate on LoaderConfig.hasModRuntime).',
        );
      }
    }
    outputDir.createSync(recursive: true);

    if (pluginServerJar != null && pluginInstallMarker != null) {
      final marker = File(
        p.join(outputDir.path, '.gitrinth-installed-$pluginInstallMarker'),
      );
      if (marker.existsSync()) return;
      final destJar = p.join(outputDir.path, 'server.jar');
      pluginServerJar.copySync(destJar);
      _writeStartScripts(outputDir);
      marker.writeAsStringSync(DateTime.now().toIso8601String());
      return;
    }

    final marker = File(
      p.join(
        outputDir.path,
        '.gitrinth-installed-${loader.name}-$modsLoaderVersion',
      ),
    );
    if (marker.existsSync()) return;

    switch (loader) {
      case ModLoader.vanilla:
        throw StateError(
          'installServer: mod-loader path entered with vanilla loader; '
          'caller must dispatch through the plugin-server path or guard '
          'on hasModRuntime.',
        );
      case ModLoader.fabric:
        installerOrServerJar.copySync(
          p.join(outputDir.path, 'fabric-server-launch.jar'),
        );
      case ModLoader.forge:
      case ModLoader.neoforge:
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
        _console.io(
          'Installing ${loader.name} $modsLoaderVersion server (this may take '
          'a minute; pass --verbosity=io to see installer output).',
        );
        final args = <String>[
          '-jar',
          installerOrServerJar.path,
          '--installServer',
          outputDir.path,
        ];
        final environment = _spawnEnvironment(java.path);
        final injected = _runProcess;
        final exitCode = injected != null
            ? await injected(
                java.path,
                args,
                workingDirectory: outputDir,
                environment: environment,
              )
            : await spawnInstaller(
                executable: java.path,
                arguments: args,
                workingDirectory: outputDir,
                environment: environment,
                verbose: verbose,
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
      // The installer only needs the binary.
      final resolved = await r.resolve(
        mcVersion: mcVersion,
        explicitPath: javaPath,
        allowManaged: allowManagedJava,
        offline: offline,
      );
      return resolved.binary;
    }
    // Fallback for tests that don't inject a resolver: legacy
    // JAVA_HOME-or-PATH lookup, no version validation.
    return java_env.resolveJava(_environment['JAVA_HOME']);
  }

  /// Builds the spawn environment so `java -jar` resolves to [javaPath]
  /// even when child processes (the installer's own forks) consult
  /// `PATH` or `JAVA_HOME`.
  Map<String, String> _spawnEnvironment(String javaPath) =>
      java_env.spawnEnvironment(_environment, p.dirname(javaPath));

  void _writeStartScripts(Directory outputDir) {
    File(p.join(outputDir.path, 'start.sh')).writeAsStringSync(
      '#!/usr/bin/env bash\n'
      'set -euo pipefail\n'
      'exec java -Xmx2G -Xms1G -jar server.jar nogui "\$@"\n',
    );
    File(p.join(outputDir.path, 'start.bat')).writeAsStringSync(
      '@echo off\r\n'
      'java -Xmx2G -Xms1G -jar server.jar nogui %*\r\n',
    );
  }
}

/// Spawns a loader installer with verbosity-aware stdio handling. When
/// [verbose] is true the child inherits the parent's stdio so the user
/// sees the installer's chatter live (useful for debugging). When false,
/// stdout/stderr are buffered and only flushed to stderr if the child
/// exits non-zero — keeping the normal-success path quiet.
Future<int> spawnInstaller({
  required String executable,
  required List<String> arguments,
  Directory? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  required bool verbose,
}) async {
  if (verbose) {
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
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory?.path,
    runInShell: runInShell,
    environment: environment,
  );
  final outBuf = StringBuffer();
  final errBuf = StringBuffer();
  final outDone = process.stdout
      .transform(systemEncoding.decoder)
      .listen(outBuf.write)
      .asFuture<void>();
  final errDone = process.stderr
      .transform(systemEncoding.decoder)
      .listen(errBuf.write)
      .asFuture<void>();
  final code = await process.exitCode;
  await Future.wait([outDone, errDone]);
  if (code != 0) {
    final out = outBuf.toString().trimRight();
    final err = errBuf.toString().trimRight();
    if (out.isNotEmpty) stderr.writeln(out);
    if (err.isNotEmpty) stderr.writeln(err);
  }
  return code;
}
