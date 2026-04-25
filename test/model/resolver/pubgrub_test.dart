import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/modrinth/dependency.dart';
import 'package:gitrinth/src/model/modrinth/version.dart' as modrinth;
import 'package:gitrinth/src/model/modrinth/version_file.dart';
import 'package:gitrinth/src/model/resolver/pubgrub.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

modrinth.Version v({
  required String slug,
  required String number,
  List<Dependency> deps = const [],
  String? versionType,
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
  versionType: versionType,
);

void main() {
  test('picks highest version matching constraint', () async {
    final db = {
      'create': [
        v(slug: 'create', number: '6.0.10'),
        v(slug: 'create', number: '6.0.11'),
        v(slug: 'create', number: '7.0.0'),
      ],
    };
    final solver = PubGrubSolver(
      listVersions: (slug) async => db[slug] ?? [],
      resolveSlugForProjectId: (id) async => null,
    );
    final out = await solver.solve([
      RootConstraint(
        slug: 'create',
        constraint: VersionConstraint.parse('^6.0.10'),
        isUserDeclared: true,
      ),
    ]);
    expect(out.decisions['create']!.versionNumber, '6.0.11');
  });

  test('resolves transitive required dependencies', () async {
    final db = {
      'create': [
        v(
          slug: 'create',
          number: '6.0.10',
          deps: [
            const Dependency(
              projectId: 'flywheel',
              dependencyType: DependencyType.required,
            ),
          ],
        ),
      ],
      'flywheel': [v(slug: 'flywheel', number: '1.0.0')],
    };
    final solver = PubGrubSolver(
      listVersions: (slug) async => db[slug] ?? [],
      resolveSlugForProjectId: (id) async => id,
    );
    final out = await solver.solve([
      RootConstraint(
        slug: 'create',
        constraint: VersionConstraint.any,
        isUserDeclared: true,
      ),
    ]);
    expect(out.decisions.keys, containsAll(['create', 'flywheel']));
    expect(out.auto['create'], isFalse);
    expect(out.auto['flywheel'], isTrue);
  });

  test('reports human-readable failure when no version satisfies', () async {
    final db = {
      'create': [v(slug: 'create', number: '5.0.0')],
    };
    final solver = PubGrubSolver(
      listVersions: (slug) async => db[slug] ?? [],
      resolveSlugForProjectId: (id) async => null,
    );
    expect(
      () => solver.solve([
        RootConstraint(
          slug: 'create',
          constraint: VersionConstraint.parse('^6.0.0'),
          isUserDeclared: true,
        ),
      ]),
      throwsA(
        isA<ValidationError>().having(
          (e) => e.message,
          'message',
          contains('create'),
        ),
      ),
    );
  });

  test('lock suggestion is preferred when still satisfying', () async {
    final db = {
      'create': [
        v(slug: 'create', number: '6.0.10'),
        v(slug: 'create', number: '6.0.11'),
      ],
    };
    final solver = PubGrubSolver(
      listVersions: (slug) async => db[slug] ?? [],
      resolveSlugForProjectId: (id) async => null,
      lockSuggestions: const [LockSuggestion('create', '6.0.10')],
    );
    final out = await solver.solve([
      RootConstraint(
        slug: 'create',
        constraint: VersionConstraint.parse('^6.0.0'),
        isUserDeclared: true,
      ),
    ]);
    expect(out.decisions['create']!.versionNumber, '6.0.10');
  });

  group('channel filter', () {
    test('default (no channel) admits every version_type', () async {
      final db = {
        'jei': [
          v(slug: 'jei', number: '1.0.0', versionType: 'release'),
          v(slug: 'jei', number: '1.0.1-beta', versionType: 'beta'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => null,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'jei',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['jei']!.versionNumber, '1.0.1-beta');
    });

    test(
      'explicit release channel excludes beta even when beta is newer',
      () async {
        final db = {
          'jei': [
            v(slug: 'jei', number: '1.0.0', versionType: 'release'),
            v(slug: 'jei', number: '1.0.1-beta', versionType: 'beta'),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'jei',
            constraint: VersionConstraint.any,
            channel: Channel.release,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['jei']!.versionNumber, '1.0.0');
      },
    );

    test('beta floor picks beta when it is newer than any release', () async {
      final db = {
        'jei': [
          v(slug: 'jei', number: '1.0.0', versionType: 'release'),
          v(slug: 'jei', number: '1.0.1-beta', versionType: 'beta'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => null,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'jei',
          constraint: VersionConstraint.any,
          channel: Channel.beta,
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['jei']!.versionNumber, '1.0.1-beta');
    });

    test(
      'beta floor picks release when release is newer (floor, not filter)',
      () async {
        final db = {
          'jei': [
            v(slug: 'jei', number: '1.0.1-beta', versionType: 'beta'),
            v(slug: 'jei', number: '1.0.2', versionType: 'release'),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'jei',
            constraint: VersionConstraint.any,
            channel: Channel.beta,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['jei']!.versionNumber, '1.0.2');
      },
    );

    test(
      'beta channel + version range picks highest beta-or-release in range',
      () async {
        final db = {
          'jei': [
            v(slug: 'jei', number: '1.0.0', versionType: 'release'),
            v(slug: 'jei', number: '1.0.3-beta', versionType: 'beta'),
            v(slug: 'jei', number: '2.0.0', versionType: 'release'),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'jei',
            constraint: VersionConstraint.parse('^1.0.0'),
            channel: Channel.beta,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['jei']!.versionNumber, '1.0.3-beta');
      },
    );

    test(
      'channel-aware error when only alpha candidates exist under beta',
      () async {
        final db = {
          'jei': [v(slug: 'jei', number: '1.0.0-alpha', versionType: 'alpha')],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        expect(
          () => solver.solve([
            RootConstraint(
              slug: 'jei',
              constraint: VersionConstraint.any,
              channel: Channel.beta,
              isUserDeclared: true,
            ),
          ]),
          throwsA(
            isA<ValidationError>().having(
              (e) => e.message,
              'message',
              contains('channel beta'),
            ),
          ),
        );
      },
    );

    test(
      'transitive dependency defaults to permissive (any version_type)',
      () async {
        final db = {
          'create': [
            v(
              slug: 'create',
              number: '6.0.10',
              versionType: 'release',
              deps: [
                const Dependency(
                  projectId: 'flywheel',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
          ],
          'flywheel': [
            v(slug: 'flywheel', number: '1.0.0', versionType: 'release'),
            v(slug: 'flywheel', number: '1.0.1-beta', versionType: 'beta'),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => id,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'create',
            constraint: VersionConstraint.any,
            channel: Channel.release,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['create']!.versionNumber, '6.0.10');
        // Transitive dep is not constrained to the parent's release-only
        // floor; it inherits the permissive default.
        expect(out.decisions['flywheel']!.versionNumber, '1.0.1-beta');
      },
    );

    test(
      'missing version_type is treated as release (admitted by release floor)',
      () async {
        final db = {
          'jei': [
            v(
              slug: 'jei',
              number: '1.0.0',
            ), // versionType null → treated as release
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'jei',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['jei']!.versionNumber, '1.0.0');
      },
    );

    test(
      'lock suggestion for a beta is filtered out when entry pins release',
      () async {
        // Lockfile interaction: an existing pin at 1.0.1-beta is filtered out
        // before the constraint check once the entry's channel narrows to
        // release-only.
        final db = {
          'jei': [
            v(slug: 'jei', number: '1.0.0', versionType: 'release'),
            v(slug: 'jei', number: '1.0.1-beta', versionType: 'beta'),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
          lockSuggestions: const [LockSuggestion('jei', '1.0.1-beta')],
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'jei',
            constraint: VersionConstraint.any,
            channel: Channel.release,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['jei']!.versionNumber, '1.0.0');
      },
    );
  });

  group('forward dependency edges', () {
    test('records direct required edges per parent', () async {
      final db = {
        'create': [
          v(
            slug: 'create',
            number: '6.0.10',
            deps: const [
              Dependency(
                projectId: 'flywheel',
                dependencyType: DependencyType.required,
              ),
              Dependency(
                projectId: 'porting-lib',
                dependencyType: DependencyType.required,
              ),
            ],
          ),
        ],
        'flywheel': [v(slug: 'flywheel', number: '1.0.0')],
        'porting-lib': [v(slug: 'porting-lib', number: '2.0.0')],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'create',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      expect(out.edges['create'], unorderedEquals(['flywheel', 'porting-lib']));
      expect(out.edges['flywheel'], isEmpty);
      expect(out.edges['porting-lib'], isEmpty);
    });

    test('diamond dep is listed under each parent that requires it', () async {
      final db = {
        'create': [
          v(
            slug: 'create',
            number: '6.0.10',
            deps: const [
              Dependency(
                projectId: 'porting-lib',
                dependencyType: DependencyType.required,
              ),
            ],
          ),
        ],
        'cc-tweaked': [
          v(
            slug: 'cc-tweaked',
            number: '1.115.0',
            deps: const [
              Dependency(
                projectId: 'porting-lib',
                dependencyType: DependencyType.required,
              ),
            ],
          ),
        ],
        'porting-lib': [v(slug: 'porting-lib', number: '2.0.0')],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'create',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
        RootConstraint(
          slug: 'cc-tweaked',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      expect(out.edges['create'], ['porting-lib']);
      expect(out.edges['cc-tweaked'], ['porting-lib']);
      expect(out.edges['porting-lib'], isEmpty);
    });

    test('skips edge when projectId does not resolve to a slug', () async {
      final db = {
        'create': [
          v(
            slug: 'create',
            number: '6.0.10',
            deps: const [
              Dependency(
                projectId: 'unknown',
                dependencyType: DependencyType.required,
              ),
            ],
          ),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => null,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'create',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      expect(out.edges['create'], isEmpty);
      expect(out.decisions.keys, ['create']);
    });

    test(
      'backtracked candidate edges are dropped from final result',
      () async {
        // create@6.0.11 requires missing-mod which has no published
        // versions — solver backtracks to create@6.0.10 which requires
        // porting-lib instead. The final edges must contain only
        // 6.0.10's edge to porting-lib, never the abandoned 6.0.11's
        // edge to missing-mod.
        final db = {
          'create': [
            v(
              slug: 'create',
              number: '6.0.10',
              deps: const [
                Dependency(
                  projectId: 'porting-lib',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
            v(
              slug: 'create',
              number: '6.0.11',
              deps: const [
                Dependency(
                  projectId: 'missing-mod',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
          ],
          'missing-mod': const <modrinth.Version>[],
          'porting-lib': [v(slug: 'porting-lib', number: '2.0.0')],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => id,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'create',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
        ]);
        // Sanity: backtracked to 6.0.10.
        expect(out.decisions['create']!.versionNumber, '6.0.10');
        expect(out.edges['create'], ['porting-lib']);
        expect(out.edges['create'], isNot(contains('missing-mod')));
        expect(out.edges.containsKey('missing-mod'), isFalse);
      },
    );
  });
}
