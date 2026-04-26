import 'dart:io';

/// Verbosity floors. Choosing a level prints every category at or below
/// it: e.g. `io` prints errors, warnings, normal messages, and io. The
/// total order is `error < warning < normal < io < solver < all`.
enum LogLevel { error, warning, normal, io, solver, all }

/// Parses a level name produced by `--verbosity=<level>`. Returns `null`
/// for unknown values; callers raise the user-facing usage error.
LogLevel? parseLogLevel(String value) {
  for (final level in LogLevel.values) {
    if (level.name == value) return level;
  }
  return null;
}

class Console {
  final LogLevel level;

  /// When true, [bold]/[red]/[gray] wrap their argument in ANSI escape
  /// codes; when false they pass through. Default is `false` so the
  /// constructor stays `const`-compatible. Use [Console.detect] to opt
  /// into auto-detection (gates on `stdout.supportsAnsiEscapes` plus
  /// the absence of `NO_COLOR`).
  final bool useAnsi;

  const Console({this.level = LogLevel.normal, this.useAnsi = false});

  /// Returns a [Console] whose [useAnsi] reflects the current process's
  /// stdout terminal state and `NO_COLOR` env var. Pass [colorOverride]
  /// (typically from `--color`/`--no-color`) to bypass auto-detection;
  /// [environment] lets tests inject a fake env. Cannot be const because
  /// the detection itself is a runtime call.
  factory Console.detect({
    LogLevel level = LogLevel.normal,
    bool? colorOverride,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    return Console(
      level: level,
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

  bool _enabled(LogLevel category) => level.index >= category.index;

  void error(String message) {
    stderr.writeln('error: $message');
  }

  void warn(String message) {
    if (!_enabled(LogLevel.warning)) return;
    stderr.writeln('warning: $message');
  }

  void message(String msg) {
    if (!_enabled(LogLevel.normal)) return;
    stdout.writeln(msg);
  }

  void io(String msg) {
    if (!_enabled(LogLevel.io)) return;
    stdout.writeln(msg);
  }

  void solver(String msg) {
    if (!_enabled(LogLevel.solver)) return;
    stdout.writeln(msg);
  }

  void trace(String msg) {
    if (!_enabled(LogLevel.all)) return;
    stdout.writeln(msg);
  }

  static const _esc = '\x1b';
  String bold(String s) => useAnsi ? '$_esc[1m$s$_esc[22m' : s;
  String red(String s) => useAnsi ? '$_esc[31m$s$_esc[39m' : s;
  String gray(String s) => useAnsi ? '$_esc[90m$s$_esc[39m' : s;
}
