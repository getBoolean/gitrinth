import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/modrinth/dependency.dart';
import 'package:gitrinth/src/model/modrinth/version.dart' as modrinth;
import 'package:gitrinth/src/model/modrinth/version_file.dart';
import 'package:gitrinth/src/model/resolver/modrinth_solver_adapter.dart';
import 'package:gitrinth/src/model/resolver/version_selection.dart';
import 'package:gitrinth/src/model/resolver/version_solver_types.dart';
import 'package:test/test.dart';

modrinth.Version _v({
  required String id,
  required String versionNumber,
  String? versionType,
  String? datePublished,
  List<Dependency> dependencies = const [],
}) => modrinth.Version(
  id: id,
  projectId: 'p',
  versionNumber: versionNumber,
  files: [
    VersionFile(
      url: 'https://example.com/$id.jar',
      filename: '$id.jar',
      hashes: const {'sha512': 'deadbeef'},
      size: 1,
      primary: true,
    ),
  ],
  dependencies: dependencies,
  loaders: const ['fabric'],
  gameVersions: const ['1.21.1'],
  versionType: versionType,
  datePublished: datePublished,
);

void main() {
  group('ModrinthSolverVersion', () {
    test('passes versionNumber and id through', () {
      final v = ModrinthSolverVersion(_v(id: 'x', versionNumber: '1.2.3'));
      expect(v.id, 'x');
      expect(v.versionNumber, '1.2.3');
    });

    test('parses parsedVersion via parseModrinthVersionBestEffort', () {
      // Four-segment numeric → pub_semver-friendly form via the
      // best-effort parser.
      final v = ModrinthSolverVersion(
        _v(id: 'x', versionNumber: '19.27.0.340'),
      );
      expect(v.parsedVersion.major, 19);
      expect(v.parsedVersion.minor, 27);
      expect(v.parsedVersion.patch, 0);
    });

    test('versionType release/beta/alpha → Channel', () {
      expect(
        ModrinthSolverVersion(
          _v(id: 'r', versionNumber: '1.0.0', versionType: 'release'),
        ).channel,
        Channel.release,
      );
      expect(
        ModrinthSolverVersion(
          _v(id: 'b', versionNumber: '1.0.0', versionType: 'beta'),
        ).channel,
        Channel.beta,
      );
      expect(
        ModrinthSolverVersion(
          _v(id: 'a', versionNumber: '1.0.0', versionType: 'alpha'),
        ).channel,
        Channel.alpha,
      );
    });

    test('null/unknown versionType defaults to release', () {
      expect(
        ModrinthSolverVersion(_v(id: 'n', versionNumber: '1.0.0')).channel,
        Channel.release,
      );
    });

    test('drops optional and embedded deps; keeps required + incompatible', () {
      final v = ModrinthSolverVersion(
        _v(
          id: 'x',
          versionNumber: '1.0.0',
          dependencies: const [
            Dependency(
              projectId: 'r-pid',
              dependencyType: DependencyType.required,
            ),
            Dependency(
              projectId: 'o-pid',
              dependencyType: DependencyType.optional,
            ),
            Dependency(
              projectId: 'i-pid',
              dependencyType: DependencyType.incompatible,
            ),
            Dependency(
              projectId: 'e-pid',
              dependencyType: DependencyType.embedded,
            ),
          ],
        ),
      );
      expect(v.dependencies, hasLength(2));
      expect(v.dependencies.map((d) => d.targetProjectId).toSet(), {
        'r-pid',
        'i-pid',
      });
      expect(
        v.dependencies.where((d) => d.type == SolverDependencyType.required),
        hasLength(1),
      );
      expect(
        v.dependencies.where(
          (d) => d.type == SolverDependencyType.incompatible,
        ),
        hasLength(1),
      );
    });

    test('preserves projectId and versionId pass-through', () {
      final v = ModrinthSolverVersion(
        _v(
          id: 'x',
          versionNumber: '1.0.0',
          dependencies: const [
            Dependency(
              projectId: 'r-pid',
              versionId: 'r-vid',
              dependencyType: DependencyType.required,
            ),
          ],
        ),
      );
      expect(v.dependencies.single.targetProjectId, 'r-pid');
      expect(v.dependencies.single.targetVersionId, 'r-vid');
    });
  });

  group('compareModrinthSolverOrder', () {
    test('matches the legacy compareModrinthSelectionOrder ordering', () {
      // Two versions with date_published — newer date wins regardless of
      // parsed semver.
      final older = _v(
        id: 'a',
        versionNumber: '2.0.0',
        datePublished: '2025-01-01T00:00:00Z',
      );
      final newer = _v(
        id: 'b',
        versionNumber: '1.0.0',
        datePublished: '2025-06-01T00:00:00Z',
      );
      final solverOlder = ModrinthSolverVersion(older);
      final solverNewer = ModrinthSolverVersion(newer);
      // newer first under both comparators.
      expect(compareModrinthSolverOrder(solverNewer, solverOlder), lessThan(0));
      expect(
        compareModrinthSelectionOrder(
          newer,
          solverNewer.parsedVersion,
          older,
          solverOlder.parsedVersion,
        ),
        lessThan(0),
      );
    });
  });
}
