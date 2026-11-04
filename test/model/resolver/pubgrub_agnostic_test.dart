import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/resolver/pubgrub.dart';
import 'package:gitrinth/src/model/resolver/version_selection.dart';
import 'package:gitrinth/src/model/resolver/version_solver_types.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

/// Pure-test [SolverVersion] implementation that doesn't depend on
/// any platform-specific type. Drives a small CSP through
/// [PubGrubSolver] to confirm the solver doesn't downcast.
class _FakeSolverVersion implements SolverVersion {
  @override
  final String id;
  @override
  final String versionNumber;
  @override
  final Version parsedVersion;
  @override
  final Channel channel;
  @override
  final List<SolverDependency> dependencies;

  _FakeSolverVersion({
    required this.id,
    required this.versionNumber,
    String? parsed,
    this.dependencies = const [],
  }) : parsedVersion = Version.parse(parsed ?? versionNumber),
       channel = Channel.release;
}

int _fakeOrder(SolverVersion a, SolverVersion b) =>
    b.parsedVersion.compareTo(a.parsedVersion);

void main() {
  group('PubGrub on a non-Modrinth SolverVersion', () {
    test('decides a single user-root constraint', () async {
      final db = {
        'foo': [
          _FakeSolverVersion(id: 'foo-1', versionNumber: '1.0.0'),
          _FakeSolverVersion(id: 'foo-2', versionNumber: '2.0.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? const [],
        resolveSlugForProjectId: (_) async => null,
        selectionOrder: _fakeOrder,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'foo',
          constraint: VersionConstraint.parse('^1.0.0'),
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['foo']!.versionNumber, '1.0.0');
    });

    test('promotes a lock-suggestion when in range', () async {
      final db = {
        'foo': [
          _FakeSolverVersion(id: 'foo-1', versionNumber: '1.0.0'),
          _FakeSolverVersion(id: 'foo-2', versionNumber: '1.5.0'),
          _FakeSolverVersion(id: 'foo-3', versionNumber: '1.9.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? const [],
        resolveSlugForProjectId: (_) async => null,
        selectionOrder: _fakeOrder,
        lockSuggestions: const [LockSuggestion('foo', '1.5.0')],
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'foo',
          constraint: VersionConstraint.parse('^1.0.0'),
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['foo']!.versionNumber, '1.5.0');
    });

    test('honors a sticky override-pin decision', () async {
      final pinned = _FakeSolverVersion(id: 'foo-7', versionNumber: '7.0.0');
      final db = {
        'foo': [
          _FakeSolverVersion(id: 'foo-1', versionNumber: '1.0.0'),
          _FakeSolverVersion(id: 'foo-2', versionNumber: '2.0.0'),
          pinned,
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? const [],
        resolveSlugForProjectId: (_) async => null,
        selectionOrder: _fakeOrder,
        overridePins: [OverridePin('foo', pinned)],
      );
      final out = await solver.solve(const []);
      expect(out.decisions['foo']!.versionNumber, '7.0.0');
    });

    test(
      'follows a required dep and resolves slug via injected callback',
      () async {
        final db = {
          'parent': [
            _FakeSolverVersion(
              id: 'parent-1',
              versionNumber: '1.0.0',
              dependencies: const [
                SolverDependency(
                  targetProjectId: 'child-pid',
                  type: SolverDependencyType.required,
                ),
              ],
            ),
          ],
          'child': [_FakeSolverVersion(id: 'child-1', versionNumber: '1.0.0')],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? const [],
          resolveSlugForProjectId: (pid) async =>
              pid == 'child-pid' ? 'child' : null,
          selectionOrder: _fakeOrder,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'parent',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions.keys.toSet(), {'parent', 'child'});
        expect(out.auto['child'], isTrue);
        expect(out.auto['parent'], isFalse);
      },
    );

    test(
      'detects an incompatible dep against an already-decided slug',
      () async {
        final db = {
          'parent': [
            _FakeSolverVersion(
              id: 'parent-1',
              versionNumber: '1.0.0',
              dependencies: const [
                SolverDependency(
                  targetProjectId: 'foe-pid',
                  type: SolverDependencyType.incompatible,
                ),
              ],
            ),
          ],
          'foe': [_FakeSolverVersion(id: 'foe-1', versionNumber: '1.0.0')],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? const [],
          resolveSlugForProjectId: (pid) async =>
              pid == 'foe-pid' ? 'foe' : null,
          selectionOrder: _fakeOrder,
        );
        await expectLater(
          solver.solve([
            RootConstraint(
              slug: 'parent',
              constraint: VersionConstraint.any,
              isUserDeclared: true,
            ),
            RootConstraint(
              slug: 'foe',
              constraint: VersionConstraint.any,
              isUserDeclared: true,
            ),
          ]),
          throwsA(isA<UnsatisfiableGraphError>()),
        );
      },
    );

    test('downgrade picks the lowest matching candidate', () async {
      final db = {
        'foo': [
          _FakeSolverVersion(id: 'foo-1', versionNumber: '1.0.0'),
          _FakeSolverVersion(id: 'foo-2', versionNumber: '1.5.0'),
          _FakeSolverVersion(id: 'foo-3', versionNumber: '1.9.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? const [],
        resolveSlugForProjectId: (_) async => null,
        selectionOrder: _fakeOrder,
        solveType: SolveType.downgrade,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'foo',
          constraint: VersionConstraint.parse('^1.0.0'),
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['foo']!.versionNumber, '1.0.0');
    });
  });
}
