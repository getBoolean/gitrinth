import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  late Directory tempRoot;
  late FakeModrinth modrinth;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_create_');
    modrinth = FakeModrinth();
    await modrinth.start();
  });

  tearDown(() async {
    await modrinth.stop();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Map<String, String> env() => {'GITRINTH_MODRINTH_URL': modrinth.baseUrl};

  group('create', () {
    test(
      'scaffolds with defaults when --loader/--mc-version omitted',
      () async {
        final target = p.join(tempRoot.path, 'example_modpack');
        final out = await runCli(['create', target], environment: env());

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
      },
    );

    test('--loader vanilla scaffolds without the seeded mods entry', () async {
      final target = p.join(tempRoot.path, 'vanilla_pack');
      final out = await runCli([
        'create',
        '--loader',
        'vanilla',
        '--offline',
        target,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('mods: vanilla'));
      // The default template seeds `globalpacks: stable` under `mods:`.
      // Under vanilla that would be a parse error, so it must be
      // stripped — and an empty `mods:` header is left in its place.
      expect(mods, isNot(contains('globalpacks')));
      expect(
        mods,
        contains(RegExp(r'^mods:\s*\n', multiLine: true)),
        reason: 'expected a blank `mods:` header to remain',
      );

      // Sanity: the scaffold round-trips through the parser without
      // tripping the "mods entries require a real loader" rule.
      final parsed = parseModsYaml(mods, filePath: 'mods.yaml');
      expect(parsed.loader.mods, ModLoader.vanilla);
      expect(parsed.mods, isEmpty);
    });

    test('--loader accepts docker-style <name>:<tag>', () async {
      final target = p.join(tempRoot.path, 'tagged_pack');
      final out = await runCli([
        'create',
        '--loader',
        'neoforge:21.1.50',
        '--offline',
        target,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      // Tag must be quoted in yaml so the embedded `:` doesn't get
      // read as a nested mapping.
      expect(mods, contains('mods: "neoforge:21.1.50"'));

      // Round-trips through the parser.
      final parsed = parseModsYaml(mods, filePath: 'mods.yaml');
      expect(parsed.loader.mods, ModLoader.neoforge);
      expect(parsed.loader.modsVersion, '21.1.50');
    });

    test('--loader rejects vanilla with a tag', () async {
      final target = p.join(tempRoot.path, 'bogus_vanilla');
      final out = await runCli([
        'create',
        '--loader',
        'vanilla:1.0',
        '--offline',
        target,
      ], environment: env());
      expect(out.exitCode, 2);
      expect(
        out.stderr + out.stdout,
        allOf(contains('--loader'), contains('vanilla')),
      );
    });

    test('--loader and --mc-version override the defaults', () async {
      final target = p.join(tempRoot.path, 'custom_pack');
      final out = await runCli([
        'create',
        '--loader',
        'fabric',
        '--mc-version',
        '1.20.1',
        target,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('mods: fabric'));
      expect(mods, contains('mc-version: 1.20.1'));
    });

    test(
      'derives slug from directory basename (lowercased, hyphens preserved)',
      () async {
        final target = p.join(tempRoot.path, 'my-cool-pack');
        final out = await runCli(['create', target], environment: env());
        expect(out.exitCode, 0, reason: out.stderr);

        final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
        expect(mods, contains('slug: my-cool-pack'));
      },
    );

    test(
      '--slug overrides derived slug; --name overrides display name',
      () async {
        final target = p.join(tempRoot.path, 'dir_name');
        final out = await runCli([
          'create',
          '--slug',
          'override_slug',
          '--name',
          'Override',
          target,
        ], environment: env());
        expect(out.exitCode, 0, reason: out.stderr);

        final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
        expect(mods, contains('slug: override_slug'));
        expect(mods, contains('name: Override'));
      },
    );

    test(
      '--slug accepts uppercase letters, digits, and Modrinth-allowed chars',
      () async {
        final target = p.join(tempRoot.path, 'pack_dir');
        final out = await runCli([
          'create',
          '--slug',
          'CoolPack',
          target,
        ], environment: env());
        expect(out.exitCode, 0, reason: out.stderr);
        final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
        expect(mods, contains('slug: CoolPack'));
      },
    );

    test('--slug accepts a leading digit', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--slug',
        '1pack',
        target,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);
      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('slug: 1pack'));
    });

    test('rejects too-short slug with ValidationError (exit 2)', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--slug',
        'ab',
        target,
      ], environment: env());
      expect(out.exitCode, 2);
      expect(out.stderr, contains('Invalid slug'));
    });

    test('rejects slug with disallowed chars (exit 2)', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--slug',
        'bad slug',
        target,
      ], environment: env());
      expect(out.exitCode, 2);
      expect(out.stderr, contains('Invalid slug'));
    });

    test('rejects invalid --mc-version with ValidationError', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--mc-version',
        'not-a-version',
        target,
      ], environment: env());
      expect(out.exitCode, 2);
      expect(out.stderr, contains('Invalid --mc-version'));
    });

    test(
      'rejects --loader value outside the MVP set (validation error)',
      () async {
        final target = p.join(tempRoot.path, 'pack_dir');
        final out = await runCli([
          'create',
          '--loader',
          'sponge',
          target,
        ], environment: env());
        // Exit 2 is ValidationError; --loader runs through the shared
        // loader-ref parser (not argParser.allowed), so an unknown
        // name surfaces as a ValidationError, not a UsageError.
        expect(out.exitCode, 2);
        expect(
          out.stderr + out.stdout,
          allOf(contains('--loader'), contains('sponge')),
        );
      },
    );

    test('missing <directory> exits 64', () async {
      final out = await runCli(['create'], environment: env());
      expect(out.exitCode, 64);
    });

    test('refuses non-empty target dir without --force', () async {
      final target = Directory(p.join(tempRoot.path, 'existing'))..createSync();
      File(p.join(target.path, 'other.txt')).writeAsStringSync('hi');

      final out = await runCli(['create', target.path], environment: env());
      expect(out.exitCode, 1);
      expect(out.stderr, contains('non-empty directory'));
    });

    test('--force scaffolds into non-empty dir', () async {
      final target = Directory(p.join(tempRoot.path, 'existing'))..createSync();
      File(p.join(target.path, 'other.txt')).writeAsStringSync('hi');

      final out = await runCli([
        'create',
        '--force',
        target.path,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);
      expect(File(p.join(target.path, 'mods.yaml')).existsSync(), isTrue);
      expect(File(p.join(target.path, 'other.txt')).existsSync(), isTrue);
    });

    group('Modrinth slug-availability check', () {
      test('available slug scaffolds silently', () async {
        final target = p.join(tempRoot.path, 'fresh_pack');
        final out = await runCli(['create', target], environment: env());
        expect(out.exitCode, 0, reason: out.stderr);
        expect(out.stderr, isNot(contains('warning:')));
        expect(File(p.join(target, 'mods.yaml')).existsSync(), isTrue);
      });

      test('taken slug warns but still scaffolds', () async {
        modrinth.markSlugTaken('cool_pack');
        final target = p.join(tempRoot.path, 'cool_pack');
        final out = await runCli(['create', target], environment: env());
        expect(out.exitCode, 0, reason: out.stderr);
        expect(out.stderr, contains('warning:'));
        expect(out.stderr, contains('already taken'));
        expect(out.stderr, contains('cool_pack'));
        expect(File(p.join(target, 'mods.yaml')).existsSync(), isTrue);
      });

      test('--offline skips the check even when slug is taken', () async {
        modrinth.markSlugTaken('cool_pack');
        final target = p.join(tempRoot.path, 'cool_pack');
        final out = await runCli([
          'create',
          '--offline',
          target,
        ], environment: env());
        expect(out.exitCode, 0, reason: out.stderr);
        expect(out.stderr, isNot(contains('already taken')));
        expect(File(p.join(target, 'mods.yaml')).existsSync(), isTrue);
      });

      test('network failure warns and proceeds', () async {
        // Capture the URL before stopping — baseUrl reads `_server.port`,
        // which throws once the server is closed.
        final stoppedEnv = {'GITRINTH_MODRINTH_URL': modrinth.baseUrl};
        await modrinth.stop();
        final target = p.join(tempRoot.path, 'fresh_pack');
        final out = await runCli(['create', target], environment: stoppedEnv);
        expect(out.exitCode, 0, reason: out.stderr);
        expect(out.stderr, contains('warning:'));
        expect(out.stderr, contains('Could not validate slug'));
        expect(File(p.join(target, 'mods.yaml')).existsSync(), isTrue);

        // Restart so tearDown's stop() doesn't blow up.
        modrinth = FakeModrinth();
        await modrinth.start();
      });
    });
  });
}
