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

  group('failure messages (dart pub-style)', () {
    test(
      'direct user-root failure emits a single Because... '
      'Version solving failed. chain',
      () async {
        final db = {
          'create': [v(slug: 'create', number: '5.0.0')],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        try {
          await solver.solve([
            RootConstraint(
              slug: 'create',
              constraint: VersionConstraint.parse('^6.0.0'),
              isUserDeclared: true,
            ),
          ]);
          fail('expected ValidationError');
        } on ValidationError catch (e) {
          final msg = e.message;
          expect(
            msg,
            startsWith('Because the modpack depends on create ^6.0.0'),
          );
          expect(msg, contains('no version of create matches ^6.0.0'));
          expect(msg, endsWith('Version solving failed.'));
          // The "saw N candidates" parenthetical lands at the end of the reason.
          expect(msg, contains('(saw 1 candidates)'));
        }
      },
    );

    test('transitive failure includes the parent → child chain', () async {
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
            ],
          ),
        ],
        // Empty version list for flywheel → "no published version matches".
        'flywheel': <modrinth.Version>[],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
      );
      try {
        await solver.solve([
          RootConstraint(
            slug: 'create',
            constraint: VersionConstraint.parse('^6.0.10'),
            isUserDeclared: true,
          ),
        ]);
        fail('expected ValidationError');
      } on ValidationError catch (e) {
        final msg = e.message;
        expect(msg, contains('the modpack depends on create ^6.0.10'));
        expect(msg, contains('every create depends on flywheel'));
        expect(
          msg,
          contains(
            'no published version of flywheel matches the configured '
            'loader/mc-version pair',
          ),
        );
        expect(msg, endsWith('Version solving failed.'));
      }
    });

    test(
      'no `all candidate versions led to conflicts` cascade through other '
      'user roots',
      () async {
        // The original cascade scenario: one bad root (`distanthorizons`)
        // causes the depth-first search to iterate every candidate of the
        // alphabetically-earlier user roots before failing. Each of those
        // roots used to land in the conflict list as
        // "all candidate versions led to conflicts" — pure noise.
        final db = {
          'appleskin': [v(slug: 'appleskin', number: '3.0.9')],
          'create': [v(slug: 'create', number: '6.0.10')],
          'distanthorizons': [
            v(
              slug: 'distanthorizons',
              number: '2.3.0',
              versionType: 'release',
            ),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        try {
          await solver.solve([
            RootConstraint(
              slug: 'appleskin',
              constraint: VersionConstraint.parse('^3.0.9'),
              isUserDeclared: true,
            ),
            RootConstraint(
              slug: 'create',
              constraint: VersionConstraint.parse('^6.0.10'),
              isUserDeclared: true,
            ),
            // Bad root: pin a version that doesn't exist.
            RootConstraint(
              slug: 'distanthorizons',
              constraint: VersionConstraint.parse('^99.0.0'),
              isUserDeclared: true,
            ),
          ]);
          fail('expected ValidationError');
        } on ValidationError catch (e) {
          final msg = e.message;
          expect(msg, isNot(contains('all candidate versions led to conflicts')));
          // The actual broken slug is named.
          expect(msg, contains('distanthorizons'));
          // The healthy slugs are NOT named in any failure paragraph
          // (their names appear nowhere in the message).
          expect(msg, isNot(contains('appleskin')));
          expect(msg, isNot(contains(' create ')));
          expect(msg, endsWith('Version solving failed.'));
        }
      },
    );

    test(
      'deduplicates the same leaf failure encountered on multiple '
      'backtrack paths',
      () async {
        // Both create candidates require flywheel; flywheel has no
        // satisfying version. Each backtrack revisits flywheel's
        // failure — the message should mention it once.
        final db = {
          'create': [
            v(
              slug: 'create',
              number: '6.0.11',
              deps: const [
                Dependency(
                  projectId: 'flywheel',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
            v(
              slug: 'create',
              number: '6.0.10',
              deps: const [
                Dependency(
                  projectId: 'flywheel',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
          ],
          'flywheel': <modrinth.Version>[],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => id,
        );
        try {
          await solver.solve([
            RootConstraint(
              slug: 'create',
              constraint: VersionConstraint.any,
              isUserDeclared: true,
            ),
          ]);
          fail('expected ValidationError');
        } on ValidationError catch (e) {
          final msg = e.message;
          // The flywheel reason appears exactly once even though two
          // create candidates each tried (and failed) on it.
          final flywheelReason =
              'no published version of flywheel matches the configured '
              'loader/mc-version pair';
          final occurrences = flywheelReason.allMatches(msg).length;
          expect(
            occurrences,
            1,
            reason: 'expected exactly one mention of the flywheel failure, '
                'got $occurrences in:\n$msg',
          );
          expect(msg, endsWith('Version solving failed.'));
        }
      },
    );
  });
}
