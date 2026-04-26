import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import 'console.dart';
import 'java_environment.dart' as java_env;
import 'java_runtime_resolver.dart';
import 'server_installer.dart' show ProcessRunner, spawnInstaller;

/// Runs the loader's installer in client mode against the user's `.minecraft`
/// directory, registering a profile entry and downloading the loader's
/// libraries. Returns the `lastVersionId` string suitable for plumbing into
/// `launcher_profiles.json`.
class LoaderClientInstaller {
  final ProcessRunner? _runProcess;
  final Map<String, String> _environment;
  final JavaRuntimeResolver? _resolver;
  final Console _console;

  LoaderClientInstaller({
    ProcessRunner? runProcess,
    Map<String, String>? environment,
    JavaRuntimeResolver? resolver,
    Console? console,
  }) : _runProcess = runProcess,
       _environment = environment ?? Platform.environment,
       _resolver = resolver,
       _console = console ?? const Console();

  Future<String> installClient({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
    required Directory dotMinecraftDir,
    required File installerJar,
    required bool offline,
    String? javaPath,
    bool allowManagedJava = true,
    bool verbose = false,
  }) async {
    final versionId = expectedClientVersionId(
      loader: loader,
      mcVersion: mcVersion,
      loaderVersion: loaderVersion,
    );

    // Idempotent: the launcher writes <dotMc>/versions/<id>/<id>.json on
    // first install; treat its presence as "already installed".
    final versionJson = File(
      p.join(dotMinecraftDir.path, 'versions', versionId, '$versionId.json'),
    );
    if (versionJson.existsSync()) return versionId;

    if (offline) {
      throw UserError(
        '${loader.name} client install requires running its installer '
        '(network) and --offline was set. Drop --offline once to install '
        'the loader; later launches re-use the existing install.',
      );
    }

    dotMinecraftDir.createSync(recursive: true);
    // All three installers want a `launcher_profiles.json` to exist before
    // they will append a profile entry to it (Forge/NeoForge error out
    // otherwise; Fabric needs it once we drop `-noprofile`). Seed an empty
    // one if missing.
    final profilesFile = File(
      p.join(dotMinecraftDir.path, 'launcher_profiles.json'),
    );
    if (!profilesFile.existsSync()) {
      profilesFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'profiles': <String, dynamic>{},
          'settings': <String, dynamic>{},
          'version': 3,
        }),
      );
    }

    final java = await _resolveJava(
      mcVersion: mcVersion,
      javaPath: javaPath,
      allowManagedJava: allowManagedJava,
      offline: offline,
    );
    _console.io(
      'Installing ${loader.name} $loaderVersion client into '
      '${dotMinecraftDir.path} (this may take a minute; pass --verbosity=io '
      'to see installer output).',
    );
    final args = _installArgs(
      loader: loader,
      mcVersion: mcVersion,
      loaderVersion: loaderVersion,
      installerJar: installerJar,
      dotMinecraftDir: dotMinecraftDir,
    );

    final environment = _spawnEnvironment(java.path);
    final injected = _runProcess;
    final exitCode = injected != null
        ? await injected(java.path, args, environment: environment)
        : await spawnInstaller(
            executable: java.path,
            arguments: args,
            environment: environment,
            verbose: verbose,
          );
    if (exitCode != 0) {
      throw UserError(
        '${loader.name} client installer exited with code $exitCode '
        '(see installer output above).',
      );
    }

    return versionId;
  }

  Map<String, String> _spawnEnvironment(String javaPath) =>
      java_env.spawnEnvironment(_environment, p.dirname(javaPath));

  /// The `lastVersionId` the launcher uses for the freshly-installed profile.
  /// Must match what the installer writes to `<dotMc>/versions/`.
  static String expectedClientVersionId({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) {
    switch (loader) {
      case Loader.fabric:
        return 'fabric-loader-$loaderVersion-$mcVersion';
      case Loader.forge:
        return '$mcVersion-forge-$loaderVersion';
      case Loader.neoforge:
        return 'neoforge-$loaderVersion';
    }
  }

  List<String> _installArgs({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
    required File installerJar,
    required Directory dotMinecraftDir,
  }) {
    switch (loader) {
      case Loader.fabric:
        return [
          '-jar',
          installerJar.path,
          'client',
          '-dir',
          dotMinecraftDir.path,
          '-mcversion',
          mcVersion,
          '-loader',
          loaderVersion,
        ];
      case Loader.forge:
      case Loader.neoforge:
        return [
          '-jar',
          installerJar.path,
          '--installClient',
          dotMinecraftDir.path,
        ];
    }
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
    return java_env.resolveJava(_environment['JAVA_HOME']);
  }
}
