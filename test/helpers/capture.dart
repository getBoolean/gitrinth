import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/cli/runner.dart';

class CapturedOutput {
  final int exitCode;
  final String stdout;
  final String stderr;

  CapturedOutput(this.exitCode, this.stdout, this.stderr);
}

Future<CapturedOutput> runCli(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final outBuf = _CapturingSink();
  final errBuf = _CapturingSink();
  final savedCwd = Directory.current.path;
  String cwd = workingDirectory == null
      ? savedCwd
      : Directory(workingDirectory).absolute.path;
  try {
    final code = await runZoned<Future<int>>(
      () => IOOverrides.runZoned<Future<int>>(
        () => runGitrinth(args, environment: environment),
        stdout: () => outBuf,
        stderr: () => errBuf,
        stdin: () => _NoTerminalStdin(),
        getCurrentDirectory: () => Directory(cwd),
        setCurrentDirectory: (path) {
          cwd = Directory(path).absolute.path;
        },
      ),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          outBuf.writeln(line);
        },
      ),
    );
    return CapturedOutput(code, outBuf.text, errBuf.text);
  } finally {
    Directory.current = savedCwd;
  }
}

class _CapturingSink implements Stdout {
  final StringBuffer _buf = StringBuffer();

  String get text => _buf.toString();

  @override
  void write(Object? object) {
    _buf.write(object);
  }

  @override
  void writeln([Object? object = '']) {
    _buf.writeln(object);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _buf.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    _buf.writeCharCode(charCode);
  }

  @override
  void add(List<int> data) {
    _buf.write(utf8.decode(data, allowMalformed: true));
  }

  @override
  Future<void> flush() async {}

  @override
  Future close() async {}

  @override
  Future get done => Future<void>.value();

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding _) {}

  @override
  bool get hasTerminal => false;

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  IOSink get nonBlocking => this;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoTerminalStdin implements Stdin {
  @override
  bool get hasTerminal => false;

  @override
  bool get echoMode => false;

  @override
  set echoMode(bool _) {}

  @override
  bool get lineMode => false;

  @override
  set lineMode(bool _) {}

  Encoding get encoding => utf8;

  set encoding(Encoding _) {}

  @override
  String? readLineSync({
    Encoding encoding = systemEncoding,
    bool retainNewlines = false,
  }) => null;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
