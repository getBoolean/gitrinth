import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/loader_version_resolver.dart';
import 'package:test/test.dart';

import '../helpers/fake_modrinth.dart';

void main() {
  group('LoaderVersionResolver', () {
    late FakeModrinth modrinth;
    late LoaderVersionResolver resolver;

    setUp(() async {
      modrinth = FakeModrinth();
      await modrinth.start();
      resolver = LoaderVersionResolver(
        dio: Dio(),
        fabricMetaUrl: modrinth.fabricMetaUrl,
        forgePromotionsUrl: modrinth.forgePromotionsUrl,
        forgeVersionsUrl: modrinth.forgeVersionsUrl,
        neoforgeVersionsUrl: modrinth.neoforgeVersionsUrl,
        neoforgeLegacyVersionsUrl: modrinth.neoforgeLegacyVersionsUrl,
      );
    });

    tearDown(() async {
      await modrinth.stop();
    });

    group('Forge', () {
      test('forge:stable picks `<mc>-recommended`', () async {
        final v = await resolver.resolve(
          loader: Loader.forge,
          tag: 'stable',
          mcVersion: '1.20.1',
        );
        expect(v, '47.2.0');
      });

      test('forge:latest picks `<mc>-latest`', () async {
        final v = await resolver.resolve(
          loader: Loader.forge,
          tag: 'latest',
          mcVersion: '1.20.1',
        );
        expect(v, '47.4.10');
      });

      test('forge:stable errors when only -latest exists for the MC', () async {
        modrinth.forgePromotions = {
          'promos': {'1.21-latest': '51.0.33'},
        };
        await expectLater(
          resolver.resolve(
            loader: Loader.forge,
            tag: 'stable',
            mcVersion: '1.21',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('no stable Forge build for Minecraft 1.21'),
            ),
          ),
        );
      });

      test('forge:latest succeeds when only -latest exists', () async {
        modrinth.forgePromotions = {
          'promos': {'1.21-latest': '51.0.33'},
        };
        final v = await resolver.resolve(
          loader: Loader.forge,
          tag: 'latest',
          mcVersion: '1.21',
        );
        expect(v, '51.0.33');
      });

      test('forge:stable errors when MC has no entries at all', () async {
        await expectLater(
          resolver.resolve(
            loader: Loader.forge,
            tag: 'stable',
            mcVersion: '1.99',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('no Forge build for Minecraft 1.99'),
            ),
          ),
        );
      });

      test('concrete forge tag validates via maven-metadata.json '
          'and skips promotions', () async {
        final v = await resolver.resolve(
          loader: Loader.forge,
          tag: '47.2.0',
          mcVersion: '1.20.1',
        );
        expect(v, '47.2.0');
        expect(
          modrinth.requestCounts['/forge/maven-metadata.json'] ?? 0,
          greaterThan(0),
        );
        expect(modrinth.requestCounts['/forge/promotions_slim.json'] ?? 0, 0);
      });

      test('concrete forge tag errors when build is unknown', () async {
        await expectLater(
          resolver.resolve(
            loader: Loader.forge,
            tag: '99.9.9',
            mcVersion: '1.20.1',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('not a published version for Minecraft 1.20.1'),
            ),
          ),
        );
      });

      test('concrete forge tag errors when MC version mismatched', () async {
        modrinth.forgeVersions = {
          '1.20.1': ['1.20.1-47.2.0'],
          '1.20.4': ['1.20.4-49.2.0'],
        };
        await expectLater(
          resolver.resolve(
            loader: Loader.forge,
            tag: '47.2.0',
            mcVersion: '1.20.4',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('not a published version for Minecraft 1.20.4'),
            ),
          ),
        );
      });
    });

    group('NeoForge modern', () {
      test(
        'neoforge:stable picks newest non-beta with matching prefix',
        () async {
          modrinth.neoforgeVersionsBody = {
            'isSnapshot': false,
            'versions': ['21.4.50', '21.4.99', '21.4.100-beta'],
          };
          final v = await resolver.resolve(
            loader: Loader.neoforge,
            tag: 'stable',
            mcVersion: '1.21.4',
          );
          expect(v, '21.4.99');
        },
      );

      test('neoforge:latest picks newest including -beta', () async {
        modrinth.neoforgeVersionsBody = {
          'isSnapshot': false,
          'versions': ['21.4.50', '21.4.99', '21.4.100-beta'],
        };
        final v = await resolver.resolve(
          loader: Loader.neoforge,
          tag: 'latest',
          mcVersion: '1.21.4',
        );
        expect(v, '21.4.100-beta');
      });

      test('MC 1.21 (no patch) uses prefix 21.0.', () async {
        modrinth.neoforgeVersionsBody = {
          'isSnapshot': false,
          'versions': ['21.0.10', '21.0.42', '21.1.50'],
        };
        final v = await resolver.resolve(
          loader: Loader.neoforge,
          tag: 'stable',
          mcVersion: '1.21',
        );
        expect(v, '21.0.42');
      });

      test(
        'neoforge:stable errors when only -beta builds match the MC',
        () async {
          modrinth.neoforgeVersionsBody = {
            'isSnapshot': false,
            'versions': ['21.5.1-beta', '21.5.2-beta'],
          };
          await expectLater(
            resolver.resolve(
              loader: Loader.neoforge,
              tag: 'stable',
              mcVersion: '1.21.5',
            ),
            throwsA(
              isA<UserError>().having(
                (e) => e.message,
                'message',
                contains('no stable NeoForge build for Minecraft 1.21.5'),
              ),
            ),
          );
        },
      );

      test(
        'neoforge:stable errors when no version matches MC prefix',
        () async {
          modrinth.neoforgeVersionsBody = {
            'isSnapshot': false,
            'versions': ['20.4.167', '21.1.228'],
          };
          await expectLater(
            resolver.resolve(
              loader: Loader.neoforge,
              tag: 'stable',
              mcVersion: '1.21.4',
            ),
            throwsA(
              isA<UserError>().having(
                (e) => e.message,
                'message',
                contains('no NeoForge build for Minecraft 1.21.4'),
              ),
            ),
          );
        },
      );

      test('concrete neoforge tag with valid prefix succeeds', () async {
        final v = await resolver.resolve(
          loader: Loader.neoforge,
          tag: '21.1.228',
          mcVersion: '1.21.1',
        );
        expect(v, '21.1.228');
      });

      test('concrete neoforge tag errors when prefix mismatches MC', () async {
        await expectLater(
          resolver.resolve(
            loader: Loader.neoforge,
            tag: '21.1.228',
            mcVersion: '1.21.4',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('expected version prefix `21.4.`'),
            ),
          ),
        );
      });

      test(
        'concrete neoforge tag errors when version is not in upstream list',
        () async {
          await expectLater(
            resolver.resolve(
              loader: Loader.neoforge,
              tag: '21.1.999',
              mcVersion: '1.21.1',
            ),
            throwsA(isA<UserError>()),
          );
        },
      );
    });

    group('NeoForge legacy (MC 1.20.1)', () {
      test('neoforge:stable strips 1.20.1- prefix', () async {
        final v = await resolver.resolve(
          loader: Loader.neoforge,
          tag: 'stable',
          mcVersion: '1.20.1',
        );
        expect(v, '47.1.106');
        expect(
          modrinth.requestCounts['/neoforge-legacy/versions'] ?? 0,
          greaterThan(0),
        );
        expect(modrinth.requestCounts['/neoforge/versions'] ?? 0, 0);
      });

      test('neoforge:latest returns last entry stripped', () async {
        modrinth.neoforgeLegacyVersionsBody = {
          'isSnapshot': false,
          'versions': [
            '1.20.1-47.1.100',
            '1.20.1-47.1.106',
            '1.20.1-47.1.107-beta',
          ],
        };
        final v = await resolver.resolve(
          loader: Loader.neoforge,
          tag: 'latest',
          mcVersion: '1.20.1',
        );
        expect(v, '47.1.107-beta');
      });

      test(
        'concrete legacy neoforge tag validates against legacy list',
        () async {
          final v = await resolver.resolve(
            loader: Loader.neoforge,
            tag: '47.1.106',
            mcVersion: '1.20.1',
          );
          expect(v, '47.1.106');
          expect(
            modrinth.requestCounts['/neoforge-legacy/versions'] ?? 0,
            greaterThan(0),
          );
        },
      );

      test(
        'concrete legacy neoforge tag errors when not in legacy list',
        () async {
          await expectLater(
            resolver.resolve(
              loader: Loader.neoforge,
              tag: '47.1.999',
              mcVersion: '1.20.1',
            ),
            throwsA(isA<UserError>()),
          );
        },
      );
    });

    group('Fabric', () {
      test('fabric:stable picks newest stable', () async {
        final v = await resolver.resolve(
          loader: Loader.fabric,
          tag: 'stable',
          mcVersion: '1.21.1',
        );
        expect(v, '0.17.3');
      });

      test('fabric:latest picks newest of any stability', () async {
        modrinth.fabricLoaderVersions = [
          {'version': '0.18.0-beta.1', 'stable': false},
          {'version': '0.17.3', 'stable': true},
        ];
        final v = await resolver.resolve(
          loader: Loader.fabric,
          tag: 'latest',
          mcVersion: '1.21.1',
        );
        expect(v, '0.18.0-beta.1');
      });

      test('concrete fabric tag validates against upstream list', () async {
        final v = await resolver.resolve(
          loader: Loader.fabric,
          tag: '0.17.3',
          mcVersion: '1.21.1',
        );
        expect(v, '0.17.3');
      });

      test('concrete fabric tag errors when version unknown', () async {
        await expectLater(
          resolver.resolve(
            loader: Loader.fabric,
            tag: '99.9.9',
            mcVersion: '1.21.1',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('Fabric loader version'),
            ),
          ),
        );
      });
    });

    group('mc-version parsing', () {
      test('malformed mc-version errors with helpful message', () async {
        for (final bad in const ['snapshot-23w14a', '1', '1.x', '2.0.0']) {
          await expectLater(
            resolver.resolve(
              loader: Loader.neoforge,
              tag: 'stable',
              mcVersion: bad,
            ),
            throwsA(
              isA<UserError>().having(
                (e) => e.message,
                'message',
                contains('mc-version "$bad"'),
              ),
            ),
            reason: 'expected UserError for mc-version "$bad"',
          );
        }
      });
    });

    group('upstream errors', () {
      test('empty Fabric list surfaces upstream-labelled UserError', () async {
        modrinth.fabricLoaderVersions = const [];
        await expectLater(
          resolver.resolve(
            loader: Loader.fabric,
            tag: 'stable',
            mcVersion: '1.21.1',
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('meta.fabricmc.net'),
            ),
          ),
        );
      });
    });
  });
}
