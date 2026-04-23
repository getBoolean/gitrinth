import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_create_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('create', () {
    test('scaffolds with defaults when --loader/--mc-version omitted', () async {
      final target = p.join(tempRoot.path, 'example_modpack');
      final out = await runCli(['create', target]);

      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('slug: example_modpack'));
      expect(mods, contains('name: example_modpack'));
      expect(mods, contains('loader:'));
      expect(mods, contains('mods: neoforge'));
      expect(mods, contains('mc-version: 1.21.1'));
      expect(mods, contains('tooling:'));

      expect(File(p.join(target, 'README.md')).existsSync(), isTrue);
      expect(File(p.join(target, '.gitignore')).existsSync(), isTrue);
      expect(File(p.join(target, '.modrinth_ignore')).existsSync(), isTrue);
    });

    test('--loader and --mc-version override the defaults', () async {
      final target = p.join(tempRoot.path, 'custom_pack');
      final out = await runCli([
        'create',
        '--loader', 'fabric',
        '--mc-version', '1.20.1',
        target,
      ]);
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('mods: fabric'));
      expect(mods, contains('mc-version: 1.20.1'));
    });

    test('derives slug from directory basename (hyphens -> underscores)', () async {
      final target = p.join(tempRoot.path, 'my-cool-pack');
      final out = await runCli(['create', target]);
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('slug: my_cool_pack'));
    });

    test('--slug overrides derived slug; --name overrides display name', () async {
      final target = p.join(tempRoot.path, 'dir_name');
      final out = await runCli([
        'create',
        '--slug', 'override_slug',
        '--name', 'Override',
        target,
      ]);
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('slug: override_slug'));
      expect(mods, contains('name: Override'));
    });

    test('rejects invalid slug with ValidationError (exit 2)', () async {
      final target = p.join(tempRoot.path, 'Bad-Slug');
      final out = await runCli([
        'create',
        '--slug', 'BAD_SLUG',
        target,
      ]);
      expect(out.exitCode, 2);
      expect(out.stderr, contains('Invalid slug'));
    });

    test('rejects invalid --mc-version with ValidationError', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--mc-version', 'not-a-version',
        target,
      ]);
      expect(out.exitCode, 2);
      expect(out.stderr, contains('Invalid --mc-version'));
    });

    test('rejects --loader value outside the MVP set (args usage error)', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--loader', 'sponge',
        target,
      ]);
      expect(out.exitCode, 64);
    });

    test('missing <directory> exits 64', () async {
      final out = await runCli(['create']);
      expect(out.exitCode, 64);
    });

    test('refuses non-empty target dir without --force', () async {
      final target = Directory(p.join(tempRoot.path, 'existing'))..createSync();
      File(p.join(target.path, 'other.txt')).writeAsStringSync('hi');

      final out = await runCli(['create', target.path]);
      expect(out.exitCode, 1);
      expect(out.stderr, contains('non-empty directory'));
    });

    test('--force scaffolds into non-empty dir', () async {
      final target = Directory(p.join(tempRoot.path, 'existing'))..createSync();
      File(p.join(target.path, 'other.txt')).writeAsStringSync('hi');

      final out = await runCli(['create', '--force', target.path]);
      expect(out.exitCode, 0, reason: out.stderr);
      expect(File(p.join(target.path, 'mods.yaml')).existsSync(), isTrue);
      expect(File(p.join(target.path, 'other.txt')).existsSync(), isTrue);
    });
  });
}
