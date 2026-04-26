import 'dart:io';

class Console {
  final bool verbose;
  final bool quiet;

  /// When true, [bold]/[red]/[gray] wrap their argument in ANSI escape
  /// codes; when false they pass through. Default is `false` so the
  /// constructor stays `const`-compatible. Use [Console.detect] to opt
  /// into auto-detection (gates on `stdout.supportsAnsiEscapes` plus
  /// the absence of `NO_COLOR`).
  final bool useAnsi;

  const Console({
    this.verbose = false,
    this.quiet = false,
    this.useAnsi = false,
  });

  /// Returns a [Console] whose [useAnsi] reflects the current process's
  /// stdout terminal state and `NO_COLOR` env var. Pass [colorOverride]
  /// (typically from `--color`/`--no-color`) to bypass auto-detection;
  /// [environment] lets tests inject a fake env. Cannot be const because
  /// the detection itself is a runtime call.
  factory Console.detect({
    bool verbose = false,
    bool quiet = false,
    bool? colorOverride,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    return Console(
      verbose: verbose,
      quiet: quiet,
      useAnsi: resolveUseAnsi(colorOverride, env),
    );
  }

  /// Resolves the effective ANSI setting given an explicit user
  /// override and the env. `null` override means auto-detect.
  static bool resolveUseAnsi(bool? override, Map<String, String> env) {
    if (override != null) return override;
    if (env.containsKey('NO_COLOR')) return false;
    try {
      return stdout.hasTerminal && stdout.supportsAnsiEscapes;
    } on Object {
      return false;
    }
  }

  void info(String message) {
    if (quiet) return;
    stdout.writeln(message);
  }

  void detail(String message) {
    if (quiet) return;
    if (verbose) {
      stdout.writeln(message);
    }
  }

  void warn(String message) {
    stderr.writeln('warning: $message');
  }

  void error(String message) {
    stderr.writeln('error: $message');
  }

  static const _esc = '\x1b';
  String bold(String s) => useAnsi ? '$_esc[1m$s$_esc[22m' : s;
  String red(String s) => useAnsi ? '$_esc[31m$s$_esc[39m' : s;
  String gray(String s) => useAnsi ? '$_esc[90m$s$_esc[39m' : s;
}
