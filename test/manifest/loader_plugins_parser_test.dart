import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

void main() {
  String yamlWithLoaderPlugins(
    String pluginsValue, {
    String mods = 'neoforge',
  }) =>
      '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: $mods
  plugins: $pluginsValue
mc-version: 1.21.1
''';

  group('loader.plugins parsing', () {
    test('accepts every documented value', () {
      for (final v in const ['paper', 'folia', 'bukkit', 'spigot']) {
        final manifest = parseModsYaml(
          yamlWithLoaderPlugins(v),
          filePath: 'mods.yaml',
        );
        expect(manifest.loader.plugins?.name, v);
      }
      // `sponge` resolves to a concrete distribution based on `loader.mods`.
      final manifest = parseModsYaml(
        yamlWithLoaderPlugins('sponge', mods: 'forge'),
        filePath: 'mods.yaml',
      );
      expect(manifest.loader.plugins, PluginLoader.spongeforge);
    });

    test('rejects an unknown value with a message listing every loader', () {
      try {
        parseModsYaml(yamlWithLoaderPlugins('bogus'), filePath: 'mods.yaml');
        fail('expected a parse error');
      } on ValidationError catch (e) {
        expect(e.message, contains('bukkit'));
        expect(e.message, contains('folia'));
        expect(e.message, contains('paper'));
        expect(e.message, contains('spigot'));
        expect(e.message, contains('sponge'));
      }
    });

    test('rejects a non-empty plugins: section with no loader.plugins', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
plugins:
  luckperms:
''';
      try {
        parseModsYaml(yaml, filePath: 'mods.yaml');
        fail('expected a parse error');
      } on ValidationError catch (e) {
        expect(e.message, contains('loader.plugins'));
        expect(e.message, contains('plugins:'));
      }
    });

    test('sponge + fabric resolves to spongevanilla', () {
      final manifest = parseModsYaml(
        yamlWithLoaderPlugins('sponge', mods: 'fabric'),
        filePath: 'mods.yaml',
      );
      expect(manifest.loader.plugins, PluginLoader.spongevanilla);
    });

    test('sponge + neoforge resolves to spongeneo', () {
      final manifest = parseModsYaml(
        yamlWithLoaderPlugins('sponge', mods: 'neoforge'),
        filePath: 'mods.yaml',
      );
      expect(manifest.loader.plugins, PluginLoader.spongeneo);
    });

    test('the old spongeforge spelling is rejected as unknown', () {
      try {
        parseModsYaml(
          yamlWithLoaderPlugins('spongeforge', mods: 'forge'),
          filePath: 'mods.yaml',
        );
        fail('expected a parse error');
      } on ValidationError catch (e) {
        expect(e.message, contains('spongeforge'));
        expect(e.message, contains('not recognized'));
        expect(e.message, contains('sponge'));
      }
    });
  });

  group('Section.plugins behavior', () {
    test(
      'defaultSidesFor(plugins) is client: unsupported, server: required',
      () {
        final sides = defaultSidesFor(Section.plugins);
        expect(sides.client, SideEnv.unsupported);
        expect(sides.server, SideEnv.required);
      },
    );

    test('mods entry under loader.plugins: paper is coerced to '
        'server-unsupported regardless of declared value', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
  plugins: paper
mc-version: 1.21.1
mods:
  sodium:
    version: ^1.0.0
    client: required
    server: required
''';
      final manifest = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(manifest.mods['sodium']!.server, SideEnv.unsupported);
      expect(manifest.mods['sodium']!.client, SideEnv.required);
    });

    test('mods entry under sponge + forge (resolved spongeforge) keeps its '
        'declared server value (spongeforge is exempt)', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: forge
  plugins: sponge
mc-version: 1.21.1
mods:
  sodium:
    version: ^1.0.0
    client: required
    server: required
''';
      final manifest = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(manifest.mods['sodium']!.server, SideEnv.required);
    });

    test('plugins entry must have a server side that is not unsupported', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
  plugins: paper
mc-version: 1.21.1
plugins:
  luckperms:
    version: ^5.0.0
    client: unsupported
    server: unsupported
''';
      try {
        parseModsYaml(yaml, filePath: 'mods.yaml');
        fail('expected a parse error');
      } on ValidationError {
        // ok
      }
    });
  });
}
