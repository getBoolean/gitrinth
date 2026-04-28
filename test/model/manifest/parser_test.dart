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
      expect(m.loader.mods, ModLoader.neoforge);
      expect(m.loader.shaders, isNull);
      expect(m.mcVersion, '1.21.1');
      expect(m.mods.keys, containsAll(['create', 'jei', 'iris']));
      expect(m.mods['create']!.constraintRaw, '^6.0.10+mc1.21.1');
      expect(m.mods['jei']!.constraintRaw, '19.27.0.340');
      expect(m.mods['iris']!.constraintRaw, isNull);
      expect(m.mods['create']!.source, isA<ModrinthEntrySource>());
    });

    test('parses long-form mod entries with per-side state + sources', () {
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
    client: required
    server: unsupported
  custom_mod:
    url: https://example.com/x.jar
  local_mod:
    path: ./mods/local.jar
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['iris']!.client, SideEnv.required);
      expect(m.mods['iris']!.server, SideEnv.unsupported);
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
      expect(m.loader.mods, ModLoader.neoforge);
      expect(m.loader.shaders, ShaderLoader.iris);
      expect(m.shaders['my-shader']!.constraintRaw, '^1.0.0');
    });

    test('parses loader.plugins: paper', () {
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
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.loader.plugins, PluginLoader.paper);
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

    test('shaders cannot declare server: required', () {
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
    server: required
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('shaders cannot declare client: unsupported', () {
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
    client: unsupported
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('legacy environment: field is rejected with a migration error', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  iris:
    version: ^1.0
    environment: client
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('removed `environment:`'),
          ),
        ),
      );
    });

    test('legacy optional: field is rejected with a migration error', () {
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
    version: ^1.0
    optional: true
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('removed `optional:`'),
          ),
        ),
      );
    });

    test('rejects entry with both sides unsupported', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  ghost:
    version: ^1.0
    client: unsupported
    server: unsupported
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('per-section defaults: mods default to required/required', () {
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
    version: ^1.0
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['jei']!.client, SideEnv.required);
      expect(m.mods['jei']!.server, SideEnv.required);
    });

    test('per-section defaults: resource_packs default to client optional, '
        'server unsupported', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
resource_packs:
  faithful: ^1.0
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.resourcePacks['faithful']!.client, SideEnv.optional);
      expect(m.resourcePacks['faithful']!.server, SideEnv.unsupported);
    });

    test('per-section defaults: data_packs default to required/required', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
data_packs:
  terralith: ^1.0
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.dataPacks['terralith']!.client, SideEnv.required);
      expect(m.dataPacks['terralith']!.server, SideEnv.required);
    });

    test('per-section defaults: shaders default to client required, '
        'server unsupported', () {
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
  comp: r5.7.1
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.shaders['comp']!.client, SideEnv.required);
      expect(m.shaders['comp']!.server, SideEnv.unsupported);
    });

    test('accepts-mc parses into a deduped List<String>', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts-mc: [1.21, 1.20.1, 1.21]
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['appleskin']!.acceptsMc, ['1.21', '1.20.1']);
    });

    test('accepts-mc defaults to empty when omitted', () {
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
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['jei']!.acceptsMc, isEmpty);
    });

    test('accepts-mc accepts scalar shorthand as a single-element list', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts-mc: 1.21
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['appleskin']!.acceptsMc, ['1.21']);
    });

    test('accepts-mc rejects a bool scalar', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts-mc: true
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts-mc accepts snapshot/pre-release tags', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts-mc: [1.21, "24w10a", "1.21-pre1", "b1.7.3"]
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['appleskin']!.acceptsMc, [
        '1.21',
        '24w10a',
        '1.21-pre1',
        'b1.7.3',
      ]);
    });

    test('accepts-mc rejects strings with invalid characters', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts-mc: ["1.21 snapshot"]
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts-mc rejects non-scalar list items', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9
    accepts-mc: [1.21, true]
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts-mc works on shaders (forcedEnvSource branch)', () {
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
  complementary-reimagined:
    version: ^5.7.1
    accepts-mc: [1.21]
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.shaders['complementary-reimagined']!.acceptsMc, ['1.21']);
    });

    test('parses per-side optional state on a long-form entry', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
mc-version: 1.21.1
mods:
  distanthorizons:
    version: beta
    client: optional
    server: optional
  sodium: ^0.6.0
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['distanthorizons']!.client, SideEnv.optional);
      expect(m.mods['distanthorizons']!.server, SideEnv.optional);
      expect(m.mods['sodium']!.client, SideEnv.required);
      expect(m.mods['sodium']!.server, SideEnv.required);
      // Long-form `version: beta` mirrors the short form: it sets the
      // channel and leaves the constraint blank.
      expect(m.mods['distanthorizons']!.constraintRaw, isNull);
      expect(m.mods['distanthorizons']!.channel, Channel.beta);
    });

    test('long-form version accepts channel tokens (release/beta/alpha)', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
mc-version: 1.21.1
mods:
  one:
    version: release
    client: required
    server: unsupported
  two:
    version: BETA
  three:
    version: '  alpha  '
''';
      final m = parseModsYaml(yaml, filePath: 'mods.yaml');
      expect(m.mods['one']!.constraintRaw, isNull);
      expect(m.mods['one']!.channel, Channel.release);
      expect(m.mods['two']!.channel, Channel.beta);
      expect(m.mods['three']!.channel, Channel.alpha);
    });

    test(
      'long-form rejects declaring channel via both version: and channel:',
      () {
        final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
mc-version: 1.21.1
mods:
  conflicted:
    version: beta
    channel: alpha
''';
        expect(
          () => parseModsYaml(yaml, filePath: 'mods.yaml'),
          throwsA(isA<ValidationError>()),
        );
      },
    );

    test('rejects non-string client/server side value', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
mc-version: 1.21.1
mods:
  jei:
    version: 19.27.0.340
    client: "yes"
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('parseProjectOverrides', () {
    test('empty file returns empty entries', () {
      final o = parseProjectOverrides('', filePath: 'project_overrides.yaml');
      expect(o.entries, isEmpty);
    });

    test('parses project_overrides map with version/path/url forms', () {
      final yaml = '''
project_overrides:
  jei:
    version: 19.27.0.340
  create:
    path: ./mods/create.jar
''';
      final o = parseProjectOverrides(yaml, filePath: 'project_overrides.yaml');
      expect(o.entries.keys, containsAll(['jei', 'create']));
      expect(o.entries['jei']!.constraintRaw, '19.27.0.340');
      expect(o.entries['create']!.source, isA<PathEntrySource>());
    });

    test('rejects deprecated overrides: key in standalone file', () {
      final yaml = '''
overrides:
  jei:
    version: 19.27.0.340
''';
      expect(
        () => parseProjectOverrides(yaml, filePath: 'project_overrides.yaml'),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains("'overrides:' was renamed") &&
                e.toString().contains('project_overrides:'),
          ),
        ),
      );
    });

    test('rejects deprecated overrides: key in mods.yaml', () {
      final yaml = '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: fabric
mc-version: 1.21.1
overrides:
  jei:
    version: 19.27.0.340
''';
      expect(
        () => parseModsYaml(yaml, filePath: 'mods.yaml'),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains("'overrides:' was renamed") &&
                e.toString().contains('project_overrides:'),
          ),
        ),
      );
    });
  });

  group('loader.mods docker-style tag', () {
    ModsYaml parse(String mods) => parseModsYaml('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: $mods
mc-version: 1.21.1
''', filePath: 'mods.yaml');

    test('bare loader name defaults the version tag to "stable"', () {
      final m = parse('fabric');
      expect(m.loader.mods, ModLoader.fabric);
      expect(m.loader.modLoaderVersion, 'stable');
    });

    test('explicit :stable parses as stable', () {
      final m = parse('fabric:stable');
      expect(m.loader.mods, ModLoader.fabric);
      expect(m.loader.modLoaderVersion, 'stable');
    });

    test('explicit :latest parses as latest', () {
      final m = parse('neoforge:latest');
      expect(m.loader.mods, ModLoader.neoforge);
      expect(m.loader.modLoaderVersion, 'latest');
    });

    test('concrete version tag parses verbatim', () {
      final m = parse('fabric:0.17.3');
      expect(m.loader.mods, ModLoader.fabric);
      expect(m.loader.modLoaderVersion, '0.17.3');
    });

    test(
      'quoted scalar with concrete tag round-trips through the YAML loader',
      () {
        final m = parse('"forge:52.0.45"');
        expect(m.loader.mods, ModLoader.forge);
        expect(m.loader.modLoaderVersion, '52.0.45');
      },
    );

    test('empty tag after colon is rejected', () {
      // Quoted because bare `fabric:` would otherwise look like a YAML
      // key with an empty value.
      expect(
        () => parse('"fabric:"'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('empty version tag'),
          ),
        ),
      );
    });

    test('multiple colons are rejected', () {
      expect(
        () => parse('"fabric:1.2.3:extra"'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('more than one'),
          ),
        ),
      );
    });

    test('unknown loader name is rejected', () {
      expect(
        () => parse('quilt:1.2.3'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('not a recognized loader'),
          ),
        ),
      );
    });
  });

  group('parseModsLock with loader version', () {
    test('reads loader.mods with embedded concrete version', () {
      const lock = '''
gitrinth-version: 0.1.0
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods: {}
resource_packs: {}
data_packs: {}
shaders: {}
''';
      final l = parseModsLock(lock, filePath: 'mods.lock');
      expect(l.loader.mods, ModLoader.fabric);
      expect(l.loader.modLoaderVersion, '0.17.3');
    });

    test('lock without :tag defaults modLoaderVersion to "stable"', () {
      const lock = '''
gitrinth-version: 0.1.0
loader:
  mods: neoforge
mc-version: 1.21.1
mods: {}
resource_packs: {}
data_packs: {}
shaders: {}
''';
      final l = parseModsLock(lock, filePath: 'mods.lock');
      expect(l.loader.mods, ModLoader.neoforge);
      expect(l.loader.modLoaderVersion, 'stable');
    });

    test('lock without plugin :tag is rejected', () {
      const lock = '''
gitrinth-version: 0.1.0
loader:
  mods: "neoforge:21.1.50"
  plugins: paper
mc-version: 1.21.1
mods: {}
resource_packs: {}
data_packs: {}
shaders: {}
plugins: {}
''';
      expect(
        () => parseModsLock(lock, filePath: 'mods.lock'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('no concrete plugin loader version'),
          ),
        ),
      );
    });

    test('reads sha1 alongside sha512 on a locked file', () {
      const lock = '''
gitrinth-version: 0.1.0
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  sodium:
    source: modrinth
    project-id: AANobbMI
    version-id: abcdef
    file:
      name: sodium-0.6.0.jar
      url: https://cdn.modrinth.com/data/AANobbMI/versions/abcdef/sodium-0.6.0.jar
      sha1: 0123456789abcdef
      sha512: deadbeef
      size: 1024
    env: both
resource_packs: {}
data_packs: {}
shaders: {}
''';
      final l = parseModsLock(lock, filePath: 'mods.lock');
      final f = l.mods['sodium']!.file!;
      expect(f.sha1, '0123456789abcdef');
      expect(f.sha512, 'deadbeef');
    });

    test('round-trips per-side state from mods.lock', () {
      const lock = '''
gitrinth-version: 0.1.0
loader:
  mods: "fabric:0.17.3"
mc-version: 1.21.1
mods:
  distanthorizons:
    source: modrinth
    version: "2.3.0-b"
    project-id: uCdwusMi
    version-id: abc123
    file:
      name: distanthorizons-2.3.0-b.jar
      sha1: deadbeef
      sha512: cafebabe
      size: 12345
    client: optional
    server: optional
resource_packs: {}
data_packs: {}
shaders: {}
''';
      final l = parseModsLock(lock, filePath: 'mods.lock');
      expect(l.mods['distanthorizons']!.client, SideEnv.optional);
      expect(l.mods['distanthorizons']!.server, SideEnv.optional);
    });
  });

  group('parseModsYaml files: section', () {
    String wrap(String filesBlock) =>
        '''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: neoforge
mc-version: 1.21.1
$filesBlock
''';

    test('parses a minimal files: entry with defaults', () {
      final m = parseModsYaml(
        wrap('''
files:
  config/sodium-options.json:
    path: ./presets/sodium-options.json
'''),
        filePath: 'mods.yaml',
      );
      final f = m.files['config/sodium-options.json']!;
      expect(f.destination, 'config/sodium-options.json');
      expect(f.sourcePath, './presets/sodium-options.json');
      expect(f.client, SideEnv.required);
      expect(f.server, SideEnv.required);
      expect(f.preserve, isFalse);
    });

    test('parses preserve: true and per-side state', () {
      final m = parseModsYaml(
        wrap('''
files:
  kubejs/server_scripts/loot.js:
    path: ./scripts/loot.js
    client: unsupported
    server: required
    preserve: true
'''),
        filePath: 'mods.yaml',
      );
      final f = m.files['kubejs/server_scripts/loot.js']!;
      expect(f.client, SideEnv.unsupported);
      expect(f.server, SideEnv.required);
      expect(f.preserve, isTrue);
    });

    test('absent files: section yields empty map', () {
      final m = parseModsYaml(wrap(''), filePath: 'mods.yaml');
      expect(m.files, isEmpty);
    });

    test('rejects missing required path:', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  config/foo.toml:
    preserve: true
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('missing required `path:`'),
          ),
        ),
      );
    });

    test('rejects unknown keys', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  config/foo.toml:
    path: ./foo.toml
    sha512: deadbeef
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('unknown key "sha512"'),
          ),
        ),
      );
    });

    test('rejects optional on client/server (deferred)', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  config/foo.toml:
    path: ./foo.toml
    client: optional
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"optional"'),
              contains('not supported on `files:`'),
            ),
          ),
        ),
      );
    });

    test('rejects both sides unsupported', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  config/foo.toml:
    path: ./foo.toml
    client: unsupported
    server: unsupported
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('would not install anywhere'),
          ),
        ),
      );
    });

    test('rejects absolute destination key', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  /etc/foo.toml:
    path: ./foo.toml
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('relative path'),
          ),
        ),
      );
    });

    test('rejects `..` segments in destination', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  ../escape.txt:
    path: ./escape.txt
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('`..` segment'),
          ),
        ),
      );
    });

    test('rejects backslash separators in destination', () {
      expect(
        () => parseModsYaml(
          wrap(r'''
files:
  config\foo.toml:
    path: ./foo.toml
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('backslashes'),
          ),
        ),
      );
    });

    test('rejects denormalized destination', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  ./config/foo.toml:
    path: ./foo.toml
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('contains an empty or `.` segment'),
          ),
        ),
      );
    });

    test('rejects non-boolean preserve', () {
      expect(
        () => parseModsYaml(
          wrap('''
files:
  config/foo.toml:
    path: ./foo.toml
    preserve: yes-please
'''),
          filePath: 'mods.yaml',
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('preserve must be a boolean'),
          ),
        ),
      );
    });
  });
}
