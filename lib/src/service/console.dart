import 'dart:io';

class Console {
  final bool verbose;

  /// When true, [bold]/[red]/[gray] wrap their argument in ANSI escape
  /// codes; when false they pass through. Default is `false` so the
  /// constructor stays `const`-compatible. Use [Console.detect] to opt
  /// into auto-detection (gates on `stdout.supportsAnsiEscapes` plus
  /// the absence of `NO_COLOR`).
  final bool useAnsi;

  const Console({this.verbose = false, this.useAnsi = false});

  /// Returns a [Console] whose [useAnsi] reflects the current process's
  /// stdout terminal state and `NO_COLOR` env var. Cannot be const because
  /// the detection itself is a runtime call.
  factory Console.detect({bool verbose = false}) {
    return Console(verbose: verbose, useAnsi: _detectAnsiSupport());
  }

  static bool _detectAnsiSupport() {
    if (Platform.environment.containsKey('NO_COLOR')) return false;
    try {
      return stdout.hasTerminal && stdout.supportsAnsiEscapes;
    } on Object {
      return false;
    }
  }

  void info(String message) {
    stdout.writeln(message);
  }

  void detail(String message) {
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
