import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';

void main() {
  ModEntry mod({
    SideEnv client = SideEnv.required,
    SideEnv server = SideEnv.required,
  }) => ModEntry(slug: 'sodium', client: client, server: server);

  group('coerceModsForPluginLoader', () {
    test('returns input unchanged when no plugin loader is set', () {
      final input = {'sodium': mod()};
      expect(coerceModsForPluginLoader(input, null), same(input));
    });

    test(
      'returns input unchanged under spongeforge (mods keep per-side state)',
      () {
        final input = {'sodium': mod()};
        final out = coerceModsForPluginLoader(input, PluginLoader.spongeforge);
        expect(out, same(input));
      },
    );

    test(
      'returns input unchanged under spongeneo (mods keep per-side state)',
      () {
        final input = {'sodium': mod()};
        final out = coerceModsForPluginLoader(input, PluginLoader.spongeneo);
        expect(out, same(input));
      },
    );

    test('forces server: unsupported under paper', () {
      final input = {'sodium': mod()};
      final out = coerceModsForPluginLoader(input, PluginLoader.paper);
      expect(out['sodium']!.server, SideEnv.unsupported);
      expect(out['sodium']!.client, SideEnv.required);
    });

    test('forces server: unsupported under folia/bukkit/spigot', () {
      for (final loader in const [
        PluginLoader.folia,
        PluginLoader.bukkit,
        PluginLoader.spigot,
      ]) {
        final input = {
          'sodium': mod(client: SideEnv.optional, server: SideEnv.required),
        };
        final out = coerceModsForPluginLoader(input, loader);
        expect(
          out['sodium']!.server,
          SideEnv.unsupported,
          reason: '${loader.name} should coerce server to unsupported',
        );
        expect(out['sodium']!.client, SideEnv.optional);
      }
    });

    test('preserves client when coercing', () {
      final input = {
        'sodium': mod(client: SideEnv.optional, server: SideEnv.required),
      };
      final out = coerceModsForPluginLoader(input, PluginLoader.paper);
      expect(out['sodium']!.client, SideEnv.optional);
    });
  });
}
