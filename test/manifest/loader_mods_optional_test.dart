import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

void main() {
  group('loader.mods is optional', () {
    test(
      'omitting loader.mods defaults to ModLoader.vanilla / null version',
      () {
        const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  plugins: paper
mc-version: 1.21.1
''';
        final m = parseModsYaml(yaml, filePath: 'mods.yaml');
        expect(m.loader.mods, ModLoader.vanilla);
        expect(m.loader.modsLoaderVersion, isNull);
        expect(m.loader.hasModRuntime, isFalse);
      },
    );

    test('omitting loader: entirely is also vanilla', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
mc-version: 1.21.1
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.loader.mods, ModLoader.vanilla);
      expect(m.loader.hasModRuntime, isFalse);
    });

    test('explicit `mods: vanilla` is accepted (no version tag)', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: vanilla
mc-version: 1.21.1
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.loader.mods, ModLoader.vanilla);
      expect(m.loader.modsLoaderVersion, isNull);
    });

    test('explicit `mods: vanilla:something` is rejected (no version tag)', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: vanilla:1.0
mc-version: 1.21.1
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('vanilla'),
          ),
        ),
      );
    });

    test('mods: section non-empty but loader.mods unset → parse error', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  plugins: paper
mc-version: 1.21.1
mods:
  sodium: release
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            allOf(contains('mods:'), contains('loader.mods is not set')),
          ),
        ),
      );
    });

    test('vanilla pack with empty mods: section parses cleanly', () {
      const yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  plugins: paper
mc-version: 1.21.1
mods:
plugins:
  luckperms: release
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.loader.mods, ModLoader.vanilla);
      expect(m.plugins.containsKey('luckperms'), isTrue);
    });
  });

  group('LoaderConfig roundtrip with vanilla', () {
    test('LoaderConfig(mods: vanilla, modsLoaderVersion: null) constructs', () {
      const cfg = LoaderConfig(
        mods: ModLoader.vanilla,
        modsLoaderVersion: null,
        plugins: PluginLoader.spongevanilla,
      );
      expect(cfg.hasModRuntime, isFalse);
      expect(cfg.plugins, PluginLoader.spongevanilla);
    });

    test('PluginLoader.toDeclared() round-trips Sponge variants to sponge', () {
      expect(
        PluginLoader.spongeforge.toDeclared(),
        DeclaredPluginLoader.sponge,
      );
      expect(PluginLoader.spongeneo.toDeclared(), DeclaredPluginLoader.sponge);
      expect(
        PluginLoader.spongevanilla.toDeclared(),
        DeclaredPluginLoader.sponge,
      );
      expect(PluginLoader.paper.toDeclared(), DeclaredPluginLoader.paper);
      expect(PluginLoader.bukkit.toDeclared(), DeclaredPluginLoader.bukkit);
    });
  });
}
