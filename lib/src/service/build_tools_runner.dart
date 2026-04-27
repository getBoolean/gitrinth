import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import 'cache.dart';
import 'console.dart';
import 'downloader.dart';
import 'java_runtime_resolver.dart';
import 'server_installer.dart' show ProcessRunner, spawnInstaller;

/// Spigot-family flavor produced by SpigotMC's `BuildTools.jar`.
enum SpigotFlavor { spigot, craftbukkit }

/// Wraps the SpigotMC `BuildTools.jar` lifecycle: download once, run on
/// demand, cache the produced server jar. Isolated from
/// [PluginServerSource] so it can be tested without spawning a real JVM.
class BuildToolsRunner {
  final ProcessRunner? _runProcess;
  final Downloader _downloader;
  final GitrinthCache _cache;
  final JavaRuntimeResolver? _resolver;
  final String _buildToolsUrl;
  final ProcessRunner _gitProbe;

  BuildToolsRunner({
    required Downloader downloader,
    required GitrinthCache cache,
    JavaRuntimeResolver? resolver,
    ProcessRunner? runProcess,
    Map<String, String>? environment,
    String? buildToolsUrlTemplate,
    ProcessRunner? gitProbe,
  }) : _downloader = downloader,
       _cache = cache,
       _resolver = resolver,
       _runProcess = runProcess,
       _buildToolsUrl =
           buildToolsUrlTemplate ??
           (environment ?? Platform.environment)['GITRINTH_BUILDTOOLS_URL'] ??
           'https://hub.spigotmc.org/jenkins/job/BuildTools/'
               'lastSuccessfulBuild/artifact/target/BuildTools.jar',
       _gitProbe = gitProbe ?? _defaultGitProbe;

  /// Returns the cached spigot/craftbukkit jar for ([flavor], [mc]),
  /// running BuildTools on first call. Re-runs hit the cache and skip
  /// the download + spawn. [offline] forces a cache-only resolution
  /// (BuildTools needs network + git, so a clean cache miss errors).
  Future<File> buildSpigotFamily({
    required String mc,
    required SpigotFlavor flavor,
    required Console console,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
  }) async {
    final artifactKey = _artifactKey(flavor);
    final filename = _producedJarName(flavor, mc);
    final cachedPath = _cache.pluginServerJarPath(
      artifactKey: artifactKey,
      mcVersion: mc,
      version: mc,
      filename: filename,
    );
    final cached = File(cachedPath);
    if (cached.existsSync()) return cached;

    if (offline) {
      throw UserError(
        'BuildTools requires network and git to fetch sources for '
        '$artifactKey $mc, but --offline was set. Rerun without '
        '--offline once to populate the cache.',
      );
    }

    if (!await _hasGit()) {
      throw const UserError(
        'BuildTools requires `git` on PATH but `git --version` did not '
        'succeed. Install Git and rerun.',
      );
    }

    final buildToolsJar = await _ensureBuildToolsJar();
    final java = await _resolveJava(
      mcVersion: mc,
      javaPath: javaPath,
      allowManagedJava: allowManagedJava,
      offline: offline,
    );

    final workDir = Directory(
      p.join(
        _cache.buildToolsCacheRoot,
        'work-${DateTime.now().microsecondsSinceEpoch}'
        '-${Random().nextInt(1 << 32)}',
      ),
    )..createSync(recursive: true);

    try {
      console.io(
        'Running BuildTools for ${flavor.name} $mc (this can take several '
        'minutes; pass --verbosity=io to see progress).',
      );
      final args = <String>[
        '-jar',
        buildToolsJar.path,
        '--rev',
        mc,
        if (flavor == SpigotFlavor.craftbukkit) ...['--compile', 'craftbukkit'],
      ];
      final injected = _runProcess;
      final exitCode = injected != null
          ? await injected(
              java.path,
              args,
              workingDirectory: workDir,
              runInShell: false,
            )
          : await spawnInstaller(
              executable: java.path,
              arguments: args,
              workingDirectory: workDir,
              verbose: false,
            );
      if (exitCode != 0) {
        throw UserError(
          'BuildTools exited with code $exitCode while building '
          '${flavor.name} $mc.',
        );
      }
      final produced = File(p.join(workDir.path, filename));
      if (!produced.existsSync()) {
        throw UserError(
          'BuildTools finished but ${flavor.name}-$mc.jar was not produced '
          'in ${workDir.path}.',
        );
      }
      Directory(p.dirname(cachedPath)).createSync(recursive: true);
      produced.copySync(cachedPath);
      return File(cachedPath);
    } finally {
      try {
        if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<File> _ensureBuildToolsJar() async {
    final dest = p.join(_cache.buildToolsCacheRoot, 'BuildTools.jar');
    return _downloader.downloadTo(url: _buildToolsUrl, destinationPath: dest);
  }

  Future<File> _resolveJava({
    required String mcVersion,
    required String? javaPath,
    required bool allowManagedJava,
    required bool offline,
  }) async {
    final r = _resolver;
    if (r != null) {
      // BuildTools only needs the binary.
      final resolved = await r.resolve(
        mcVersion: mcVersion,
        explicitPath: javaPath,
        allowManaged: allowManagedJava,
        offline: offline,
      );
      return resolved.binary;
    }
    if (javaPath != null && javaPath.isNotEmpty) return File(javaPath);
    final binName = Platform.isWindows ? 'java.exe' : 'java';
    return File(binName);
  }

  Future<bool> _hasGit() async {
    try {
      final code = await _gitProbe('git', const [
        '--version',
      ], runInShell: false);
      return code == 0;
    } on Object {
      return false;
    }
  }

  String _artifactKey(SpigotFlavor flavor) => switch (flavor) {
    SpigotFlavor.spigot => 'spigot',
    SpigotFlavor.craftbukkit => 'craftbukkit',
  };

  String _producedJarName(SpigotFlavor flavor, String mc) => switch (flavor) {
    SpigotFlavor.spigot => 'spigot-$mc.jar',
    SpigotFlavor.craftbukkit => 'craftbukkit-$mc.jar',
  };
}

Future<int> _defaultGitProbe(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
  bool runInShell = false,
  Map<String, String>? environment,
}) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory?.path,
      runInShell: runInShell,
      environment: environment,
    );
    return result.exitCode;
  } on ProcessException {
    return -1;
  }
}
