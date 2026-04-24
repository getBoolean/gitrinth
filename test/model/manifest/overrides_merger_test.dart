import 'package:gitrinth/src/model/manifest/mods_overrides.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/overrides_merger.dart';
import 'package:test/test.dart';

void main() {
  ModsYaml base() => ModsYaml(
    slug: 'pack',
    name: 'Pack',
    version: '0.1.0',
    description: 'x',
    loader: const LoaderConfig(mods: Loader.neoforge),
    mcVersion: '1.21.1',
    mods: {
      'jei': const ModEntry(slug: 'jei', constraintRaw: '^19.0.0'),
      'create': const ModEntry(slug: 'create', constraintRaw: '^6.0.0'),
    },
  );

  test('overrides win over matching entries (in-file overrides)', () {
    final m = base();
    final withOv = ModsYaml(
      slug: m.slug,
      name: m.name,
      version: m.version,
      description: m.description,
      loader: m.loader,
      mcVersion: m.mcVersion,
      mods: m.mods,
      overrides: {
        'jei': const ModEntry(slug: 'jei', constraintRaw: '19.27.0.340'),
      },
    );
    final out = applyOverrides(withOv, const ModsOverrides());
    expect(out.mods['jei']!.constraintRaw, '19.27.0.340');
    expect(out.mods['create']!.constraintRaw, '^6.0.0');
  });

  test('standalone mods_overrides.yaml wins on conflicts', () {
    final m = base();
    final withOv = ModsYaml(
      slug: m.slug,
      name: m.name,
      version: m.version,
      description: m.description,
      loader: m.loader,
      mcVersion: m.mcVersion,
      mods: m.mods,
      overrides: {'jei': const ModEntry(slug: 'jei', constraintRaw: '19.0.0')},
    );
    final extra = ModsOverrides(
      overrides: {
        'jei': const ModEntry(slug: 'jei', constraintRaw: '19.27.0.340'),
      },
    );
    final out = applyOverrides(withOv, extra);
    expect(out.mods['jei']!.constraintRaw, '19.27.0.340');
  });

  test('source override redirects entry to a local path', () {
    final m = base();
    final extra = ModsOverrides(
      overrides: {
        'create': const ModEntry(
          slug: 'create',
          source: PathEntrySource(path: './mods/dev.jar'),
        ),
      },
    );
    final out = applyOverrides(m, extra);
    expect(out.mods['create']!.source, isA<PathEntrySource>());
    expect(
      (out.mods['create']!.source as PathEntrySource).path,
      './mods/dev.jar',
    );
  });
}
