import 'dart:io';

class Console {
  final bool verbose;

  const Console({this.verbose = false});

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
}
