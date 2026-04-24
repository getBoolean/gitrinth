import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/pack_assembler.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/mrpack_index.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

ModsYaml _yaml({String slug = 'pack', String version = '0.1.0'}) {
  return ModsYaml(
    slug: slug,
    name: 'Pack',
    version: version,
    description: 'a pack',
    loader: const LoaderConfig(mods: Loader.fabric, modsVersion: '0.17.3'),
    mcVersion: '1.21.1',
  );
}

ModsLock _lock({
  Loader loader = Loader.fabric,
  String loaderVersion = '0.17.3',
  String mcVersion = '1.21.1',
  Map<String, LockedEntry> mods = const {},
  Map<String, LockedEntry> resourcePacks = const {},
  Map<String, LockedEntry> dataPacks = const {},
  Map<String, LockedEntry> shaders = const {},
}) {
  return ModsLock(
    gitrinthVersion: '0.1.0',
    loader: LoaderConfig(mods: loader, modsVersion: loaderVersion),
    mcVersion: mcVersion,
    mods: mods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
  );
}

LockedEntry _modrinth({
  required String slug,
  String name = 'mod-1.0.0.jar',
  String projectId = 'PID',
  String versionId = 'VID',
  String? url,
  String sha1 = '0123456789abcdef',
  String sha512 = 'deadbeef',
  int size = 1024,
  Environment env = Environment.both,
}) {
  return LockedEntry(
    slug: slug,
    sourceKind: LockedSourceKind.modrinth,
    version: '1.0.0',
    projectId: projectId,
    versionId: versionId,
    file: LockedFile(
      name: name,
      url: url,
      sha1: sha1,
      sha512: sha512,
      size: size,
    ),
    env: env,
  );
}

LockedEntry _url({
  required String slug,
  String url = 'https://example.com/x.jar',
  String filename = 'x.jar',
  String sha512 = 'beefcafe',
  Environment env = Environment.both,
}) {
  return LockedEntry(
    slug: slug,
    sourceKind: LockedSourceKind.url,
    file: LockedFile(name: filename, url: url, sha512: sha512),
    env: env,
  );
}

LockedEntry _path({
  required String slug,
  String path = './local.jar',
  Environment env = Environment.both,
}) {
  return LockedEntry(
    slug: slug,
    sourceKind: LockedSourceKind.path,
    path: path,
    env: env,
  );
}

void main() {
  group('mrpackLoaderKey', () {
    test('forge -> "forge"', () {
      expect(mrpackLoaderKey(Loader.forge), 'forge');
    });
    test('neoforge -> "neoforge"', () {
      expect(mrpackLoaderKey(Loader.neoforge), 'neoforge');
    });
    test('fabric -> "fabric-loader"', () {
      expect(mrpackLoaderKey(Loader.fabric), 'fabric-loader');
    });
  });

  group('mrpackEnv', () {
    test('both maps to required/required', () {
      expect(mrpackEnv(Environment.both), {
        'client': 'required',
        'server': 'required',
      });
    });
    test('client maps to required/unsupported', () {
      expect(mrpackEnv(Environment.client), {
        'client': 'required',
        'server': 'unsupported',
      });
    });
    test('server maps to unsupported/required', () {
      expect(mrpackEnv(Environment.server), {
        'client': 'unsupported',
        'server': 'required',
      });
    });
  });

  group('buildIndex', () {
    test('modrinth-only lock produces a complete MrpackIndex', () {
      final lock = _lock(
        mods: {
          'sodium': _modrinth(
            slug: 'sodium',
            name: 'sodium-0.6.0.jar',
            projectId: 'AANobbMI',
            versionId: 'abcdef',
          ),
        },
        shaders: {
          'complementary': _modrinth(
            slug: 'complementary',
            name: 'complementary-r5.7.1.zip',
            projectId: 'COMP',
            versionId: 'V1',
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      expect(idx.game, 'minecraft');
      expect(idx.formatVersion, 1);
      expect(idx.versionId, '0.1.0');
      expect(idx.name, 'Pack');
      expect(idx.summary, 'a pack');
      expect(idx.dependencies, {
        'minecraft': '1.21.1',
        'fabric-loader': '0.17.3',
      });
      expect(idx.files, hasLength(2));
      final sodium = idx.files.firstWhere(
        (f) => f.path.endsWith('sodium-0.6.0.jar'),
      );
      expect(sodium.path, 'mods/sodium-0.6.0.jar');
      expect(sodium.hashes, {'sha1': '0123456789abcdef', 'sha512': 'deadbeef'});
      expect(sodium.env, {'client': 'required', 'server': 'required'});
      expect(sodium.fileSize, 1024);
      expect(
        sodium.downloads.single,
        'https://cdn.modrinth.com/data/AANobbMI/versions/abcdef/sodium-0.6.0.jar',
      );
      final shader = idx.files.firstWhere(
        (f) => f.path.startsWith('shaderpacks/'),
      );
      expect(shader.path, 'shaderpacks/complementary-r5.7.1.zip');
    });

    test('uses LockedFile.url verbatim when present (no canonical synth)', () {
      final lock = _lock(
        mods: {
          'sodium': _modrinth(
            slug: 'sodium',
            name: 'sodium-0.6.0.jar',
            projectId: 'AANobbMI',
            versionId: 'abcdef',
            url:
                'https://cdn.modrinth.com/data/AANobbMI/versions/abcdef/EXACT.jar',
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      expect(
        idx.files.single.downloads.single,
        'https://cdn.modrinth.com/data/AANobbMI/versions/abcdef/EXACT.jar',
      );
    });

    test('synthesizes canonical Modrinth URL with URL-encoded filename', () {
      final lock = _lock(
        mods: {
          'cwb-fabric': _modrinth(
            slug: 'cwb-fabric',
            name: 'cwb-fabric-3.0.0+mc1.21.5.jar',
            projectId: 'ETlrkaYF',
            versionId: 'wXhtL4fb',
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      // `+` must percent-encode to `%2B` in the path segment.
      expect(
        idx.files.single.downloads.single,
        'https://cdn.modrinth.com/data/ETlrkaYF/versions/wXhtL4fb/cwb-fabric-3.0.0%2Bmc1.21.5.jar',
      );
    });

    test('url/path mods are excluded from files[] (they go to overrides)', () {
      final lock = _lock(
        mods: {
          'sodium': _modrinth(slug: 'sodium'),
          'local-mod': _path(slug: 'local-mod'),
          'remote-mod': _url(slug: 'remote-mod'),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      expect(idx.files, hasLength(1));
      expect(idx.files.single.path, contains('mod-1.0.0.jar'));
    });

    test('per-entry env maps into per-file env in the index', () {
      final lock = _lock(
        mods: {
          'client-only': _modrinth(
            slug: 'client-only',
            env: Environment.client,
          ),
          'server-only': _modrinth(
            slug: 'server-only',
            env: Environment.server,
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      final c = idx.files.firstWhere(
        (f) =>
            f.path.contains('mod-1.0.0.jar') &&
            f.env['client'] == 'required' &&
            f.env['server'] == 'unsupported',
      );
      final s = idx.files.firstWhere(
        (f) =>
            f.path.contains('mod-1.0.0.jar') &&
            f.env['client'] == 'unsupported' &&
            f.env['server'] == 'required',
      );
      expect(c, isNotNull);
      expect(s, isNotNull);
    });

    test(
      '--publishable rejects url-source MOD with each offending slug listed',
      () {
        final lock = _lock(
          mods: {
            'sodium': _modrinth(slug: 'sodium'),
            'remote-mod': _url(slug: 'remote-mod'),
            'local-mod': _path(slug: 'local-mod'),
          },
        );
        expect(
          () => buildIndex(
            yaml: _yaml(),
            lock: lock,
            target: PackTarget.combined,
            publishable: true,
          ),
          throwsA(
            isA<ValidationError>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('--publishable refused'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('local-mod (path)'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('remote-mod (url)'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('sodium (modrinth)')),
                ),
          ),
        );
      },
    );

    test(
      '--publishable allows url-source RESOURCE PACK (different policy)',
      () {
        final lock = _lock(
          mods: {'sodium': _modrinth(slug: 'sodium')},
          resourcePacks: {'custom-rp': _url(slug: 'custom-rp')},
        );
        // Should NOT throw — only mods are gated by --publishable.
        final idx = buildIndex(
          yaml: _yaml(),
          lock: lock,
          target: PackTarget.combined,
          publishable: true,
        );
        expect(idx.files, hasLength(1)); // RP went to overrides, not files[].
      },
    );

    test('--publishable allows url-source DATA PACK and SHADER too', () {
      final lock = _lock(
        dataPacks: {'custom-dp': _url(slug: 'custom-dp')},
        shaders: {'custom-shader': _path(slug: 'custom-shader')},
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: true,
      );
      expect(idx.files, isEmpty);
    });

    test(
      'legacy "stable" / "latest" loader version in the lock is rejected',
      () {
        final lock = _lock(loaderVersion: 'stable');
        expect(
          () => buildIndex(
            yaml: _yaml(),
            lock: lock,
            target: PackTarget.combined,
            publishable: false,
          ),
          throwsA(
            isA<ValidationError>().having(
              (e) => e.message,
              'message',
              contains('no concrete loader version'),
            ),
          ),
        );
      },
    );

    test('missing sha1 on a modrinth entry is rejected with a re-run hint', () {
      final entryWithoutSha1 = LockedEntry(
        slug: 'sodium',
        sourceKind: LockedSourceKind.modrinth,
        projectId: 'PID',
        versionId: 'VID',
        file: const LockedFile(
          name: 'sodium-0.6.0.jar',
          sha512: 'deadbeef',
          size: 1024,
        ),
      );
      final lock = _lock(mods: {'sodium': entryWithoutSha1});
      expect(
        () => buildIndex(
          yaml: _yaml(),
          lock: lock,
          target: PackTarget.combined,
          publishable: false,
        ),
        throwsA(
          isA<ValidationError>()
              .having((e) => e.message, 'message', contains('missing sha1'))
              .having((e) => e.message, 'message', contains('gitrinth get')),
        ),
      );
    });

    test('client target drops server-only modrinth files from files[]', () {
      final lock = _lock(
        mods: {
          'shared': _modrinth(slug: 'shared', name: 'shared.jar'),
          'server-only': _modrinth(
            slug: 'server-only',
            name: 'server.jar',
            env: Environment.server,
          ),
          'client-only': _modrinth(
            slug: 'client-only',
            name: 'client.jar',
            env: Environment.client,
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.client,
        publishable: false,
      );
      final names = idx.files.map((f) => p.basename(f.path)).toSet();
      expect(names, {'shared.jar', 'client.jar'});
      expect(names, isNot(contains('server.jar')));
    });

    test('server target drops client-only modrinth files from files[]', () {
      final lock = _lock(
        mods: {
          'shared': _modrinth(slug: 'shared', name: 'shared.jar'),
          'server-only': _modrinth(
            slug: 'server-only',
            name: 'server.jar',
            env: Environment.server,
          ),
          'client-only': _modrinth(
            slug: 'client-only',
            name: 'client.jar',
            env: Environment.client,
          ),
        },
        shaders: {
          'shader': _modrinth(
            slug: 'shader',
            name: 'shader.zip',
            env: Environment.client,
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.server,
        publishable: false,
      );
      final names = idx.files.map((f) => p.basename(f.path)).toSet();
      // shared survives; client-only and the shader (forced client) are dropped.
      expect(names, {'shared.jar', 'server.jar'});
    });

    test(
      'combined target keeps every entry (regression of pre-split behavior)',
      () {
        final lock = _lock(
          mods: {
            'shared': _modrinth(slug: 'shared', name: 'shared.jar'),
            'server-only': _modrinth(
              slug: 'server-only',
              name: 'server.jar',
              env: Environment.server,
            ),
            'client-only': _modrinth(
              slug: 'client-only',
              name: 'client.jar',
              env: Environment.client,
            ),
          },
        );
        final idx = buildIndex(
          yaml: _yaml(),
          lock: lock,
          target: PackTarget.combined,
          publishable: false,
        );
        expect(idx.files.map((f) => p.basename(f.path)).toSet(), {
          'shared.jar',
          'server.jar',
          'client.jar',
        });
      },
    );

    test('loader-key map is respected per-loader', () {
      final forge = buildIndex(
        yaml: _yaml(),
        lock: _lock(loader: Loader.forge, loaderVersion: '52.0.45'),
        target: PackTarget.combined,
        publishable: false,
      );
      expect(forge.dependencies, {'minecraft': '1.21.1', 'forge': '52.0.45'});

      final neoforge = buildIndex(
        yaml: _yaml(),
        lock: _lock(loader: Loader.neoforge, loaderVersion: '21.1.50'),
        target: PackTarget.combined,
        publishable: false,
      );
      expect(neoforge.dependencies, {
        'minecraft': '1.21.1',
        'neoforge': '21.1.50',
      });
    });
  });

  group('collectOverrides', () {
    test('routes url/path entries into overrides/<subdir>/<filename>', () {
      final lock = _lock(
        mods: {
          'sodium': _modrinth(slug: 'sodium'),
          'local-mod': _path(slug: 'local-mod', path: '/abs/local-mod.jar'),
        },
        resourcePacks: {
          'custom-rp': _url(
            slug: 'custom-rp',
            url: 'https://example.com/rp.zip',
            filename: 'rp.zip',
          ),
        },
      );
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(plan.entries, hasLength(2));
      expect(plan.hasModOverrides, isTrue);
      final modPlan = plan.entries.firstWhere((p) => p.slug == 'local-mod');
      expect(modPlan.zipPath, 'overrides/mods/local-mod.jar');
      expect(modPlan.section, Section.mods);
      expect(modPlan.sourceKind, 'path');
      final rpPlan = plan.entries.firstWhere((p) => p.slug == 'custom-rp');
      expect(rpPlan.zipPath, 'overrides/resourcepacks/rp.zip');
      expect(rpPlan.section, Section.resourcePacks);
      expect(rpPlan.sourceKind, 'url');
    });

    test(
      'hasModOverrides is false when only non-mod sections have overrides',
      () {
        final lock = _lock(
          resourcePacks: {'custom-rp': _url(slug: 'custom-rp')},
        );
        final cache = GitrinthCache(root: '/tmp/fakeroot');
        final plan = collectOverrides(
          lock: lock,
          cache: cache,
          projectDir: '/proj',
          target: PackTarget.combined,
        );
        expect(plan.entries, hasLength(1));
        expect(plan.hasModOverrides, isFalse);
      },
    );

    test('returns empty plan when every entry is a modrinth source', () {
      final lock = _lock(mods: {'sodium': _modrinth(slug: 'sodium')});
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(plan.entries, isEmpty);
      expect(plan.hasModOverrides, isFalse);
    });

    test('routes server-only url mods to server-overrides/mods/', () {
      final lock = _lock(
        mods: {
          'server-mod': _url(
            slug: 'server-mod',
            filename: 'server.jar',
            env: Environment.server,
          ),
        },
      );
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(plan.entries.single.zipPath, 'server-overrides/mods/server.jar');
      // Still counts as a mod override for the permissions warning.
      expect(plan.hasModOverrides, isTrue);
    });

    test('routes client-only path mods to client-overrides/mods/', () {
      final lock = _lock(
        mods: {
          'client-mod': _path(
            slug: 'client-mod',
            path: '/abs/client.jar',
            env: Environment.client,
          ),
        },
      );
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(plan.entries.single.zipPath, 'client-overrides/mods/client.jar');
    });

    test(
      'shaders (forced client at the section level) land in client-overrides/shaderpacks/',
      () {
        final lock = _lock(
          shaders: {
            'custom-shader': _path(
              slug: 'custom-shader',
              path: '/abs/shader.zip',
              env: Environment.client, // forced by parser at the section level
            ),
          },
        );
        final cache = GitrinthCache(root: '/tmp/fakeroot');
        final plan = collectOverrides(
          lock: lock,
          cache: cache,
          projectDir: '/proj',
          target: PackTarget.combined,
        );
        expect(
          plan.entries.single.zipPath,
          'client-overrides/shaderpacks/shader.zip',
        );
        expect(plan.hasModOverrides, isFalse);
      },
    );

    test('client target drops server-only overrides entirely', () {
      final lock = _lock(
        mods: {
          'both-mod': _path(slug: 'both-mod', path: '/a/both.jar'),
          'server-only': _path(
            slug: 'server-only',
            path: '/a/server.jar',
            env: Environment.server,
          ),
        },
      );
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.client,
      );
      expect(plan.entries.map((e) => e.slug), ['both-mod']);
      expect(plan.hasModOverrides, isTrue);
    });

    test('server target drops client-only overrides entirely', () {
      final lock = _lock(
        mods: {
          'both-mod': _path(slug: 'both-mod', path: '/a/both.jar'),
          'client-only': _path(
            slug: 'client-only',
            path: '/a/client.jar',
            env: Environment.client,
          ),
        },
        shaders: {
          'sh': _path(slug: 'sh', path: '/a/sh.zip', env: Environment.client),
        },
      );
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.server,
      );
      // both-mod survives, client-only and the shader are dropped.
      expect(plan.entries.map((e) => e.slug), ['both-mod']);
    });

    test('mixed envs in one section spread across all three roots', () {
      final lock = _lock(
        mods: {
          'both-mod': _path(slug: 'both-mod', path: '/a/both.jar'),
          'client-mod': _path(
            slug: 'client-mod',
            path: '/a/client.jar',
            env: Environment.client,
          ),
          'server-mod': _path(
            slug: 'server-mod',
            path: '/a/server.jar',
            env: Environment.server,
          ),
        },
      );
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      final byZip = {for (final e in plan.entries) e.slug: e.zipPath};
      expect(byZip['both-mod'], 'overrides/mods/both.jar');
      expect(byZip['client-mod'], 'client-overrides/mods/client.jar');
      expect(byZip['server-mod'], 'server-overrides/mods/server.jar');
    });
  });
}
