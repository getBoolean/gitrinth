import 'package:test/test.dart';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/section_inference.dart';

void main() {
  group('inferSectionFromProject', () {
    test('resourcepack -> resource_packs', () {
      expect(
        inferSectionFromProject(projectType: 'resourcepack', loaders: const []),
        Section.resourcePacks,
      );
    });

    test('shader -> shaders', () {
      expect(
        inferSectionFromProject(projectType: 'shader', loaders: const ['iris']),
        Section.shaders,
      );
    });

    test('datapack -> data_packs', () {
      expect(
        inferSectionFromProject(
          projectType: 'datapack',
          loaders: const ['datapack'],
        ),
        Section.dataPacks,
      );
    });

    test('mod with mod loaders -> mods', () {
      expect(
        inferSectionFromProject(
          projectType: 'mod',
          loaders: const ['neoforge'],
        ),
        Section.mods,
      );
      expect(
        inferSectionFromProject(projectType: 'mod', loaders: const ['fabric']),
        Section.mods,
      );
    });

    test(
      'mod whose only loader is datapack -> data_packs (terralith case)',
      () {
        expect(
          inferSectionFromProject(
            projectType: 'mod',
            loaders: const ['datapack'],
          ),
          Section.dataPacks,
        );
      },
    );

    test('mod with empty loaders falls back to mods', () {
      expect(
        inferSectionFromProject(projectType: 'mod', loaders: const []),
        Section.mods,
      );
    });

    test('mod with mixed loaders (datapack + mod loader) -> mods', () {
      expect(
        inferSectionFromProject(
          projectType: 'mod',
          loaders: const ['datapack', 'fabric'],
        ),
        Section.mods,
      );
    });

    test('modpack throws ValidationError', () {
      expect(
        () =>
            inferSectionFromProject(projectType: 'modpack', loaders: const []),
        throwsA(isA<ValidationError>()),
      );
    });

    test('plugin throws ValidationError (deferred post-MVP)', () {
      expect(
        () => inferSectionFromProject(projectType: 'plugin', loaders: const []),
        throwsA(isA<ValidationError>()),
      );
    });

    test('unknown project_type throws ValidationError', () {
      expect(
        () => inferSectionFromProject(
          projectType: 'something',
          loaders: const [],
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('project_type matching is case-insensitive', () {
      expect(
        inferSectionFromProject(
          projectType: 'Mod',
          loaders: const ['neoforge'],
        ),
        Section.mods,
      );
      expect(
        inferSectionFromProject(projectType: 'ResourcePack', loaders: const []),
        Section.resourcePacks,
      );
    });
  });

  group('inferSectionFromFilename', () {
    test('.jar -> mods (via extension)', () {
      expect(inferSectionFromFilename('foo.jar'), Section.mods);
      expect(inferSectionFromFilename('./mods/foo.jar'), Section.mods);
      expect(
        inferSectionFromFilename('https://example.com/a/b/foo.jar'),
        Section.mods,
      );
    });

    test('.jar in URL with query/fragment still lands on mods', () {
      expect(
        inferSectionFromFilename('https://example.com/foo.jar?x=1'),
        Section.mods,
      );
      expect(
        inferSectionFromFilename('https://example.com/foo.jar#frag'),
        Section.mods,
      );
    });

    test('.zip with no stronger signal is ambiguous', () {
      expect(inferSectionFromFilename('pack.zip'), isNull);
      expect(inferSectionFromFilename('./packs/pack.zip'), isNull);
    });

    test('empty string returns null', () {
      expect(inferSectionFromFilename(''), isNull);
    });

    test('unknown extension returns null', () {
      expect(inferSectionFromFilename('mystery.xyz'), isNull);
    });
  });
}
