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
        expect(out.stdout, contains('--loader'));
        expect(out.stdout, contains('--mc-version'));
        expect(out.stdout, contains('--slug'));
        expect(out.stdout, contains('--name'));
        expect(out.stdout, contains('--force'));
      });
    });
  });
}
