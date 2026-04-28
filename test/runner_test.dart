import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/service/console.dart';
import 'package:test/test.dart';

import 'helpers/capture.dart';

void main() {
  group('GitrinthRunner', () {
    test('--version prints "gitrinth 0.1.0" and exits 0', () async {
      final out = await runCli(['--version']);
      expect(out.exitCode, 0);
      expect(out.stdout.trim(), equals('gitrinth 0.1.0'));
    });

    test('--help lists every MVP command', () async {
      final out = await runCli(['--help']);
      expect(out.exitCode, 0);
      for (final cmd in [
        'create',
        'get',
        'add',
        'remove',
        'build',
        'clean',
        'pack',
      ]) {
        expect(
          out.stdout,
          contains(cmd),
          reason: 'help output should mention "$cmd"',
        );
      }
    });

    test('unknown command exits 64 (usage error)', () async {
      final out = await runCli(['nope']);
      expect(out.exitCode, 64);
    });

    test('pack outside a project exits 1 with a friendly UserError', () async {
      // Run from the package root, which has no mods.yaml. The runner
      // should surface a UserError pointing at `gitrinth create`.
      final out = await runCli(['pack']);
      expect(out.exitCode, 1);
      expect(out.stderr, contains('mods.yaml not found'));
      expect(out.stderr, contains('gitrinth create'));
    });

    test('unknown --flag exits 64', () async {
      final out = await runCli(['--nope']);
      expect(out.exitCode, 64);
    });

    test('-C nonexistent path exits 1 with UserError', () async {
      final out = await runCli(['-C', '/does/not/exist/anywhere', 'get']);
      expect(out.exitCode, 1);
      expect(out.stderr, contains('Directory not found'));
    });

    group('global options', () {
      test('--help advertises -q, --color, --config, --verbosity', () async {
        final out = await runCli(['--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('--quiet'));
        expect(out.stdout, contains('--[no-]color'));
        expect(out.stdout, contains('--config'));
        expect(out.stdout, contains('--verbosity'));
      });

      test('combining --verbose and --quiet exits 64', () async {
        final out = await runCli(['--verbose', '--quiet', 'get']);
        expect(out.exitCode, 64);
        expect(out.stderr, contains('Cannot combine --verbose and --quiet'));
      });

      test('combining -v and -q exits 64', () async {
        final out = await runCli(['-v', '-q', 'get']);
        expect(out.exitCode, 64);
      });

      test('combining --verbosity and --verbose exits 64', () async {
        final out = await runCli(['--verbosity=io', '-v', 'get']);
        expect(out.exitCode, 64);
        expect(
          out.stderr,
          contains('Cannot combine --verbosity with --verbose or --quiet'),
        );
      });

      test('combining --verbosity and --quiet exits 64', () async {
        final out = await runCli(['--verbosity=warning', '-q', 'get']);
        expect(out.exitCode, 64);
      });

      test('--verbosity=bogus exits 64', () async {
        final out = await runCli(['--verbosity=bogus', 'get']);
        expect(out.exitCode, 64);
      });

      test('every documented --verbosity value parses', () async {
        for (final level in const [
          'error',
          'warning',
          'normal',
          'io',
          'solver',
          'all',
        ]) {
          final out = await runCli(['--verbosity=$level', '--help']);
          expect(
            out.exitCode,
            0,
            reason: '--verbosity=$level should be accepted',
          );
        }
      });

      test('--config does not error on --help', () async {
        final out = await runCli(['--config', '/tmp/cfg.yaml', '--help']);
        expect(out.exitCode, 0);
      });
    });

    group('command --help output advertises MVP flags', () {
      test('get', () async {
        final out = await runCli(['get', '--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('--dry-run'));
        expect(out.stdout, contains('--enforce-lockfile'));
      });

      test('add', () async {
        final out = await runCli(['add', '--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('--env'));
        expect(out.stdout, contains('--url'));
        expect(out.stdout, contains('--path'));
        expect(out.stdout, contains('--dry-run'));
      });

      test('remove', () async {
        final out = await runCli(['remove', '--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('--dry-run'));
      });

      test('build', () async {
        final out = await runCli(['build', '--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('client|server|both'));
        expect(out.stdout, contains('--output'));
        expect(out.stdout, contains('--clean'));
        expect(out.stdout, contains('--skip-download'));
      });

      test('clean', () async {
        final out = await runCli(['clean', '--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('--output'));
      });

      test('pack', () async {
        final out = await runCli(['pack', '--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('--output'));
      });

      test('create', () async {
        final out = await runCli(['create', '--help']);
        expect(out.exitCode, 0);
        expect(out.stdout, contains('--mod-loader'));
        expect(out.stdout, contains('--plugin-loader'));
        expect(out.stdout, contains('--mc-version'));
        expect(out.stdout, contains('--slug'));
        expect(out.stdout, contains('--name'));
        expect(out.stdout, contains('--force'));
      });
    });
  });

  group('Console (driven by global flags)', () {
    test(
      'warning level suppresses message and io but warn/error still print',
      () {
        final out = StringBuffer();
        final err = StringBuffer();
        _runCapturingIo(
          () {
            const c = Console(level: LogLevel.warning);
            c.message('hello');
            c.io('cache hit');
            c.warn('careful');
            c.error('boom');
          },
          out: out,
          err: err,
        );
        expect(out.toString(), isEmpty);
        expect(err.toString(), contains('warning: careful'));
        expect(err.toString(), contains('error: boom'));
      },
    );

    test('default level writes message to stdout', () {
      final out = StringBuffer();
      _runCapturingIo(
        () => const Console().message('hello'),
        out: out,
        err: StringBuffer(),
      );
      expect(out.toString(), contains('hello'));
    });

    test('--no-color override forces ANSI off', () {
      final c = Console.detect(colorOverride: false, environment: const {});
      expect(c.useAnsi, isFalse);
      expect(c.bold('x'), equals('x'));
    });

    test('--color override re-enables ANSI when NO_COLOR is set', () {
      final c = Console.detect(
        colorOverride: true,
        environment: const {'NO_COLOR': '1'},
      );
      expect(c.useAnsi, isTrue);
      expect(c.bold('x'), contains('\x1b'));
    });

    test('NO_COLOR honored when no override is set', () {
      final c = Console.detect(environment: const {'NO_COLOR': '1'});
      expect(c.useAnsi, isFalse);
    });
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
