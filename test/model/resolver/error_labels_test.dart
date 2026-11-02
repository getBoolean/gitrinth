import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/modrinth/version.dart';
import 'package:gitrinth/src/model/resolver/modrinth_solver_adapter.dart';
import 'package:gitrinth/src/model/resolver/resolver.dart';
import 'package:gitrinth/src/service/source_identity.dart';
import 'package:test/test.dart';

void main() {
  test(
    'missing-file error displays the local name for a scoped solver key',
    () async {
      final identities = SourceIdentity();
      for (final section in [Section.mods, Section.resourcePacks]) {
        identities.register(
          LocalEntryKey(section, 'same'),
          host: 'https://example.com/v2',
        );
      }
      final resolver = Resolver(
        nodeKeyFor: (section, slug) =>
            identities.solverKey(LocalEntryKey(section, slug)),
        localNameFor: (key) => identities.nodeForSolverKey(key).localKey,
        formatError: identities.displayMessage,
        resolveSlugForProjectId: (_) async => null,
        listVersions: (_) async => [
          ModrinthSolverVersion(
            const Version(
              id: 'v1',
              projectId: 'p1',
              versionNumber: '1.0.0',
              files: [],
              dependencies: [],
              loaders: [],
              gameVersions: [],
            ),
          ),
        ],
      );
      final manifest = ModsYaml(
        slug: 'pack',
        name: 'Pack',
        version: '1',
        description: '',
        mcVersion: '1.21.1',
        loader: const LoaderConfig(mods: ModLoader.fabric),
        mods: {'same': const ModEntry(slug: 'same')},
        resourcePacks: {'same': const ModEntry(slug: 'same')},
      );
      await expectLater(
        resolver.resolve(manifest),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.message,
            'message',
            'Resolved same version 1.0.0 has no downloadable file.',
          ),
        ),
      );
    },
  );
}
