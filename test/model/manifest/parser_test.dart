import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseModsYaml', () {
    test('parses required fields and short-form mod entries', () {
      final yaml = '''
slug: example_pack
name: Example Pack
version: 0.1.0
description: an example
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  create: ^6.0.10+mc1.21.1
  jei: 19.27.0.340
  iris:
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.slug, 'example_pack');
      expect(m.name, 'Example Pack');
      expect(m.loader.mods, Loader.neoforge);
      expect(m.loader.shaders, isNull);
      expect(m.mcVersion, '1.21.1');
      expect(m.mods.keys, containsAll(['create', 'jei', 'iris']));
      expect(m.mods['create']!.constraintRaw, '^6.0.10+mc1.21.1');
      expect(m.mods['jei']!.constraintRaw, '19.27.0.340');
      expect(m.mods['iris']!.constraintRaw, isNull);
      expect(m.mods['create']!.source, isA<ModrinthEntrySource>());
    });

    test('parses long-form mod entries with environment + sources', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
mc-version: 1.20.1
mods:
  iris:
    version: ^1.8.12
    environment: client
  custom_mod:
    url: https://example.com/x.jar
  local_mod:
    path: ./mods/local.jar
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['iris']!.env, Environment.client);
      expect(m.mods['iris']!.constraintRaw, '^1.8.12');
      final custom = m.mods['custom_mod']!.source;
      expect(custom, isA<UrlEntrySource>());
      expect((custom as UrlEntrySource).url, 'https://example.com/x.jar');
      final local = m.mods['local_mod']!.source;
      expect(local, isA<PathEntrySource>());
      expect((local as PathEntrySource).path, './mods/local.jar');
    });

    test('rejects more than one source per entry', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: forge
mc-version: 1.21.1
mods:
  bad:
    url: https://example.com/x.jar
    path: ./mods/x.jar
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects hosted: source as deferred', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: forge
mc-version: 1.21.1
mods:
  bad:
    hosted: https://example.com
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<UserError>()),
      );
    });

    test('missing required fields fail with ValidationError', () {
      final yaml = '''
slug: pack
loader:
  mods: neoforge
mc-version: 1.21.1
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects loader outside MVP set', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: bukkit
mc-version: 1.21.1
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects scalar loader form with clean-break message', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader: neoforge
mc-version: 1.21.1
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('loader must be an object'),
              contains('scalar form is no longer supported'),
            ),
          ),
        ),
      );
    });

    test('shaders entries require loader.shaders', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
shaders:
  my-shader: ^1.0.0
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains("entries under 'shaders:'"),
              contains("loader.shaders"),
            ),
          ),
        ),
      );
    });

    test('parses loader.shaders and exposes it on ModsYaml', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
  shaders: iris
mc-version: 1.21.1
shaders:
  my-shader: ^1.0.0
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.loader.mods, Loader.neoforge);
      expect(m.loader.shaders, ShaderLoader.iris);
      expect(m.shaders['my-shader']!.constraintRaw, '^1.0.0');
    });

    test('rejects loader.plugins as deferred', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
  plugins: paper
mc-version: 1.21.1
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('plugin loader support is deferred'),
          ),
        ),
      );
    });

    test(
      'short-form channel token sets channel and leaves constraint null',
      () {
        final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  jei: beta
''';
        final m = parseModsYaml(yaml, filePath: 'mods.yaml');
        expect(m.mods['jei']!.channel, Channel.beta);
        expect(m.mods['jei']!.constraintRaw, isNull);
      },
    );

    test('short-form version constraint leaves channel null', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  jei: ^1.8
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['jei']!.channel, isNull);
      expect(m.mods['jei']!.constraintRaw, '^1.8');
    });

    test('long-form accepts both version and channel', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  jei:
    version: ^1.8
    channel: beta
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['jei']!.constraintRaw, '^1.8');
      expect(m.mods['jei']!.channel, Channel.beta);
    });

    test('unknown channel token raises scoped ValidationError', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  jei:
    version: ^1.8
    channel: nightly
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('jei'),
          ),
        ),
      );
    });

    test('shaders entries cannot declare environment', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
  shaders: iris
mc-version: 1.21.1
shaders:
  my-shader:
    version: ^1.0.0
    environment: server
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('parseModsOverrides', () {
    test('empty file returns empty overrides', () {
      final o = parseModsOverrides('', filePath: 'mods_overrides.yaml');
      expect(o.overrides, isEmpty);
    });

    test('parses overrides map with version/path/url forms', () {
      final yaml = '''
overrides:
  jei:
    version: 19.27.0.340
  create:
    path: ./mods/create.jar
''';
      final o = parseModsOverrides(yaml, filePath: 'mods_overrides.yaml');
      expect(o.overrides.keys, containsAll(['jei', 'create']));
      expect(o.overrides['jei']!.constraintRaw, '19.27.0.340');
      expect(o.overrides['create']!.source, isA<PathEntrySource>());
    });
  });
}
