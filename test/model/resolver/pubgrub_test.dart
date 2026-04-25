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
  String? datePublished,
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
  datePublished: datePublished,
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


  group('candidate ordering', () {
    test(
      'date-encoded resource pack labels: newest by date_published wins '
      'over higher-MMP older release',
      () async {
        // Faithful 32x ships its versions as `<max-mc>-<release-label>`
        // (e.g. `1.21.1-december-2025`). The leading `1.21.x` is the
        // highest-supported MC version, NOT a newer pack release —
        // `1.21.3-june-2025` was published *before* `1.21.1-december-2025`
        // even though its parsed semver is "higher." Sort must follow
        // `date_published` so upgrade picks the December release.
        final db = {
          'faithful-32x': [
            v(
              slug: 'faithful-32x',
              number: '1.21.1-november-2024',
              datePublished: '2024-11-15T00:00:00Z',
            ),
            v(
              slug: 'faithful-32x',
              number: '1.21.1-april-2025',
              datePublished: '2025-04-15T00:00:00Z',
            ),
            v(
              slug: 'faithful-32x',
              number: '1.21.3-june-2025',
              datePublished: '2025-06-15T00:00:00Z',
            ),
            v(
              slug: 'faithful-32x',
              number: '1.21.1-december-2025',
              datePublished: '2025-12-15T00:00:00Z',
            ),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => null,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'faithful-32x',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
        ]);
        expect(
          out.decisions['faithful-32x']!.versionNumber,
          '1.21.1-december-2025',
        );
      },
    );

    test('null date_published falls back to parsed semver desc', () async {
      // Existing-callers contract: when Modrinth doesn't return a
      // date_published (or in tests that don't set one), candidate sort
      // falls back to parsed semver descending — matching pre-fix
      // behavior for normal semver-shaped mod versions.
      final db = {
        'a': [
          v(slug: 'a', number: '1.0.0'),
          v(slug: 'a', number: '1.5.0'),
          v(slug: 'a', number: '1.2.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => null,
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'a',
          constraint: VersionConstraint.parse('^1.0.0'),
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['a']!.versionNumber, '1.5.0');
    });
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
