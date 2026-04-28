import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import '../app/env.dart';
import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/console.dart';
import '../service/cache.dart';
import '../service/java_runtime_fetcher.dart';
import '../service/java_runtime_resolver.dart';
import '../service/jvm_gc.dart';
import '../service/loader_binary_fetcher.dart';
import '../service/loader_client_installer.dart';
import '../service/manifest_io.dart';
import '../service/minecraft_launcher_locator.dart';
import '../service/symlink_util.dart';
import 'build_orchestrator.dart';

class LaunchCommand extends GitrinthCommand {
  @override
  String get name => 'launch';

  @override
  String get description =>
      'Run the modpack to test it: server (`launch server`) or client '
      '(`launch client`).';

  @override
  String get invocation => 'gitrinth launch <subcommand>';

  LaunchCommand() {
    addSubcommand(LaunchServerCommand());
    addSubcommand(LaunchClientCommand());
  }

  @override
  Future<int> run() async {
    printUsage();
    return exitOk;
  }
}

class LaunchServerCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'server';

  @override
  String get description =>
      'Build (if needed) and start the server distribution.';

  @override
  String get invocation =>
      'gitrinth launch server [--accept-eula] [--no-build] [-- <extra args>]';

  /// Trailing args after `--` are forwarded to the server JVM/script. Set this
  /// to false on subclasses that want stricter parsing.
  @override
  bool get takesArguments => true;

  LaunchServerCommand() {
    argParser
      ..addFlag(
        'accept-eula',
        negatable: false,
        help:
            'Write `eula=true` into build/server/eula.txt before starting. '
            'You agree to the Mojang EULA at https://aka.ms/MinecraftEULA.',
      )
      ..addFlag(
        'build',
        defaultsTo: true,
        help: 'Auto-build server/ before launching. Use --no-build to skip.',
      )
      ..addOption(
        'memory',
        abbr: 'm',
        valueHelp: 'size',
        defaultsTo: '2G',
        help:
            'JVM heap size, passed as -Xmx and -Xms. Examples: 2G, 4G, 6144M.',
      )
      ..addOption(
        'memory-max',
        valueHelp: 'size',
        help: 'Override -Xmx (max heap). Falls back to --memory.',
      )
      ..addOption(
        'memory-min',
        valueHelp: 'size',
        help: 'Override -Xms (initial heap). Falls back to --memory.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        valueHelp: 'path',
        help: 'Override the build output directory. Defaults to ./build.',
      )
      ..addOption(
        'java',
        valueHelp: 'path',
        help:
            'Path to a `java` binary OR a JDK home directory. Overrides '
            'JAVA_HOME and the auto-managed JDK. Hard-fails if its major '
            'version does not satisfy the modpack.',
      )
      ..addFlag(
        'managed-java',
        defaultsTo: true,
        help:
            'Auto-download a matching Eclipse Temurin JDK into the gitrinth '
            'cache when no system JDK satisfies the modpack. Use '
            '--no-managed-java to refuse and require --java/JAVA_HOME.',
      )
      ..addFlag(
        'headless',
        defaultsTo: false,
        negatable: false,
        help:
            'Pass `nogui` to the server JAR so it runs without the AWT/Swing '
            'console window. Off by default — opt in for headless hosts.',
      )
      ..addFlag(
        'detach',
        defaultsTo: false,
        negatable: false,
        help:
            'Spawn the server detached so it survives this terminal closing. '
            'POSIX: stdio is closed (no logs, no stdin). Windows: the JVM '
            'gets its own console window with logs and `stop`. gitrinth '
            'prints the PID either way (`kill <pid>` / `taskkill /PID '
            '<pid>`).',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        defaultsTo: false,
        negatable: false,
        help:
            'Bypass the POSIX-only check that rejects `--detach --headless` '
            'together (no terminal, no GUI, no stdin → manual kill only). '
            'No-op on Windows: the JVM\'s own console keeps logs and `stop`.',
      );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final memory = argResults!['memory'] as String;
    final memoryMax = argResults!['memory-max'] as String?;
    final memoryMin = argResults!['memory-min'] as String?;
    resolveJvmHeap(memory: memory, memoryMax: memoryMax, memoryMin: memoryMin);
    return runLaunchServer(
      options: LaunchServerOptions(
        acceptEula: argResults!['accept-eula'] as bool,
        autoBuild: argResults!['build'] as bool,
        memoryMax: memoryMax ?? memory,
        memoryMin: memoryMin ?? memory,
        outputPath: argResults!['output'] as String?,
        offline: readOfflineFlag(),
        verbose: gitrinthRunner.level.index >= LogLevel.io.index,
        extraArgs: List<String>.from(argResults!.rest),
        javaPath: argResults!['java'] as String?,
        allowManagedJava: argResults!['managed-java'] as bool,
        headless: argResults!['headless'] as bool,
        detach: argResults!['detach'] as bool,
        force: argResults!['force'] as bool,
      ),
      container: container,
      console: console,
    );
  }
}

class LaunchServerOptions {
  const LaunchServerOptions({
    required this.acceptEula,
    required this.autoBuild,
    required this.memoryMax,
    required this.memoryMin,
    required this.offline,
    required this.verbose,
    required this.extraArgs,
    required this.headless,
    required this.detach,
    required this.force,
    this.outputPath,
    this.javaPath,
    this.allowManagedJava = true,
  });

  final bool acceptEula;
  final bool autoBuild;
  final String memoryMax;
  final String memoryMin;
  final String? outputPath;
  final bool offline;
  final bool verbose;
  final List<String> extraArgs;

  /// Explicit `--java <path>`: a `java` binary or a JDK home directory.
  /// When set, takes precedence over JAVA_HOME and the auto-managed
  /// JDK; mismatched major version hard-fails.
  final String? javaPath;

  /// When false (`--no-managed-java`), the resolver refuses to
  /// auto-download a JDK and surfaces a clear error if no system JDK
  /// satisfies the modpack.
  final bool allowManagedJava;

  /// Pass `nogui` to the server JAR / run script so the AWT/Swing
  /// management console is suppressed. Off by default — opt in for
  /// headless hosts.
  final bool headless;

  /// Spawn via `ProcessStartMode.detached`. POSIX closes stdio.
  /// Windows gives `java.exe` its own console with logs and stdin.
  final bool detach;

  /// Acknowledge POSIX [detach] + [headless] (no logs, no GUI, no stdin).
  /// No-op on Windows.
  final bool force;
}

/// Outcome of spawning a child via [LaunchProcessRunner]. In foreground
/// (`inheritStdio`) mode [exitCode] is non-null and the spawn awaited
/// the child to exit. In `detached` mode [exitCode] is null because
/// Dart never delivers it for fully-detached children.
typedef LaunchProcessResult = ({int pid, int? exitCode});

typedef LaunchProcessRunner =
    Future<LaunchProcessResult> Function(
      String executable,
      List<String> arguments, {
      Directory? workingDirectory,
      bool runInShell,
      Map<String, String>? environment,
      ProcessStartMode mode,
    });

/// Public hook so [LaunchServerCommand] can drive the launch flow without a
/// hard dependency on [Process.start] (tests inject [runProcess]) and without
/// a hard dependency on [runBuild] (tests inject [doBuild]).
Future<int> runLaunchServer({
  required LaunchServerOptions options,
  required ProviderContainer container,
  required Console console,
  ManifestIo? io,
  LaunchProcessRunner? runProcess,
  Future<int> Function(BuildOptions)? doBuild,
  JavaRuntimeResolver? resolver,
}) async {
  // Windows gets a fresh JVM console, so only gate this on POSIX.
  if (!Platform.isWindows &&
      options.detach &&
      options.headless &&
      !options.force) {
    throw const UserError(
      'On POSIX, `--detach --headless` silences the server (no logs, no '
      'AWT, no stdin) — manual kill only. Pass --force (-f) to acknowledge.',
    );
  }

  final manifestIo = io ?? ManifestIo();
  final effectiveDoBuild =
      doBuild ??
      (BuildOptions opts) =>
          runBuild(options: opts, container: container, console: console);
  final effectiveRunProcess = runProcess ?? _defaultRunProcess;
  final JavaRuntimeResolver effectiveResolver =
      resolver ?? container.read(javaRuntimeResolverProvider);

  if (options.autoBuild) {
    final exit = await effectiveDoBuild(
      BuildOptions(
        envFlag: 'server',
        outputPath: options.outputPath,
        offline: options.offline,
        verbose: options.verbose,
      ),
    );
    if (exit != exitOk) return exit;
  }

  final lock = manifestIo.readModsLock();
  if (lock == null) {
    throw const UserError(
      'mods.lock not found; run `gitrinth get` then `gitrinth build` first, '
      'or drop --no-build.',
    );
  }

  final outputDir = Directory(
    p.normalize(
      p.absolute(
        options.outputPath ?? p.join(manifestIo.directory.path, 'build'),
      ),
    ),
  );
  final serverDir = Directory(p.join(outputDir.path, 'server'));
  if (!serverDir.existsSync()) {
    throw UserError(
      'server distribution not found at ${serverDir.path}. '
      'Drop --no-build or run `gitrinth build server` first.',
    );
  }

  // Resolve Java BEFORE side effects (eula.txt, spawn) so a misconfigured
  // --java fails fast without leaving partial state.
  final java = await effectiveResolver.resolve(
    mcVersion: lock.mcVersion,
    explicitPath: options.javaPath,
    allowManaged: options.allowManagedJava,
    offline: options.offline,
  );

  if (options.acceptEula) {
    File(p.join(serverDir.path, 'eula.txt')).writeAsStringSync('eula=true\n');
  }

  final (executable, args, useShell) = _serverLaunchCommand(
    loader: lock.loader.mods,
    serverDir: serverDir,
    memoryMax: options.memoryMax,
    memoryMin: options.memoryMin,
    extraArgs: options.extraArgs,
    javaPath: java.binary.path,
    javaMajor: java.majorVersion,
    headless: options.headless,
  );

  console.message(
    'Launching ${lock.loader.mods.name} server in ${serverDir.path}...',
  );

  final result = await effectiveRunProcess(
    executable,
    args,
    workingDirectory: serverDir,
    runInShell: useShell,
    environment: _spawnEnvironment(
      base: container.read(environmentProvider),
      javaPath: java.binary.path,
    ),
    mode: options.detach
        ? ProcessStartMode.detached
        : ProcessStartMode.inheritStdio,
  );

  if (options.detach) {
    console.message(
      'Server detached as PID ${result.pid}. Kill it manually if you '
      'need to stop it (`kill ${result.pid}` on POSIX, `taskkill /PID '
      '${result.pid}` on Windows).',
    );
    return exitOk;
  }
  return result.exitCode!;
}

/// Builds the spawn environment so the loader's `run.bat`/`run.sh` (and
/// any nested `java` invocations) resolve to the chosen JDK even when
/// they consult `PATH` or `JAVA_HOME`.
Map<String, String> _spawnEnvironment({
  required Map<String, String> base,
  required String javaPath,
}) {
  final pathSep = Platform.isWindows ? ';' : ':';
  final binDir = p.dirname(javaPath);
  return {
    ...base,
    'PATH': '$binDir$pathSep${base['PATH'] ?? ''}',
    'JAVA_HOME': p.dirname(binDir),
  };
}

(String executable, List<String> args, bool runInShell) _serverLaunchCommand({
  required ModLoader loader,
  required Directory serverDir,
  required String memoryMax,
  required String memoryMin,
  required List<String> extraArgs,
  required String javaPath,
  required int javaMajor,
  required bool headless,
}) {
  final jar = loader.serverLaunchJar;
  if (jar != null) {
    return (
      javaPath,
      [
        ...gcFlagsForJavaMajor(javaMajor),
        '-Xmx$memoryMax',
        '-Xms$memoryMin',
        '-jar',
        jar,
        if (headless) 'nogui',
        ...extraArgs,
      ],
      false,
    );
  }
  // Forge / NeoForge: write JVM args to user_jvm_args.txt.
  _writeUserJvmArgs(serverDir, memoryMax, memoryMin, javaMajor);
  final scriptArgs = [...extraArgs, if (headless) 'nogui'];
  if (Platform.isWindows) {
    final bat = File(p.join(serverDir.path, 'run.bat'));
    if (bat.existsSync()) {
      return (bat.path, scriptArgs, true);
    }
  } else {
    final sh = File(p.join(serverDir.path, 'run.sh'));
    if (sh.existsSync()) {
      // Make it executable in case the installer didn't chmod +x.
      try {
        Process.runSync('chmod', ['+x', sh.path]);
      } catch (_) {
        // Non-fatal; if chmod isn't available the user will see a
        // clearer error from the spawn step.
      }
      return ('bash', [sh.path, ...scriptArgs], false);
    }
  }
  throw UserError(
    '${loader.name} server scripts not found in ${serverDir.path}; '
    'rebuild or run `gitrinth build server` to populate it.',
  );
}

void _writeUserJvmArgs(
  Directory serverDir,
  String memoryMax,
  String memoryMin,
  int javaMajor,
) {
  final file = File(p.join(serverDir.path, 'user_jvm_args.txt'));
  // Replace gitrinth-owned heap/GC tokens; keep everything else.
  final keep = <String>[];
  if (file.existsSync()) {
    for (final raw in file.readAsLinesSync()) {
      final t = raw.trim();
      if (t.startsWith('-Xmx') || t.startsWith('-Xms')) continue;
      if (t.startsWith('-XX:+Use') && t.endsWith('GC')) continue;
      if (t == '-XX:+UnlockExperimentalVMOptions') continue;
      keep.add(raw);
    }
  }
  final out = <String>[
    ...keep,
    ...gcFlagsForJavaMajor(javaMajor),
    '-Xmx$memoryMax',
    '-Xms$memoryMin',
  ];
  file.writeAsStringSync('${out.join('\n')}\n');
}

/// Parses a JVM-style size literal (`<int>[k|K|m|M|g|G|t|T]`) into bytes.
/// Throws [UserError] when [input] doesn't match the JVM grammar — no
/// decimals, no `B` suffix.
int _parseJvmSize(String input) {
  final match = RegExp(r'^\s*(\d+)\s*([kKmMgGtT])?\s*$').firstMatch(input);
  if (match == null) {
    throw UserError(
      'Invalid JVM size "$input". Expected an integer with an optional unit '
      'suffix (k, m, g, or t). Examples: 2G, 6144M, 512K.',
    );
  }
  final raw = match.group(1);
  if (raw == null) {
    throw FormatException(
      'memory specifier "$input" did not parse a numeric prefix',
    );
  }
  final value = int.parse(raw);
  final suffix = match.group(2)?.toLowerCase();
  final multiplier = switch (suffix) {
    'k' => 1024,
    'm' => 1024 * 1024,
    'g' => 1024 * 1024 * 1024,
    't' => 1024 * 1024 * 1024 * 1024,
    _ => 1,
  };
  return value * multiplier;
}

/// Resolves `--memory`, `--memory-max`, `--memory-min` into validated
/// `(xmx, xms)` byte counts. Per-side flags override `--memory`. Throws
/// [UserError] when any value is invalid syntax or when `xms > xmx`.
(int, int) resolveJvmHeap({
  String? memory,
  String? memoryMax,
  String? memoryMin,
}) {
  final xmxStr = memoryMax ?? memory ?? '2G';
  final xmsStr = memoryMin ?? memory ?? '2G';
  final xmx = _parseJvmSize(xmxStr);
  final xms = _parseJvmSize(xmsStr);
  if (xms > xmx) {
    throw UserError(
      'JVM heap min ($xmsStr) exceeds max ($xmxStr); --memory-min must be '
      '<= --memory-max.',
    );
  }
  return (xmx, xms);
}

Future<LaunchProcessResult> _defaultRunProcess(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
  bool runInShell = false,
  Map<String, String>? environment,
  ProcessStartMode mode = ProcessStartMode.inheritStdio,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory?.path,
    mode: mode,
    runInShell: runInShell,
    environment: environment,
  );
  if (mode == ProcessStartMode.detached) {
    // Detached children never deliver exitCode to the parent; returning
    // it here would hang forever. The caller distinguishes outcomes by
    // checking whether they spawned in detached mode.
    return (pid: process.pid, exitCode: null);
  }
  return (pid: process.pid, exitCode: await process.exitCode);
}

/// Updates the profile in [profilesFile] whose `lastVersionId` matches
/// [lastVersionId]: renames it to [newName] and optionally rewrites
/// `javaArgs`. When [javaMajor] is set, injects matching GC flags.
/// When [memoryMax] and [memoryMin] are set, injects `-Xmx` / `-Xms`.
/// Existing heap and GC tokens are stripped first. Other tokens stay.
/// No-op if the file is missing, malformed, or no profile matches.
void _updateInstallerProfile({
  required File profilesFile,
  required String lastVersionId,
  required String newName,
  int? javaMajor,
  String? memoryMax,
  String? memoryMin,
}) {
  if (!profilesFile.existsSync()) return;
  Map<String, dynamic> root;
  try {
    final raw = jsonDecode(profilesFile.readAsStringSync());
    if (raw is! Map<String, dynamic>) return;
    root = raw;
  } on FormatException {
    return;
  }
  final profiles = root['profiles'];
  if (profiles is! Map) return;
  final injectMemory = memoryMax != null && memoryMin != null;
  final injectGc = javaMajor != null;
  for (final entry in profiles.values) {
    if (entry is! Map) continue;
    if (entry['lastVersionId'] != lastVersionId) continue;
    entry['name'] = newName;
    if (injectGc || injectMemory) {
      final existing = entry['javaArgs'];
      final preserved = (existing is String ? existing : '')
          .split(RegExp(r'\s+'))
          .where(
            (t) =>
                t.isNotEmpty &&
                !t.startsWith('-Xmx') &&
                !t.startsWith('-Xms') &&
                !(t.startsWith('-XX:+Use') && t.endsWith('GC')) &&
                t != '-XX:+UnlockExperimentalVMOptions',
          )
          .toList();
      entry['javaArgs'] = [
        ...preserved,
        if (injectGc) ...gcFlagsForJavaMajor(javaMajor),
        if (injectMemory) '-Xmx$memoryMax',
        if (injectMemory) '-Xms$memoryMin',
      ].join(' ');
    }
  }
  profilesFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(root),
  );
}

class LaunchClientCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'client';

  @override
  String get description =>
      'Build (if needed), install the loader into build/client/, and open '
      'the official Minecraft Launcher with --workDir build/client/.';

  @override
  String get invocation => 'gitrinth launch client [--no-build]';

  LaunchClientCommand() {
    argParser
      ..addFlag(
        'build',
        defaultsTo: true,
        help: 'Auto-build client/ before launching. Use --no-build to skip.',
      )
      ..addOption(
        'memory',
        abbr: 'm',
        valueHelp: 'size',
        defaultsTo: '2G',
        help:
            'JVM heap size, written to the launcher profile as -Xmx and -Xms. '
            'Examples: 2G, 4G, 6144M. Only takes effect when explicitly '
            'passed; omit to keep whatever the launcher GUI has set.',
      )
      ..addOption(
        'memory-max',
        valueHelp: 'size',
        help: 'Override -Xmx (max heap). Falls back to --memory.',
      )
      ..addOption(
        'memory-min',
        valueHelp: 'size',
        help: 'Override -Xms (initial heap). Falls back to --memory.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        valueHelp: 'path',
        help: 'Override the build output directory. Defaults to ./build.',
      )
      ..addOption(
        'java',
        valueHelp: 'path',
        help:
            'Path to a `java` binary OR a JDK home directory used to run '
            'the loader installer. Overrides JAVA_HOME and the auto-managed '
            'JDK. Hard-fails if its major version does not satisfy the '
            'modpack.',
      )
      ..addFlag(
        'managed-java',
        defaultsTo: true,
        help:
            'Auto-download a matching Eclipse Temurin JDK into the gitrinth '
            'cache when no system JDK satisfies the modpack. Use '
            '--no-managed-java to refuse and require --java/JAVA_HOME.',
      );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final memory = argResults!['memory'] as String;
    final memoryMax = argResults!['memory-max'] as String?;
    final memoryMin = argResults!['memory-min'] as String?;
    // The launcher GUI owns javaArgs by default; only inject when the user
    // explicitly opts in, so a no-arg `gitrinth launch client` doesn't stomp
    // their customizations.
    final memorySet =
        argResults!.wasParsed('memory') ||
        argResults!.wasParsed('memory-max') ||
        argResults!.wasParsed('memory-min');
    String? effectiveMax;
    String? effectiveMin;
    if (memorySet) {
      resolveJvmHeap(
        memory: memory,
        memoryMax: memoryMax,
        memoryMin: memoryMin,
      );
      effectiveMax = memoryMax ?? memory;
      effectiveMin = memoryMin ?? memory;
    }
    return runLaunchClient(
      options: LaunchClientOptions(
        autoBuild: argResults!['build'] as bool,
        outputPath: argResults!['output'] as String?,
        offline: readOfflineFlag(),
        verbose: gitrinthRunner.level.index >= LogLevel.io.index,
        javaPath: argResults!['java'] as String?,
        allowManagedJava: argResults!['managed-java'] as bool,
        memoryMax: effectiveMax,
        memoryMin: effectiveMin,
      ),
      container: container,
      console: console,
    );
  }
}

class LaunchClientOptions {
  const LaunchClientOptions({
    required this.autoBuild,
    required this.offline,
    required this.verbose,
    this.outputPath,
    this.javaPath,
    this.allowManagedJava = true,
    this.memoryMax,
    this.memoryMin,
  });

  final bool autoBuild;
  final String? outputPath;
  final bool offline;
  final bool verbose;
  final String? javaPath;
  final bool allowManagedJava;

  /// JVM `-Xmx` written into the launcher profile's `javaArgs`. Null means
  /// the user did not pass a memory flag, so gitrinth leaves `javaArgs`
  /// alone — whatever the launcher GUI has set wins.
  final String? memoryMax;

  /// JVM `-Xms` for the launcher profile; same null semantics as
  /// [memoryMax].
  final String? memoryMin;
}

/// Public hook so [LaunchClientCommand] can drive the client-launch flow
/// while tests inject every external dependency (no real launcher spawn,
/// no real installer, no real `Process.start`).
Future<int> runLaunchClient({
  required LaunchClientOptions options,
  required ProviderContainer container,
  required Console console,
  ManifestIo? io,
  LaunchProcessRunner? runProcess,
  Future<int> Function(BuildOptions)? doBuild,
  LoaderBinaryFetcher? fetcher,
  LoaderClientInstaller? clientInstaller,
  MinecraftLauncherLocator? locator,
  GitrinthCache? cache,
}) async {
  if (options.offline) {
    throw const UserError(
      'launch client requires network on first run (the Minecraft Launcher '
      'downloads libraries and assets); rerun without --offline.',
    );
  }

  final manifestIo = io ?? ManifestIo();
  final effectiveDoBuild =
      doBuild ??
      (BuildOptions opts) =>
          runBuild(options: opts, container: container, console: console);
  final effectiveRunProcess = runProcess ?? _defaultRunProcess;
  final LoaderBinaryFetcher effectiveFetcher =
      fetcher ?? container.read(loaderBinaryFetcherProvider);
  final LoaderClientInstaller effectiveClientInstaller =
      clientInstaller ?? container.read(loaderClientInstallerProvider);
  final MinecraftLauncherLocator effectiveLocator =
      locator ?? container.read(minecraftLauncherLocatorProvider);
  final GitrinthCache effectiveCache = cache ?? container.read(cacheProvider);

  if (options.autoBuild) {
    final exit = await effectiveDoBuild(
      BuildOptions(
        envFlag: 'client',
        outputPath: options.outputPath,
        offline: options.offline,
        verbose: options.verbose,
      ),
    );
    if (exit != exitOk) return exit;
  }

  final lock = manifestIo.readModsLock();
  if (lock == null) {
    throw const UserError(
      'mods.lock not found; run `gitrinth get` then `gitrinth build` first, '
      'or drop --no-build.',
    );
  }
  if (!lock.loader.hasModRuntime) {
    throw const UserError(
      'launch client: pack has no mod runtime (loader.mods is vanilla). '
      'gitrinth does not install vanilla Minecraft launchers; use the '
      'official launcher to play this pack.',
    );
  }

  final outputDir = Directory(
    p.normalize(
      p.absolute(
        options.outputPath ?? p.join(manifestIo.directory.path, 'build'),
      ),
    ),
  );
  final clientDir = Directory(p.join(outputDir.path, 'client'));
  if (!clientDir.existsSync()) {
    throw UserError(
      'client distribution not found at ${clientDir.path}. '
      'Drop --no-build or run `gitrinth build client` first.',
    );
  }

  // The launcher's `.minecraft` lives in the gitrinth cache, scoped per
  // pack slug. This lets `gitrinth clean` wipe build/ without taking the
  // user's saves, screenshots, options.txt, or installed loader with it.
  // Artifact dirs (mods/, config/, ...) under the cache workdir are
  // symlinked back to build/client/<section> — the source of truth for
  // those files stays in the pack tree.
  final yaml = manifestIo.readModsYaml();
  final workDir = Directory(effectiveCache.launcherWorkDir(slug: yaml.slug))
    ..createSync(recursive: true);

  // Each entry is a list of path segments so it composes correctly with
  // the platform's directory separator (Windows mklink rejects forward
  // slashes inside the link path) and so the link's parent directory can
  // be pre-created (mklink /J fails if the link's parent doesn't exist).
  for (final segments in const [
    ['mods'],
    ['config'],
    ['shaderpacks'],
    ['global_packs', 'required_data'],
    ['global_packs', 'optional_data'],
    ['global_packs', 'required_resources'],
    ['global_packs', 'optional_resources'],
  ]) {
    // Pre-create the build/client/<rel> dir so the junction target
    // exists even when the build didn't populate that path this run.
    final target = Directory(p.joinAll([clientDir.path, ...segments]))
      ..createSync(recursive: true);
    final linkPath = p.joinAll([workDir.path, ...segments]);
    // Pre-create the link's parent (e.g. workDir/global_packs/) so
    // Windows mklink /J can create the junction inside it.
    final linkParent = Directory(p.dirname(linkPath));
    if (!linkParent.existsSync()) linkParent.createSync(recursive: true);
    await ensureDirSymlink(linkPath: linkPath, target: target.path);
  }

  // hasModRuntime is true (gated above), so a non-vanilla loader was
  // resolved during `gitrinth get`. A null modsLoaderVersion here means the
  // lock is missing the resolved version it should have written.
  final modsLoaderVersion = lock.loader.modsLoaderVersion;
  if (modsLoaderVersion == null) {
    throw const UserError(
      'launch client: mods.lock has hasModRuntime=true but no resolved '
      'loader version — mods.lock is malformed.',
    );
  }

  final installerJar = await effectiveFetcher.fetchClientInstaller(
    loader: lock.loader.mods,
    mcVersion: lock.mcVersion,
    modsLoaderVersion: modsLoaderVersion,
  );

  // Install the loader into the cache workdir so versions/, libraries/,
  // and the installer's auto-injected launcher_profiles.json entry all
  // live there. The launcher's --workDir flag below makes the GUI read
  // this tree as its .minecraft.
  final lastVersionId = await effectiveClientInstaller.installClient(
    loader: lock.loader.mods,
    mcVersion: lock.mcVersion,
    modsLoaderVersion: modsLoaderVersion,
    dotMinecraftDir: workDir,
    installerJar: installerJar,
    offline: options.offline,
    javaPath: options.javaPath,
    allowManagedJava: options.allowManagedJava,
    verbose: options.verbose,
  );

  // Rename the installer-created profile and refresh managed GC/heap args.
  final javaMajor = JavaRuntimeFetcher.requiredFeatureFor(
    lock.mcVersion,
    console: console,
  );
  _updateInstallerProfile(
    profilesFile: File(p.join(workDir.path, 'launcher_profiles.json')),
    lastVersionId: lastVersionId,
    newName: 'gitrinth: ${yaml.slug}',
    javaMajor: javaMajor,
    memoryMax: options.memoryMax,
    memoryMin: options.memoryMin,
  );

  final launcherExe = effectiveLocator.launcherExecutable;
  console.message(
    'Opening Minecraft Launcher with workDir ${workDir.path} '
    '(artifacts symlinked from ${clientDir.path}). The profile is named '
    '"gitrinth: ${yaml.slug}"; click Play to boot the modpack.',
  );

  await effectiveRunProcess(launcherExe.path, [
    '--workDir',
    workDir.absolute.path,
  ], mode: ProcessStartMode.detached);
  return exitOk;
}
