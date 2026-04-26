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
      expect(e.message, contains('create'));
      expect(e.message, contains('^6.0.0'));
    }
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
        try {
          await solver.solve([
            RootConstraint(
              slug: 'jei',
              constraint: VersionConstraint.any,
              channel: Channel.beta,
              isUserDeclared: true,
            ),
          ]);
          fail('expected ValidationError');
        } on ValidationError catch (e) {
          expect(e.message, contains('jei'));
          expect(e.message, contains('channel beta'));
        }
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

  group('UnsatisfiableGraphError', () {
    test('is a ValidationError so existing catch sites still work', () async {
      // Defensive: the public surface preserves the old exception type
      // for any caller that still pattern-matches on ValidationError.
      final db = {
        'a': [v(slug: 'a', number: '1.0.0')],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => null,
      );
      try {
        await solver.solve([
          RootConstraint(
            slug: 'a',
            constraint: VersionConstraint.parse('^2.0.0'),
            isUserDeclared: true,
          ),
        ]);
        fail('expected ValidationError');
      } on ValidationError catch (e) {
        expect(e, isA<ValidationError>());
        expect(e, isA<UnsatisfiableGraphError>());
      }
    });

    test(
      'two user roots pin a shared transitive at the same major resolve '
      'cleanly to the highest in-range version (caret semantics, not '
      'exact pin)',
      () async {
        // a pins shared 1.2.0 → ^1.2.0 → [1.2.0, 2.0.0).
        // b pins shared 1.5.0 → ^1.5.0 → [1.5.0, 2.0.0).
        // Intersection ^1.5.0 admits 1.5.0 and 1.7.0; PubGrub picks
        // 1.7.0 (newest in range). If we treated version_id as an
        // exact pin instead, this combination would conflict on every
        // patch release — too aggressive.
        final db = {
          'a': [
            v(
              slug: 'a',
              number: '1.0.0',
              deps: const [
                Dependency(
                  projectId: 'shared',
                  versionId: 'shared-1.2.0',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
          ],
          'b': [
            v(
              slug: 'b',
              number: '1.0.0',
              deps: const [
                Dependency(
                  projectId: 'shared',
                  versionId: 'shared-1.5.0',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
          ],
          'shared': [
            v(slug: 'shared', number: '1.2.0'),
            v(slug: 'shared', number: '1.5.0'),
            v(slug: 'shared', number: '1.7.0'),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => id,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'a',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
          RootConstraint(
            slug: 'b',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['shared']!.versionNumber, '1.7.0');
      },
    );

    test(
      'two user roots pin a shared transitive at cross-major versionIds: '
      'resolve to the higher floor (>= semantics, no upper bound)',
      () async {
        // a → shared >=1.0.0; b → shared >=2.0.0; intersection >=2.0.0.
        final db = {
          'a': [
            v(
              slug: 'a',
              number: '1.0.0',
              deps: const [
                Dependency(
                  projectId: 'shared',
                  versionId: 'shared-1.0.0',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
          ],
          'b': [
            v(
              slug: 'b',
              number: '1.0.0',
              deps: const [
                Dependency(
                  projectId: 'shared',
                  versionId: 'shared-2.0.0',
                  dependencyType: DependencyType.required,
                ),
              ],
            ),
          ],
          'shared': [
            v(slug: 'shared', number: '1.0.0'),
            v(slug: 'shared', number: '2.0.0'),
          ],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => id,
        );
        final out = await solver.solve([
          RootConstraint(
            slug: 'a',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
          RootConstraint(
            slug: 'b',
            constraint: VersionConstraint.any,
            isUserDeclared: true,
          ),
        ]);
        expect(out.decisions['shared']!.versionNumber, '2.0.0');
      },
    );

    test(
      'mutual incompatible deps: both user-root slugs land in '
      'conflictingUserSlugs',
      () async {
        // `a` declares `b` as incompatible. The solver decides `a` first
        // (alphabetical user-root tie-break), then tries to decide `b` —
        // by which point `a` is already in `decisions`, so the
        // incompat-already-decided branch fires and records `b` as the
        // failing slug with `a` as its counterpart. Both must end up in
        // conflictingUserSlugs so the auto-disable cuts both endpoints
        // and lets the user pick which to keep.
        final db = {
          'a': [
            v(
              slug: 'a',
              number: '1.0.0',
              deps: const [
                Dependency(
                  projectId: 'b',
                  dependencyType: DependencyType.incompatible,
                ),
              ],
            ),
          ],
          'b': [v(slug: 'b', number: '1.0.0')],
        };
        final solver = PubGrubSolver(
          listVersions: (slug) async => db[slug] ?? [],
          resolveSlugForProjectId: (id) async => id,
        );
        try {
          await solver.solve([
            RootConstraint(
              slug: 'a',
              constraint: VersionConstraint.any,
              isUserDeclared: true,
            ),
            RootConstraint(
              slug: 'b',
              constraint: VersionConstraint.any,
              isUserDeclared: true,
            ),
          ]);
          fail('expected UnsatisfiableGraphError');
        } on UnsatisfiableGraphError catch (e) {
          expect(e.conflictingUserSlugs, containsAll(['a', 'b']));
        }
      },
    );

    test(
      'transitive failure attributes the conflict to the user-declared '
      'ancestor',
      () async {
        // User declares `create`. Resolver pulls in `flywheel` transitively;
        // `flywheel` has no published version. The user-controllable
        // disable target is `create` (the ancestor), since the user can
        // not directly act on `flywheel`'s entry — it isn't in mods.yaml.
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
          fail('expected UnsatisfiableGraphError');
        } on UnsatisfiableGraphError catch (e) {
          expect(e.conflictingUserSlugs, contains('create'));
          // flywheel is not user-declared → must NOT appear.
          expect(e.conflictingUserSlugs, isNot(contains('flywheel')));
        }
      },
    );

    test(
      'direct user-root with no matching versions throws '
      'UnsatisfiableGraphError naming the user root',
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
          fail('expected UnsatisfiableGraphError');
        } on UnsatisfiableGraphError catch (e) {
          expect(e.conflictingUserSlugs, {'create'});
        }
      },
    );
  });

  group('project_overrides (sticky pre-decisions)', () {
    test('case 1: override on a slug already in mods: wins over '
        'the mods: constraint', () async {
      final db = {
        'jei': [
          v(slug: 'jei', number: '19.0.0'),
          v(slug: 'jei', number: '19.5.0'),
          v(slug: 'jei', number: '19.27.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [OverridePin('jei', db['jei']![2])],
      );
      // The user-declared root would normally cap us at 19.0.0; the
      // override pin pre-decides 19.27.0 and the root is dropped from
      // the resolver's candidate-search loop (handled by Resolver,
      // mirrored here by simply not adding it).
      final out = await solver.solve(const []);
      expect(out.decisions['jei']!.versionNumber, '19.27.0');
    });

    test('case 2: purely transitive override is added to graph at '
        'override version', () async {
      final db = {
        'flywheel': [
          v(slug: 'flywheel', number: '1.0.0'),
          v(slug: 'flywheel', number: '2.0.0'),
          v(slug: 'flywheel', number: '3.0.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [OverridePin('flywheel', db['flywheel']![1])],
      );
      final out = await solver.solve(const []);
      expect(out.decisions['flywheel']!.versionNumber, '2.0.0');
    });

    test('case 3: incompatible edge against an overridden slug '
        'is dropped', () async {
      final db = {
        'bukkit_compat': [
          v(
            slug: 'bukkit_compat',
            number: '1.0.0',
            deps: [
              const Dependency(
                projectId: 'forge_compat',
                dependencyType: DependencyType.incompatible,
              ),
            ],
          ),
        ],
        'forge_compat': [v(slug: 'forge_compat', number: '1.0.0')],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [
          OverridePin('forge_compat', db['forge_compat']![0]),
        ],
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'bukkit_compat',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions.keys, containsAll(['bukkit_compat', 'forge_compat']));
    });

    test('case 4: override constraint wins over a transitive '
        'lower-bound from another mod', () async {
      // mod_a requires mod_b at version-id 'mod_b-2.0.0' (=> floor 2.0.0)
      // but the override pins mod_b@1.0.0. The pin must win.
      final db = {
        'mod_a': [
          v(
            slug: 'mod_a',
            number: '1.0.0',
            deps: [
              const Dependency(
                projectId: 'mod_b',
                versionId: 'mod_b-2.0.0',
                dependencyType: DependencyType.required,
              ),
            ],
          ),
        ],
        'mod_b': [
          v(slug: 'mod_b', number: '1.0.0'),
          v(slug: 'mod_b', number: '2.0.0'),
          v(slug: 'mod_b', number: '3.0.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [OverridePin('mod_b', db['mod_b']![0])],
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'mod_a',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['mod_b']!.versionNumber, '1.0.0');
    });

    test('case 5: override wins when no inherited constraint is '
        'satisfiable', () async {
      // mod_a requires mod_b@5.0.0, but max published is 3.0.0. Without
      // the override this would throw; with it, resolution succeeds.
      final db = {
        'mod_a': [
          v(
            slug: 'mod_a',
            number: '1.0.0',
            deps: [
              const Dependency(
                projectId: 'mod_b',
                versionId: 'mod_b-5.0.0',
                dependencyType: DependencyType.required,
              ),
            ],
          ),
        ],
        'mod_b': [
          v(slug: 'mod_b', number: '1.0.0'),
          v(slug: 'mod_b', number: '2.0.0'),
          v(slug: 'mod_b', number: '3.0.0'),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [OverridePin('mod_b', db['mod_b']![0])],
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'mod_a',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions['mod_b']!.versionNumber, '1.0.0');
    });

    test("case 6: override mod's outbound incompatible edge "
        'is dropped', () async {
      // create_incompatible 1.1.0 declares `incompatible: create`. The
      // user has both `create ^6.0.0` in mods: and `create_incompatible
      // 1.1.0` in project_overrides:. Resolution must succeed.
      final db = {
        'create': [
          v(slug: 'create', number: '6.0.0'),
          v(slug: 'create', number: '6.1.0'),
        ],
        'create_incompatible': [
          v(
            slug: 'create_incompatible',
            number: '1.1.0',
            deps: [
              const Dependency(
                projectId: 'create',
                dependencyType: DependencyType.incompatible,
              ),
            ],
          ),
        ],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [
          OverridePin('create_incompatible', db['create_incompatible']![0]),
        ],
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'create',
          constraint: VersionConstraint.parse('^6.0.0'),
          isUserDeclared: true,
        ),
      ]);
      expect(out.decisions.keys,
          containsAll(['create', 'create_incompatible']));
    });

    test('overridden slug never appears in conflictingUserSlugs',
        () async {
      // Override pins jei to a version that would normally lose, but
      // because the slug is overridden, even when the rest of the graph
      // fails the override slug is filtered out of the auto-disable
      // set. (Build a graph that fails via a different slug.)
      final db = {
        'jei': [v(slug: 'jei', number: '1.0.0')],
        'create': [v(slug: 'create', number: '5.0.0')],
      };
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [OverridePin('jei', db['jei']![0])],
      );
      try {
        await solver.solve([
          RootConstraint(
            slug: 'create',
            constraint: VersionConstraint.parse('^6.0.0'),
            isUserDeclared: true,
          ),
        ]);
        fail('expected throw');
      } on UnsatisfiableGraphError catch (e) {
        expect(e.conflictingUserSlugs, isNot(contains('jei')));
        expect(e.conflictingUserSlugs, contains('create'));
      }
    });

    test('override decision survives backtracking', () async {
      // Force the search loop to backtrack: mod_a has two candidates,
      // the first conflicts (declares mod_c incompatible while mod_c
      // is decided via mod_b dep), the second succeeds.
      final db = {
        'mod_a': [
          v(
            slug: 'mod_a',
            number: '2.0.0',
            deps: [
              const Dependency(
                projectId: 'mod_c',
                dependencyType: DependencyType.incompatible,
              ),
            ],
          ),
          v(slug: 'mod_a', number: '1.0.0'),
        ],
        'mod_b': [
          v(
            slug: 'mod_b',
            number: '1.0.0',
            deps: [
              const Dependency(
                projectId: 'mod_c',
                dependencyType: DependencyType.required,
              ),
            ],
          ),
        ],
        'mod_c': [v(slug: 'mod_c', number: '1.0.0')],
      };
      final overridePin = OverridePin('mod_c', db['mod_c']![0]);
      final solver = PubGrubSolver(
        listVersions: (slug) async => db[slug] ?? [],
        resolveSlugForProjectId: (id) async => id,
        overridePins: [overridePin],
      );
      final out = await solver.solve([
        RootConstraint(
          slug: 'mod_a',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
        RootConstraint(
          slug: 'mod_b',
          constraint: VersionConstraint.any,
          isUserDeclared: true,
        ),
      ]);
      // mod_a 2.0.0 was abandoned (its incompatible edge was dropped
      // because mod_c is overridden — but it would *still* conflict
      // with mod_c being decided). The backtracking restored the
      // override decision.
      expect(out.decisions['mod_c']!.versionNumber, '1.0.0');
      expect(out.decisions['mod_a']!.versionNumber, '2.0.0');
    });
  });
}
