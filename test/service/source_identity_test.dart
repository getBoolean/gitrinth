import 'package:gitrinth/src/service/source_identity.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';
import 'package:gitrinth/src/model/resolver/resolver.dart';
import 'package:gitrinth/src/model/resolver/pubgrub.dart';
import 'package:gitrinth/src/model/resolver/modrinth_solver_adapter.dart';
import 'package:gitrinth/src/model/modrinth/version.dart' as mr;
import 'package:gitrinth/src/model/modrinth/dependency.dart';

void main() {
  test(
    'transitive opaque failures keep local labels and structured conflicts',
    () async {
      final identities = SourceIdentity();
      const root = LocalEntryKey(Section.mods, 'anchor');
      const existing = LocalEntryKey(Section.mods, 'library');
      const transitive = LocalEntryKey(Section.resourcePacks, 'library');
      for (final node in [root, existing]) {
        identities.register(node, host: 'https://example.com/v2');
      }
      final resolver = Resolver(
        nodeKeyFor: (section, slug) =>
            identities.solverKey(LocalEntryKey(section, slug)),
        localNameFor: (key) => identities.nodeForSolverKey(key).localKey,
        formatError: identities.displayMessage,
        sectionForSlug: (key) => identities.nodeForSolverKey(key).section,
        resolveSlugForProjectId: (_) async => null,
        resolveDependencySlug: (_, _) async {
          identities.register(transitive, host: 'https://example.com/v2');
          return identities.solverKey(transitive);
        },
        listVersions: (key) async => key == 'anchor'
            ? [
                ModrinthSolverVersion(
                  const mr.Version(
                    id: 'V',
                    projectId: 'anchor',
                    versionNumber: '1.0.0',
                    files: [],
                    dependencies: [
                      Dependency(
                        projectId: 'LIB',
                        dependencyType: DependencyType.required,
                      ),
                    ],
                    loaders: [],
                    gameVersions: [],
                  ),
                ),
              ]
            : [],
      );
      final manifest = ModsYaml(
        slug: 'p',
        name: 'p',
        version: '1',
        description: '',
        mcVersion: '1.21.1',
        loader: const LoaderConfig(mods: ModLoader.fabric),
        mods: {'anchor': const ModEntry(slug: 'anchor')},
      );
      await expectLater(
        resolver.resolve(manifest),
        throwsA(
          isA<UnsatisfiableGraphError>()
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('library'),
                  isNot(contains('\u0000')),
                  isNot(contains('resourcePacks/')),
                ),
              )
              .having(
                (error) => error.conflictingUserSlugs,
                'conflicting names',
                {'anchor'},
              ),
        ),
      );
    },
  );
  test(
    'remote aliases preserve local keys and full normalized host identity',
    () {
      final identities = SourceIdentity();
      const mod = LocalEntryKey(Section.mods, 'same');
      const resource = LocalEntryKey(Section.resourcePacks, 'same');
      const alias = LocalEntryKey(Section.mods, 'alias');
      for (final node in [mod, resource, alias]) {
        identities.register(node, host: 'HTTPS://Example.COM:8443/api/v2/');
        identities.bind(
          node,
          ModrinthProjectKey('https://example.com:8443/api/v2', 'PID'),
        );
      }
      expect(
        identities.aliases(
          ModrinthProjectKey('https://EXAMPLE.com:8443/api/v2/', 'PID'),
        ),
        {mod, resource, alias},
      );
      expect(
        identities.aliases(
          ModrinthProjectKey('https://example.com:8443/other/v2', 'PID'),
        ),
        isEmpty,
      );
      expect(
        identities.aliases(
          ModrinthProjectKey('https://example.com:8444/api/v2', 'PID'),
        ),
        isEmpty,
      );
      expect(identities.solverKey(mod), isNot(identities.solverKey(resource)));
      expect(
        identities.nodeForSolverKey(identities.solverKey(resource)),
        resource,
      );
      expect(identities.find('same'), isNull);
      expect(identities.find('same', Section.mods), mod);
    },
  );
}
