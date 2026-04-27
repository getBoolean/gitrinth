import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';

void main() {
  group('PluginLoaderTraits.runsServerMods', () {
    test('only sponge runs server-side mods', () {
      expect(PluginLoader.bukkit.runsServerMods, isFalse);
      expect(PluginLoader.folia.runsServerMods, isFalse);
      expect(PluginLoader.paper.runsServerMods, isFalse);
      expect(PluginLoader.spigot.runsServerMods, isFalse);
      expect(PluginLoader.spongeforge.runsServerMods, isTrue);
      expect(PluginLoader.spongeneo.runsServerMods, isTrue);
      expect(PluginLoader.spongevanilla.runsServerMods, isFalse);
    });
  });

  group('PluginLoaderTraits.modrinthLoaderToken', () {
    test('non-sponge loaders use their enum name', () {
      for (final loader in const [
        PluginLoader.bukkit,
        PluginLoader.folia,
        PluginLoader.paper,
        PluginLoader.spigot,
      ]) {
        expect(
          loader.modrinthLoaderToken,
          loader.name,
          reason: '${loader.name} should query Modrinth as itself',
        );
      }
    });

    test('all sponge variants collapse to the "sponge" Modrinth token', () {
      for (final loader in const [
        PluginLoader.spongeforge,
        PluginLoader.spongeneo,
        PluginLoader.spongevanilla,
      ]) {
        expect(
          loader.modrinthLoaderToken,
          'sponge',
          reason:
              '${loader.name} plugins are tagged with loaders:[sponge] on '
              'Modrinth — querying with the variant name returns nothing',
        );
      }
    });
  });

  group('PluginLoaderTraits.compatibleModLoaders', () {
    test('paper/folia/bukkit/spigot accept any mod loader (empty set)', () {
      for (final loader in const [
        PluginLoader.paper,
        PluginLoader.folia,
        PluginLoader.bukkit,
        PluginLoader.spigot,
      ]) {
        expect(
          loader.compatibleModLoaders,
          isEmpty,
          reason: '${loader.name} should not constrain loader.mods',
        );
      }
    });

    test('spongeforge requires forge or neoforge', () {
      expect(
        PluginLoader.spongeforge.compatibleModLoaders,
        equals({ModLoader.forge, ModLoader.neoforge}),
      );
    });

    test('spongeneo requires forge or neoforge', () {
      expect(
        PluginLoader.spongeneo.compatibleModLoaders,
        equals({ModLoader.forge, ModLoader.neoforge}),
      );
    });
  });
}
