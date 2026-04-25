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
  SideEnv client = SideEnv.required,
  SideEnv server = SideEnv.required,
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
    client: client,
    server: server,
  );
}

LockedEntry _url({
  required String slug,
  String url = 'https://example.com/x.jar',
  String filename = 'x.jar',
  String sha512 = 'beefcafe',
  SideEnv client = SideEnv.required,
  SideEnv server = SideEnv.required,
}) {
  return LockedEntry(
    slug: slug,
    sourceKind: LockedSourceKind.url,
    file: LockedFile(name: filename, url: url, sha512: sha512),
    client: client,
    server: server,
  );
}

LockedEntry _path({
  required String slug,
  String path = './local.jar',
  SideEnv client = SideEnv.required,
  SideEnv server = SideEnv.required,
}) {
  return LockedEntry(
    slug: slug,
    sourceKind: LockedSourceKind.path,
    path: path,
    client: client,
    server: server,
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

  group('mrpackEnvFor', () {
    test('both required -> required/required', () {
      expect(mrpackEnvFor(SideEnv.required, SideEnv.required), {
        'client': 'required',
        'server': 'required',
      });
    });
    test('client required, server unsupported', () {
      expect(mrpackEnvFor(SideEnv.required, SideEnv.unsupported), {
        'client': 'required',
        'server': 'unsupported',
      });
    });
    test('client unsupported, server required', () {
      expect(mrpackEnvFor(SideEnv.unsupported, SideEnv.required), {
        'client': 'unsupported',
        'server': 'required',
      });
    });
    test('both optional -> optional/optional', () {
      expect(mrpackEnvFor(SideEnv.optional, SideEnv.optional), {
        'client': 'optional',
        'server': 'optional',
      });
    });
    test('asymmetric optional/required passes through verbatim', () {
      expect(mrpackEnvFor(SideEnv.optional, SideEnv.required), {
        'client': 'optional',
        'server': 'required',
      });
      expect(mrpackEnvFor(SideEnv.required, SideEnv.optional), {
        'client': 'required',
        'server': 'optional',
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
            client: SideEnv.required,
            server: SideEnv.unsupported,
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
      expect(shader.env, {'client': 'required', 'server': 'unsupported'});
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

    test('per-side state maps into per-file env in the index', () {
      final lock = _lock(
        mods: {
          'client-only': _modrinth(
            slug: 'client-only',
            client: SideEnv.required,
            server: SideEnv.unsupported,
          ),
          'server-only': _modrinth(
            slug: 'server-only',
            client: SideEnv.unsupported,
            server: SideEnv.required,
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
        final idx = buildIndex(
          yaml: _yaml(),
          lock: lock,
          target: PackTarget.combined,
          publishable: true,
        );
        expect(idx.files, hasLength(1));
      },
    );

    test('--publishable allows url-source DATA PACK and SHADER too', () {
      final lock = _lock(
        dataPacks: {'custom-dp': _url(slug: 'custom-dp')},
        shaders: {
          'custom-shader': _path(
            slug: 'custom-shader',
            client: SideEnv.required,
            server: SideEnv.unsupported,
          ),
        },
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
            client: SideEnv.unsupported,
            server: SideEnv.required,
          ),
          'client-only': _modrinth(
            slug: 'client-only',
            name: 'client.jar',
            client: SideEnv.required,
            server: SideEnv.unsupported,
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
            client: SideEnv.unsupported,
            server: SideEnv.required,
          ),
          'client-only': _modrinth(
            slug: 'client-only',
            name: 'client.jar',
            client: SideEnv.required,
            server: SideEnv.unsupported,
          ),
        },
        shaders: {
          'shader': _modrinth(
            slug: 'shader',
            name: 'shader.zip',
            client: SideEnv.required,
            server: SideEnv.unsupported,
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
              client: SideEnv.unsupported,
              server: SideEnv.required,
            ),
            'client-only': _modrinth(
              slug: 'client-only',
              name: 'client.jar',
              client: SideEnv.required,
              server: SideEnv.unsupported,
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

    test('per-side optional state produces env: optional in files[]', () {
      final lock = _lock(
        mods: {
          'distanthorizons': _modrinth(
            slug: 'distanthorizons',
            name: 'distanthorizons-2.3.0-b.jar',
            projectId: 'uCdwusMi',
            versionId: 'abc123',
            client: SideEnv.optional,
            server: SideEnv.optional,
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      expect(idx.files.single.env, {
        'client': 'optional',
        'server': 'optional',
      });
    });

    test('client-only optional entry stays optional in client target', () {
      final lock = _lock(
        mods: {
          'distanthorizons': _modrinth(
            slug: 'distanthorizons',
            name: 'distanthorizons.jar',
            projectId: 'uCdwusMi',
            versionId: 'abc123',
            client: SideEnv.optional,
            server: SideEnv.unsupported,
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.client,
        publishable: false,
      );
      expect(idx.files, hasLength(1));
      expect(idx.files.single.env, {
        'client': 'optional',
        'server': 'unsupported',
      });
    });

    test('data_packs in files[] keep historical "datapacks/" path', () {
      final lock = _lock(
        dataPacks: {
          'terralith': _modrinth(
            slug: 'terralith',
            name: 'Terralith.zip',
            projectId: 'TPID',
            versionId: 'TVID',
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      expect(idx.files.single.path, 'datapacks/Terralith.zip');
    });

    test('resource_packs in files[] keep historical "resourcepacks/" path', () {
      final lock = _lock(
        resourcePacks: {
          'faithful': _modrinth(
            slug: 'faithful',
            name: 'Faithful.zip',
            projectId: 'FPID',
            versionId: 'FVID',
            client: SideEnv.optional,
            server: SideEnv.unsupported,
          ),
        },
      );
      final idx = buildIndex(
        yaml: _yaml(),
        lock: lock,
        target: PackTarget.combined,
        publishable: false,
      );
      expect(idx.files.single.path, 'resourcepacks/Faithful.zip');
      expect(idx.files.single.env, {
        'client': 'optional',
        'server': 'unsupported',
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
            client: SideEnv.optional,
            server: SideEnv.optional,
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
          resourcePacks: {
            'custom-rp': _url(
              slug: 'custom-rp',
              client: SideEnv.optional,
              server: SideEnv.unsupported,
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
            client: SideEnv.unsupported,
            server: SideEnv.required,
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
      expect(plan.hasModOverrides, isTrue);
    });

    test('routes client-only path mods to client-overrides/mods/', () {
      final lock = _lock(
        mods: {
          'client-mod': _path(
            slug: 'client-mod',
            path: '/abs/client.jar',
            client: SideEnv.required,
            server: SideEnv.unsupported,
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
      'shaders (server unsupported by default) land in '
      'client-overrides/shaderpacks/',
      () {
        final lock = _lock(
          shaders: {
            'custom-shader': _path(
              slug: 'custom-shader',
              path: '/abs/shader.zip',
              client: SideEnv.required,
              server: SideEnv.unsupported,
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
            client: SideEnv.unsupported,
            server: SideEnv.required,
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
            client: SideEnv.required,
            server: SideEnv.unsupported,
          ),
        },
        shaders: {
          'sh': _path(
            slug: 'sh',
            path: '/a/sh.zip',
            client: SideEnv.required,
            server: SideEnv.unsupported,
          ),
        },
      );
      final cache = GitrinthCache(root: '/tmp/fakeroot');
      final plan = collectOverrides(
        lock: lock,
        cache: cache,
        projectDir: '/proj',
        target: PackTarget.server,
      );
      expect(plan.entries.map((e) => e.slug), ['both-mod']);
    });

    test('mixed sides in one section spread across all three roots', () {
      final lock = _lock(
        mods: {
          'both-mod': _path(slug: 'both-mod', path: '/a/both.jar'),
          'client-mod': _path(
            slug: 'client-mod',
            path: '/a/client.jar',
            client: SideEnv.required,
            server: SideEnv.unsupported,
          ),
          'server-mod': _path(
            slug: 'server-mod',
            path: '/a/server.jar',
            client: SideEnv.unsupported,
            server: SideEnv.required,
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

  group('collectOverrides files: section', () {
    ModsLock filesLock(Map<String, LockedFileEntry> files) => ModsLock(
      gitrinthVersion: '0.1.0',
      loader: const LoaderConfig(mods: Loader.fabric, modsVersion: '0.17.3'),
      mcVersion: '1.21.1',
      files: files,
    );

    test('routes both-sides files: entries to overrides/<destination>', () {
      final lock = filesLock({
        'config/sodium-options.json': const LockedFileEntry(
          destination: 'config/sodium-options.json',
          sourcePath: './presets/sodium-options.json',
          preserve: true,
        ),
      });
      final plan = collectOverrides(
        lock: lock,
        cache: GitrinthCache(root: '/tmp/fakeroot'),
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(plan.entries, hasLength(1));
      final e = plan.entries.single;
      expect(e.section, isNull);
      expect(e.sourceKind, 'file');
      expect(e.zipPath, 'overrides/config/sodium-options.json');
      expect(
        e.sourcePath,
        endsWith(p.join('proj', 'presets', 'sodium-options.json')),
      );
    });

    test('routes client-only files: entries to client-overrides/', () {
      final lock = filesLock({
        'config/options.txt': const LockedFileEntry(
          destination: 'config/options.txt',
          sourcePath: './options.txt',
          server: SideEnv.unsupported,
        ),
      });
      final plan = collectOverrides(
        lock: lock,
        cache: GitrinthCache(root: '/tmp/fakeroot'),
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(
        plan.entries.single.zipPath,
        'client-overrides/config/options.txt',
      );
    });

    test('routes server-only files: entries to server-overrides/', () {
      final lock = filesLock({
        'kubejs/server_scripts/loot.js': const LockedFileEntry(
          destination: 'kubejs/server_scripts/loot.js',
          sourcePath: './loot.js',
          client: SideEnv.unsupported,
        ),
      });
      final plan = collectOverrides(
        lock: lock,
        cache: GitrinthCache(root: '/tmp/fakeroot'),
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(
        plan.entries.single.zipPath,
        'server-overrides/kubejs/server_scripts/loot.js',
      );
    });

    test('PackTarget.client drops server-only files: entries', () {
      final lock = filesLock({
        'kubejs/server_scripts/loot.js': const LockedFileEntry(
          destination: 'kubejs/server_scripts/loot.js',
          sourcePath: './loot.js',
          client: SideEnv.unsupported,
        ),
      });
      final plan = collectOverrides(
        lock: lock,
        cache: GitrinthCache(root: '/tmp/fakeroot'),
        projectDir: '/proj',
        target: PackTarget.client,
      );
      expect(plan.entries, isEmpty);
    });

    test('PackTarget.server drops client-only files: entries', () {
      final lock = filesLock({
        'config/options.txt': const LockedFileEntry(
          destination: 'config/options.txt',
          sourcePath: './options.txt',
          server: SideEnv.unsupported,
        ),
      });
      final plan = collectOverrides(
        lock: lock,
        cache: GitrinthCache(root: '/tmp/fakeroot'),
        projectDir: '/proj',
        target: PackTarget.server,
      );
      expect(plan.entries, isEmpty);
    });

    test('files: entries do not set hasModOverrides', () {
      final lock = filesLock({
        'config/options.txt': const LockedFileEntry(
          destination: 'config/options.txt',
          sourcePath: './options.txt',
        ),
      });
      final plan = collectOverrides(
        lock: lock,
        cache: GitrinthCache(root: '/tmp/fakeroot'),
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(plan.hasModOverrides, isFalse);
    });

    test('rejects `..` segments in destination as defense-in-depth', () {
      // Schema/parser already block this; the assembler re-asserts in
      // case a stale or hand-written lock smuggles one through.
      final lock = filesLock({
        '../escape.txt': const LockedFileEntry(
          destination: '../escape.txt',
          sourcePath: './escape.txt',
        ),
      });
      expect(
        () => collectOverrides(
          lock: lock,
          cache: GitrinthCache(root: '/tmp/fakeroot'),
          projectDir: '/proj',
          target: PackTarget.combined,
        ),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('..'),
          ),
        ),
      );
    });

    test('rejects absolute destination as defense-in-depth', () {
      final lock = filesLock({
        '/etc/foo.toml': const LockedFileEntry(
          destination: '/etc/foo.toml',
          sourcePath: './foo.toml',
        ),
      });
      expect(
        () => collectOverrides(
          lock: lock,
          cache: GitrinthCache(root: '/tmp/fakeroot'),
          projectDir: '/proj',
          target: PackTarget.combined,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('coexists with mod overrides without setting hasModOverrides on files', () {
      final lock = ModsLock(
        gitrinthVersion: '0.1.0',
        loader: const LoaderConfig(mods: Loader.fabric, modsVersion: '0.17.3'),
        mcVersion: '1.21.1',
        mods: {
          'local-mod': _path(slug: 'local-mod', path: '/a/local.jar'),
        },
        files: const {
          'config/options.txt': LockedFileEntry(
            destination: 'config/options.txt',
            sourcePath: './options.txt',
          ),
        },
      );
      final plan = collectOverrides(
        lock: lock,
        cache: GitrinthCache(root: '/tmp/fakeroot'),
        projectDir: '/proj',
        target: PackTarget.combined,
      );
      expect(plan.hasModOverrides, isTrue, reason: 'mod entry sets the flag');
      // Verify both mod and files entries are in the plan, with the
      // mod entry tagged Section.mods and the files entry tagged null.
      final modEntry = plan.entries.firstWhere((e) => e.slug == 'local-mod');
      final fileEntry =
          plan.entries.firstWhere((e) => e.slug == 'config/options.txt');
      expect(modEntry.section, Section.mods);
      expect(fileEntry.section, isNull);
    });
  });
}
