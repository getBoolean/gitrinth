import 'package:test/test.dart';

import '../helpers/capture.dart';

const _subcommandNames = [
  'add',
  'build',
  'clean',
  'completion',
  'create',
  'get',
  'pack',
  'remove',
];

const _envValues = ['client', 'server', 'both'];
const _loaderValues = ['forge', 'fabric', 'neoforge'];
const _pluginLoaderValues = ['bukkit', 'folia', 'paper', 'spigot', 'sponge'];

void _expectCommonAnchors(String stdout) {
  expect(stdout, contains('gitrinth'));
  for (final name in _subcommandNames) {
    expect(stdout, contains(name), reason: 'missing subcommand "$name"');
  }
  for (final v in _envValues) {
    expect(stdout, contains(v), reason: 'missing --env value "$v"');
  }
  for (final v in _loaderValues) {
    expect(stdout, contains(v), reason: 'missing --mod-loader value "$v"');
  }
  for (final v in _pluginLoaderValues) {
    expect(stdout, contains(v), reason: 'missing --plugin-loader value "$v"');
  }
  // The shell names offered by the completion positional.
  for (final s in ['bash', 'zsh', 'fish', 'powershell']) {
    expect(stdout, contains(s), reason: 'missing shell name "$s"');
  }
}

void main() {
  group('completion bash', () {
    test('emits a valid-looking bash completion script', () async {
      final out = await runCli(['completion', 'bash']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      _expectCommonAnchors(out.stdout);
      expect(out.stdout, contains('complete -F'));
      expect(out.stdout, contains('COMPREPLY='));
    });
  });

  group('completion zsh', () {
    test('emits a #compdef header and _describe block', () async {
      final out = await runCli(['completion', 'zsh']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      _expectCommonAnchors(out.stdout);
      expect(out.stdout, startsWith('#compdef gitrinth'));
      expect(out.stdout, contains('_describe'));
      expect(out.stdout, contains('_arguments'));
    });
  });

  group('completion fish', () {
    test('emits `complete -c gitrinth` lines', () async {
      final out = await runCli(['completion', 'fish']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      _expectCommonAnchors(out.stdout);
      expect(out.stdout, contains('complete -c gitrinth'));
      expect(out.stdout, contains('__fish_use_subcommand'));
      expect(out.stdout, contains('__fish_seen_subcommand_from'));
    });
  });

  group('completion powershell', () {
    test('emits Register-ArgumentCompleter and CompletionResult', () async {
      final out = await runCli(['completion', 'powershell']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      _expectCommonAnchors(out.stdout);
      expect(out.stdout, contains('Register-ArgumentCompleter'));
      expect(out.stdout, contains('CompletionResult'));
    });

    test('pwsh alias is accepted and emits the same script', () async {
      final a = await runCli(['completion', 'powershell']);
      final b = await runCli(['completion', 'pwsh']);
      expect(b.exitCode, 0, reason: '${b.stderr}\n${b.stdout}');
      expect(b.stdout, equals(a.stdout));
    });
  });

  group('negative cases', () {
    test('missing shell argument exits 64 with usage error', () async {
      final out = await runCli(['completion']);
      expect(out.exitCode, 64);
      expect(out.stderr.toLowerCase(), contains('shell'));
    });

    test('unknown shell exits 64 with usage error', () async {
      final out = await runCli(['completion', 'csh']);
      expect(out.exitCode, 64);
      expect(out.stderr, contains('csh'));
    });

    test('extra positional after shell exits 64', () async {
      final out = await runCli(['completion', 'bash', 'extra']);
      expect(out.exitCode, 64);
      expect(out.stderr.toLowerCase(), contains('unexpected'));
    });
  });
}
