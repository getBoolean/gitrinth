import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/entry_lookup.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';

ModsYaml _manifest({
  Map<String, ModEntry> mods = const {},
  Map<String, ModEntry> resourcePacks = const {},
  Map<String, ModEntry> dataPacks = const {},
  Map<String, ModEntry> shaders = const {},
}) => ModsYaml(
  slug: 'pack',
  name: 'pack',
  version: '0.1.0',
  description: '',
  loader: const LoaderConfig(mods: ModLoader.fabric),
  mcVersion: '1.21',
  mods: mods,
  resourcePacks: resourcePacks,
  dataPacks: dataPacks,
  shaders: shaders,
);

void main() {
  group('resolveEntry', () {
    test('returns the single hit when slug exists in one section', () {
      final manifest = _manifest(
        mods: const {'jei': ModEntry(slug: 'jei', constraintRaw: '^1.0.0')},
      );
      final hit = resolveEntry(manifest, slug: 'jei');
      expect(hit.section, Section.mods);
      expect(hit.entry.slug, 'jei');
    });

    test('throws when slug is not present', () {
      final manifest = _manifest();
      expect(
        () => resolveEntry(manifest, slug: 'missing'),
        throwsA(isA<UserError>()),
      );
    });

    test('throws when slug exists in multiple sections, names them', () {
      final manifest = _manifest(
        mods: const {'foo': ModEntry(slug: 'foo', constraintRaw: '^1.0.0')},
        dataPacks: const {
          'foo': ModEntry(slug: 'foo', constraintRaw: '^2.0.0'),
        },
      );
      expect(
        () => resolveEntry(manifest, slug: 'foo'),
        throwsA(
          isA<UserError>()
              .having((e) => e.message, 'message', contains('mods'))
              .having((e) => e.message, 'message', contains('dataPacks'))
              .having((e) => e.message, 'message', contains('--type')),
        ),
      );
    });

    test('restricts to preferredSection when provided', () {
      final manifest = _manifest(
        mods: const {'foo': ModEntry(slug: 'foo', constraintRaw: '^1.0.0')},
        dataPacks: const {
          'foo': ModEntry(slug: 'foo', constraintRaw: '^2.0.0'),
        },
      );
      final hit = resolveEntry(
        manifest,
        slug: 'foo',
        preferredSection: Section.dataPacks,
      );
      expect(hit.section, Section.dataPacks);
      expect(hit.entry.constraintRaw, '^2.0.0');
    });

    test('throws when preferredSection does not contain the slug', () {
      final manifest = _manifest(
        mods: const {'foo': ModEntry(slug: 'foo', constraintRaw: '^1.0.0')},
      );
      expect(
        () => resolveEntry(
          manifest,
          slug: 'foo',
          preferredSection: Section.shaders,
        ),
        throwsA(isA<UserError>()),
      );
    });
  });
}
