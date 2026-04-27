import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

void main() {
  String yaml({required String mods, required String plugins}) =>
      '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: $mods
  plugins: $plugins
mc-version: 1.21.1
''';

  String yamlNoMods({required String plugins}) =>
      '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  plugins: $plugins
mc-version: 1.21.1
''';

  group('DeclaredPluginLoader resolution truth table', () {
    test('bukkit / folia / paper / spigot pass through any mods loader', () {
      for (final declared in const ['bukkit', 'folia', 'paper', 'spigot']) {
        for (final mods in const ['forge', 'fabric', 'neoforge']) {
          final m = parseModsYaml(
            yaml(mods: mods, plugins: declared),
            filePath: 'mods.yaml',
          );
          expect(m.loader.plugins?.name, declared, reason: '$declared/$mods');
        }
      }
    });

    test('sponge + forge → spongeforge', () {
      final m = parseModsYaml(
        yaml(mods: 'forge', plugins: 'sponge'),
        filePath: 'mods.yaml',
      );
      expect(m.loader.plugins, PluginLoader.spongeforge);
    });

    test('sponge + neoforge → spongeneo', () {
      final m = parseModsYaml(
        yaml(mods: 'neoforge', plugins: 'sponge'),
        filePath: 'mods.yaml',
      );
      expect(m.loader.plugins, PluginLoader.spongeneo);
    });

    test('sponge + fabric → spongevanilla', () {
      final m = parseModsYaml(
        yaml(mods: 'fabric', plugins: 'sponge'),
        filePath: 'mods.yaml',
      );
      expect(m.loader.plugins, PluginLoader.spongevanilla);
    });

    test('sponge + omitted loader.mods → spongevanilla', () {
      final m = parseModsYaml(
        yamlNoMods(plugins: 'sponge'),
        filePath: 'mods.yaml',
      );
      expect(m.loader.plugins, PluginLoader.spongevanilla);
      expect(m.loader.mods, ModLoader.vanilla);
    });

    test('sponge + fabric coerces fabric mods to server-unsupported '
        '(spongevanilla is a pure plugin server)', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
  plugins: sponge
mc-version: 1.21.1
mods:
  sodium:
    version: ^1.0.0
    client: required
    server: required
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.loader.plugins, PluginLoader.spongevanilla);
      expect(m.mods['sodium']!.server, SideEnv.unsupported);
      expect(m.mods['sodium']!.client, SideEnv.required);
    });
  });
}
