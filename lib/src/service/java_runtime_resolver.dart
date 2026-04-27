import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../util/host_platform.dart';
import 'console.dart';
import 'java_runtime_fetcher.dart';

/// Probes a `java` binary and returns its major version (e.g. 21).
/// Returns null if the binary is missing, exits non-zero, or prints
/// output the resolver can't parse. Tests inject a stub.
typedef JavaProber = Future<int?> Function(String javaPath);

/// Picks a `java` binary that satisfies a modpack's MC version
/// requirement. Resolution chain (first match wins):
///
/// 1. `--java <path>` (file or JDK home) — hard-fails on version mismatch.
///    This is the only source that hard-fails: it's an unambiguous
///    per-invocation directive, so silently overriding it would surprise.
/// 2. `JAVA_HOME` — soft-fails on version mismatch. Logs a warning and
///    falls through; a stale system-wide JAVA_HOME shouldn't block a
///    correctly-flagged invocation.
/// 3. Cached gitrinth-managed Temurin (no probe needed; we installed it).
/// 4. `PATH java` — soft-fails; falls through if the version is wrong.
/// 5. Auto-fetch via [JavaRuntimeFetcher] (skipped when offline or
///    `--no-managed-java`).
class JavaRuntimeResolver {
  final JavaRuntimeFetcher _fetcher;
  final Map<String, String> _environment;
  final Console _console;
  final JavaProber _probe;
  final Map<String, int?> _probeCache = {};

  JavaRuntimeResolver({
    required JavaRuntimeFetcher fetcher,
    Map<String, String>? environment,
    Console? console,
    JavaProber? probe,
  }) : _fetcher = fetcher,
       _environment = environment ?? Platform.environment,
       _console = console ?? const Console(),
       _probe = probe ?? _defaultProbe;

  bool get _isWindows =>
      detectHostPlatform(environment: _environment).isWindows;

  /// Returns the `java` binary plus its major version. Explicit,
  /// JAVA_HOME, and PATH results are probed. Managed runtimes use the
  /// requested feature version. See [JavaRuntimeResolver] for lookup
  /// order.
  Future<({File binary, int majorVersion})> resolve({
    required String mcVersion,
    String? explicitPath,
    bool allowManaged = true,
    bool offline = false,
  }) async {
    final required = JavaRuntimeFetcher.requiredFeatureFor(
      mcVersion,
      console: _console,
    );
    final tried = <String>[];

    // 1. --java <path>
    if (explicitPath != null && explicitPath.isNotEmpty) {
      final binary = _resolveExplicit(explicitPath);
      if (!binary.existsSync()) {
        throw UserError(
          '--java "$explicitPath": no such file (looked for ${binary.path}).',
        );
      }
      final major = await probeMajorVersion(binary.path);
      if (major == null) {
        throw UserError(
          '--java "${binary.path}": could not detect Java version. '
          'Verify the path points at a working `java` binary or JDK home.',
        );
      }
      if (major < required) {
        throw UserError(
          '--java "${binary.path}" is JDK $major; this modpack '
          '(MC $mcVersion) needs JDK >= $required.',
        );
      }
      return (binary: binary, majorVersion: major);
    }

    // 2. JAVA_HOME
    String? deferredJavaHomeWarning;
    final javaHome = _environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      final binary = _binaryUnderJdkHome(javaHome);
      if (binary.existsSync()) {
        final major = await probeMajorVersion(binary.path);
        if (major != null && major >= required) {
          return (binary: binary, majorVersion: major);
        }
        final detail = major == null
            ? 'version unknown'
            : 'JDK $major < required JDK $required';
        // Only surface the warning if we end up resolving via PATH java —
        // the managed-Java path is the expected fallback when JAVA_HOME
        // doesn't satisfy the modpack and shouldn't generate noise.
        deferredJavaHomeWarning =
            'JAVA_HOME="$javaHome" skipped ($detail for MC $mcVersion); '
            'using PATH `java` instead.';
        tried.add('JAVA_HOME="$javaHome" ($detail)');
      } else {
        tried.add('JAVA_HOME="$javaHome" (no bin/java found)');
      }
    }

    // 3. Cached gitrinth-managed Temurin
    final cached = _fetcher.cachedRuntime(required);
    if (cached != null) return (binary: cached, majorVersion: required);

    // 4. PATH java
    final pathJava = _findOnPath();
    if (pathJava != null) {
      final major = await probeMajorVersion(pathJava.path);
      if (major != null && major >= required) {
        if (deferredJavaHomeWarning != null) {
          _console.warn(deferredJavaHomeWarning);
        }
        return (binary: pathJava, majorVersion: major);
      }
      tried.add('PATH `java` at ${pathJava.path} (JDK ${major ?? "unknown"})');
    } else {
      tried.add('PATH (no `java` found)');
    }

    // 5. Auto-fetch (or fail with a clear remediation message).
    if (!allowManaged) {
      throw UserError(
        'no JDK $required+ found and --no-managed-java was set. '
        'Pass --java <path> or install a JDK $required+ and rerun.\n'
        'Tried: ${tried.join("; ")}',
      );
    }
    if (offline) {
      throw UserError(
        'no JDK $required+ found and --offline was set. Rerun without '
        '--offline to auto-download Temurin $required, or pass '
        '--java <path>.\nTried: ${tried.join("; ")}',
      );
    }
    final fetched = await _fetcher.ensureRuntime(required);
    return (binary: fetched, majorVersion: required);
  }

  /// Probes [javaPath] and caches the result. See [JavaProber].
  Future<int?> probeMajorVersion(String javaPath) async {
    final cached = _probeCache[javaPath];
    if (cached != null || _probeCache.containsKey(javaPath)) return cached;
    final major = await _probe(javaPath);
    _probeCache[javaPath] = major;
    return major;
  }

  File _resolveExplicit(String path) {
    final file = File(path);
    if (file.existsSync()) return file;
    final dir = Directory(path);
    if (dir.existsSync()) return _binaryUnderJdkHome(dir.path);
    // Path doesn't exist; return the File so the caller surfaces the
    // missing-file error with the exact spelling the user typed.
    return file;
  }

  File _binaryUnderJdkHome(String jdkHome) {
    final binName = _isWindows ? 'java.exe' : 'java';
    // macOS: <home>/Contents/Home/bin/java when pointed at the bundle root.
    final macHome = File(p.join(jdkHome, 'Contents', 'Home', 'bin', binName));
    if (macHome.existsSync()) return macHome;
    return File(p.join(jdkHome, 'bin', binName));
  }

  File? _findOnPath() {
    final binName = _isWindows ? 'java.exe' : 'java';
    final pathEnv = _environment['PATH'] ?? '';
    final sep = _isWindows ? ';' : ':';
    for (final segment in pathEnv.split(sep)) {
      if (segment.isEmpty) continue;
      final candidate = File(p.join(segment, binName));
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }
}

Future<int?> _defaultProbe(String javaPath) async {
  try {
    final result = await Process.run(javaPath, ['-version']);
    // Java prints `-version` to stderr; some wrappers print to stdout.
    final output = '${result.stdout}${result.stderr}';
    final m = RegExp(r'version "(\d+)(?:\.(\d+))?').firstMatch(output);
    if (m == null) return null;
    final first = int.tryParse(m.group(1) ?? '');
    if (first == null) return null;
    if (first == 1) {
      // Legacy "1.8.0_345" → 8.
      return int.tryParse(m.group(2) ?? '');
    }
    return first;
  } on ProcessException {
    return null;
  }
}
