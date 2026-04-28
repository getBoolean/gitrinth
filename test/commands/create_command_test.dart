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
      'scaffolds with defaults when loader flags and --mc-version omitted',
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

    test('--mod-loader vanilla scaffolds without seeded mods entry', () async {
      final target = p.join(tempRoot.path, 'vanilla_pack');
      final out = await runCli([
        'create',
        '--mod-loader',
        'vanilla',
        '--offline',
        target,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('mods: vanilla'));
      // Strip the seeded `globalpacks` entry for vanilla.
      expect(mods, isNot(contains('globalpacks')));
      expect(
        mods,
        contains(RegExp(r'^mods:\s*\n', multiLine: true)),
        reason: 'expected a blank `mods:` header to remain',
      );

      // Parser round-trip still succeeds.
      final parsed = parseModsYaml(mods, filePath: 'mods.yaml');
      expect(parsed.loader.mods, ModLoader.vanilla);
      expect(parsed.mods, isEmpty);
    });

    test('--mod-loader accepts docker-style <name>:<tag>', () async {
      final target = p.join(tempRoot.path, 'tagged_pack');
      final out = await runCli([
        'create',
        '--mod-loader',
        'neoforge:21.1.50',
        '--offline',
        target,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      // Quote tags with `:`.
      expect(mods, contains('mods: "neoforge:21.1.50"'));

      // Parser round-trip still succeeds.
      final parsed = parseModsYaml(mods, filePath: 'mods.yaml');
      expect(parsed.loader.mods, ModLoader.neoforge);
      expect(parsed.loader.modLoaderVersion, '21.1.50');
    });

    test('--mod-loader rejects vanilla with a tag', () async {
      final target = p.join(tempRoot.path, 'bogus_vanilla');
      final out = await runCli([
        'create',
        '--mod-loader',
        'vanilla:1.0',
        '--offline',
        target,
      ], environment: env());
      expect(out.exitCode, 2);
      expect(
        out.stderr + out.stdout,
        allOf(contains('--mod-loader'), contains('vanilla')),
      );
    });

    test('--mod-loader and --mc-version override the defaults', () async {
      final target = p.join(tempRoot.path, 'custom_pack');
      final out = await runCli([
        'create',
        '--mod-loader',
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
      '--plugin-loader scaffolds plugin-only pack with commented mod loader',
      () async {
        final target = p.join(tempRoot.path, 'plugin_pack');
        final out = await runCli([
          'create',
          '--plugin-loader',
          'paper:187',
          '--offline',
          target,
        ], environment: env());
        expect(out.exitCode, 0, reason: out.stderr);

        final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
        expect(mods, contains('# mods: neoforge'));
        expect(
          mods,
          isNot(contains(RegExp(r'^\s+mods: neoforge$', multiLine: true))),
        );
        expect(mods, contains('plugins: "paper:187"'));
        expect(mods, isNot(contains('globalpacks')));

        final parsed = parseModsYaml(mods, filePath: 'mods.yaml');
        expect(parsed.loader.mods, ModLoader.vanilla);
        expect(parsed.loader.modLoaderVersion, isNull);
        expect(parsed.loader.plugins, PluginLoader.paper);
        expect(parsed.loader.pluginLoaderVersion, '187');
        expect(parsed.mods, isEmpty);
      },
    );

    test('--mod-loader and --plugin-loader can be combined', () async {
      final target = p.join(tempRoot.path, 'hybrid_pack');
      final out = await runCli([
        'create',
        '--mod-loader',
        'forge',
        '--plugin-loader',
        'sponge:stable',
        '--offline',
        target,
      ], environment: env());
      expect(out.exitCode, 0, reason: out.stderr);

      final mods = File(p.join(target, 'mods.yaml')).readAsStringSync();
      expect(mods, contains('mods: forge'));
      expect(mods, contains('plugins: "sponge:stable"'));

      final parsed = parseModsYaml(mods, filePath: 'mods.yaml');
      expect(parsed.loader.mods, ModLoader.forge);
      expect(parsed.loader.plugins, PluginLoader.spongeforge);
      expect(parsed.loader.pluginLoaderVersion, 'stable');
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

    test('rejects --mod-loader value outside the mod loader set', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--mod-loader',
        'sponge',
        target,
      ], environment: env());
      // Shared loader parsing reports ValidationError here.
      expect(out.exitCode, 2);
      expect(
        out.stderr + out.stdout,
        allOf(contains('--mod-loader'), contains('sponge')),
      );
    });

    test('old --loader option is rejected', () async {
      final target = p.join(tempRoot.path, 'pack_dir');
      final out = await runCli([
        'create',
        '--loader',
        'fabric',
        target,
      ], environment: env());
      expect(out.exitCode, 64);
      expect(out.stderr + out.stdout, contains('--loader'));
    });

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
        // Capture the URL before stopping the server.
        final stoppedEnv = {'GITRINTH_MODRINTH_URL': modrinth.baseUrl};
        await modrinth.stop();
        final target = p.join(tempRoot.path, 'fresh_pack');
        final out = await runCli(['create', target], environment: stoppedEnv);
        expect(out.exitCode, 0, reason: out.stderr);
        expect(out.stderr, contains('warning:'));
        expect(out.stderr, contains('Could not validate slug'));
        expect(File(p.join(target, 'mods.yaml')).existsSync(), isTrue);

        // Restart for tearDown.
        modrinth = FakeModrinth();
        await modrinth.start();
      });
    });
  });
}
