import 'dart:convert';
import 'dart:io';

/// Reads a secret from stdin without echoing it. On a TTY toggles
/// `stdin.echoMode` off for the read; otherwise reads a piped line.
String readSecret({required String prompt}) {
  if (stdin.hasTerminal) {
    stdout.write(prompt);
    final wasEcho = stdin.echoMode;
    final wasLine = stdin.lineMode;
    stdin.echoMode = false;
    stdin.lineMode = true;
    try {
      final line = stdin.readLineSync(encoding: utf8) ?? '';
      stdout.writeln();
      return line;
    } finally {
      stdin.echoMode = wasEcho;
      stdin.lineMode = wasLine;
    }
  }
  return stdin.readLineSync(encoding: utf8) ?? '';
}
