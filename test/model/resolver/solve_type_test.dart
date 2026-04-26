import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/modrinth/dependency.dart';
import 'package:gitrinth/src/model/modrinth/version.dart' as modrinth;
import 'package:gitrinth/src/model/modrinth/version_file.dart';
import 'package:gitrinth/src/model/resolver/pubgrub.dart';
import 'package:gitrinth/src/model/resolver/version_selection.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

modrinth.Version v({
  required String slug,
  required String number,
  List<Dependency> deps = const [],
}) => modrinth.Version(
  id: '$slug-$number',
  projectId: slug,
  versionNumber: number,
  files: [
    VersionFile(
      url: 'https://example.com/$slug-$number.jar',
      filename: '$slug-$number.jar',
      hashes: const {'sha512': 'deadbeef'},
      size: 1,
      primary: true,
    ),
  ],
  dependencies: deps,
  loaders: const ['neoforge'],
  gameVersions: const ['1.21.1'],
);

void main() {
  test('SolveType.get picks the newest matching version', () async {
    final db = {
      'create': [
        v(slug: 'create', number: '6.0.10'),
        v(slug: 'create', number: '6.0.11'),
        v(slug: 'create', number: '6.5.2'),
      ],
    };
    final solver = PubGrubSolver(
      listVersions: (slug) async => db[slug] ?? [],
      resolveSlugForProjectId: (_) async => null,
      // SolveType.get is the default; spelled out for clarity.
      solveType: SolveType.get,
    );
    final out = await solver.solve([
      RootConstraint(
        slug: 'create',
        constraint: VersionConstraint.parse('^6.0.10'),
        isUserDeclared: true,
      ),
    ]);
    expect(out.decisions['create']!.versionNumber, '6.5.2');
  });

  test('SolveType.downgrade picks the oldest matching version', () async {
    final db = {
      'create': [
        v(slug: 'create', number: '6.0.10'),
        v(slug: 'create', number: '6.0.11'),
        v(slug: 'create', number: '6.5.2'),
      ],
    };
    final solver = PubGrubSolver(
      listVersions: (slug) async => db[slug] ?? [],
      resolveSlugForProjectId: (_) async => null,
      solveType: SolveType.downgrade,
    );
    final out = await solver.solve([
      RootConstraint(
        slug: 'create',
        constraint: VersionConstraint.parse('^6.0.10'),
        isUserDeclared: true,
      ),
    ]);
    expect(out.decisions['create']!.versionNumber, '6.0.10');
  });

  test(
    'SolveType.downgrade still honors a non-target lock pin',
    () async {
      // A pin on a slug the caller did NOT pass through `freshSlugs`
      // sticks around — `gitrinth downgrade <subset>` relies on this so
      // the un-named entries keep their existing pinned versions.
      final db = {
        'create': [
          v(slug: 'create', number: '6.0.10'),
          v(slug: 'create', number: '6.0.11'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (_) async => null,
        lockSuggestions: const [LockSuggestion('create', '6.0.11')],
        solveType: SolveType.downgrade,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'create',
          constraint: VersionConstraint.parse('^6.0.10'),
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['create']!.versionNumber, '6.0.11');
    },
  );

  test('pickHighestMatching honors SolveType.downgrade', () {
    final versions = [
      v(slug: 'a', number: '1.0.0'),
      v(slug: 'a', number: '1.5.2'),
      v(slug: 'a', number: '2.0.0'),
    ];
    final newest = pickHighestMatching(
      versions,
      VersionConstraint.parse('^1.0.0'),
      Channel.alpha,
    );
    expect(newest!.versionNumber, '1.5.2');

    final oldest = pickHighestMatching(
      versions,
      VersionConstraint.parse('^1.0.0'),
      Channel.alpha,
      solveType: SolveType.downgrade,
    );
    expect(oldest!.versionNumber, '1.0.0');
  });
}
