import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/service/console.dart';
import 'package:test/test.dart';

void main() {
  group('Console levels', () {
    // Each entry: (level, expected stdout categories, expected stderr
    // categories). Categories are the method names — `error` and `warn`
    // route to stderr, the rest to stdout.
    const cases = <({LogLevel level, Set<String> stdout, Set<String> stderr})>[
      (level: LogLevel.error, stdout: <String>{}, stderr: <String>{'error'}),
      (
        level: LogLevel.warning,
        stdout: <String>{},
        stderr: <String>{'error', 'warn'},
      ),
      (
        level: LogLevel.normal,
        stdout: <String>{'message'},
        stderr: <String>{'error', 'warn'},
      ),
      (
        level: LogLevel.io,
        stdout: <String>{'message', 'io'},
        stderr: <String>{'error', 'warn'},
      ),
      (
        level: LogLevel.solver,
        stdout: <String>{'message', 'io', 'solver'},
        stderr: <String>{'error', 'warn'},
      ),
      (
        level: LogLevel.all,
        stdout: <String>{'message', 'io', 'solver', 'trace'},
        stderr: <String>{'error', 'warn'},
      ),
    ];

    for (final c in cases) {
      test('${c.level.name} prints exactly the right channels', () {
        final out = StringBuffer();
        final err = StringBuffer();
        _runCapturingIo(
          () {
            final console = Console(level: c.level);
            console.error('[error]');
            console.warn('[warn]');
            console.message('[message]');
            console.io('[io]');
            console.solver('[solver]');
            console.trace('[trace]');
          },
          out: out,
          err: err,
        );

        for (final name in const ['message', 'io', 'solver', 'trace']) {
          final shouldPrint = c.stdout.contains(name);
          expect(
            out.toString().contains('[$name]'),
            shouldPrint,
            reason: '[$name] expected on stdout=$shouldPrint at ${c.level}',
          );
        }
        for (final name in const ['error', 'warn']) {
          final shouldPrint = c.stderr.contains(name);
          expect(
            err.toString().contains('[$name]'),
            shouldPrint,
            reason: '[$name] expected on stderr=$shouldPrint at ${c.level}',
          );
        }
      });
    }
  });

  group('parseLogLevel', () {
    test('accepts every documented level name', () {
      for (final level in LogLevel.values) {
        expect(parseLogLevel(level.name), equals(level));
      }
    });

    test('rejects unknown values', () {
      expect(parseLogLevel('bogus'), isNull);
      expect(parseLogLevel(''), isNull);
    });
  });

  test('error stays on stderr at every level', () {
    for (final level in LogLevel.values) {
      final out = StringBuffer();
      final err = StringBuffer();
      _runCapturingIo(
        () => Console(level: level).error('boom'),
        out: out,
        err: err,
      );
      expect(out.toString(), isEmpty, reason: 'no stdout at $level');
      expect(
        err.toString(),
        contains('error: boom'),
        reason: 'stderr at $level',
      );
    }
  });
}

void _runCapturingIo(
  void Function() body, {
  required StringBuffer out,
  required StringBuffer err,
}) {
  final outSink = _BufferStdout(out);
  final errSink = _BufferStdout(err);
  IOOverrides.runZoned<void>(
    body,
    stdout: () => outSink,
    stderr: () => errSink,
  );
}

class _BufferStdout implements Stdout {
  final StringBuffer _buf;
  _BufferStdout(this._buf);

  @override
  void write(Object? object) => _buf.write(object);

  @override
  void writeln([Object? object = '']) => _buf.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buf.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);

  @override
  void add(List<int> data) =>
      _buf.write(utf8.decode(data, allowMalformed: true));

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
