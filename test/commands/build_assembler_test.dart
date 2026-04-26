import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/build_assembler.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';

LockedEntry _modrinth(
  String slug, {
  SideEnv client = SideEnv.required,
  SideEnv server = SideEnv.required,
}) => LockedEntry(
  slug: slug,
  sourceKind: LockedSourceKind.modrinth,
  projectId: 'PRJ',
  versionId: 'VER',
  file: LockedFile(
    name: '$slug.jar',
    url: 'https://example.invalid/$slug.jar',
    sha512: 'a' * 128,
    size: 0,
  ),
  client: client,
  server: server,
);

LockedEntry _url(
  String slug, {
  SideEnv client = SideEnv.required,
  SideEnv server = SideEnv.required,
}) => LockedEntry(
  slug: slug,
  sourceKind: LockedSourceKind.url,
  file: LockedFile(
    name: '$slug.jar',
    url: 'https://example.invalid/$slug.jar',
    sha512: 'b' * 128,
  ),
  client: client,
  server: server,
);

LockedEntry _path(
  String slug,
  String path, {
  SideEnv client = SideEnv.required,
  SideEnv server = SideEnv.required,
}) => LockedEntry(
  slug: slug,
  sourceKind: LockedSourceKind.path,
  path: path,
  client: client,
  server: server,
);

void main() {
  group('targetEnvironments', () {
    test('null and "both" return both envs', () {
      expect(targetEnvironments(null), [BuildEnv.client, BuildEnv.server]);
      expect(targetEnvironments('both'), [BuildEnv.client, BuildEnv.server]);
    });

    test('"client" / "server" return their single env', () {
      expect(targetEnvironments('client'), [BuildEnv.client]);
      expect(targetEnvironments('server'), [BuildEnv.server]);
    });

    test('unknown value throws UsageError', () {
      expect(
        () => targetEnvironments('both-and-more'),
        throwsA(isA<UsageError>()),
      );
    });
  });

  group('buildSubdirFor', () {
    test('shaders ship client-only when server is unsupported', () {
      final shader = _modrinth(
        'cr',
        client: SideEnv.required,
        server: SideEnv.unsupported,
      );
      expect(
        buildSubdirFor(Section.shaders, BuildEnv.client, shader),
        'shaderpacks',
      );
      expect(buildSubdirFor(Section.shaders, BuildEnv.server, shader), isNull);
    });

    test('mods with both sides required ship to mods/ on both envs', () {
      final mod = _modrinth('jei');
      expect(buildSubdirFor(Section.mods, BuildEnv.client, mod), 'mods');
      expect(buildSubdirFor(Section.mods, BuildEnv.server, mod), 'mods');
    });

    test('mods with client-only state skip server build', () {
      final mod = _modrinth(
        'iris',
        client: SideEnv.required,
        server: SideEnv.unsupported,
      );
      expect(buildSubdirFor(Section.mods, BuildEnv.client, mod), 'mods');
      expect(buildSubdirFor(Section.mods, BuildEnv.server, mod), isNull);
    });

    test('mods with server-only state skip client build', () {
      final mod = _modrinth(
        'netherportalfix',
        client: SideEnv.unsupported,
        server: SideEnv.required,
      );
      expect(buildSubdirFor(Section.mods, BuildEnv.client, mod), isNull);
      expect(buildSubdirFor(Section.mods, BuildEnv.server, mod), 'mods');
    });

    test('data_packs route by per-side state into global_packs/', () {
      final required = _modrinth('terralith');
      expect(
        buildSubdirFor(Section.dataPacks, BuildEnv.client, required),
        'global_packs/required_data',
      );
      expect(
        buildSubdirFor(Section.dataPacks, BuildEnv.server, required),
        'global_packs/required_data',
      );
      final clientOptional = _modrinth(
        'cosmetic-pack',
        client: SideEnv.optional,
        server: SideEnv.required,
      );
      expect(
        buildSubdirFor(Section.dataPacks, BuildEnv.client, clientOptional),
        'global_packs/optional_data',
      );
      expect(
        buildSubdirFor(Section.dataPacks, BuildEnv.server, clientOptional),
        'global_packs/required_data',
      );
    });

    test(
      'resource_packs default (client optional, server unsupported) lands in '
      'global_packs/optional_resources on client only',
      () {
        final faithful = _modrinth(
          'faithful-32x',
          client: SideEnv.optional,
          server: SideEnv.unsupported,
        );
        expect(
          buildSubdirFor(Section.resourcePacks, BuildEnv.client, faithful),
          'global_packs/optional_resources',
        );
        expect(
          buildSubdirFor(Section.resourcePacks, BuildEnv.server, faithful),
          isNull,
        );
      },
    );

    test('resource_packs with client: required land in required_resources', () {
      final branding = _modrinth(
        'branding-pack',
        client: SideEnv.required,
        server: SideEnv.unsupported,
      );
      expect(
        buildSubdirFor(Section.resourcePacks, BuildEnv.client, branding),
        'global_packs/required_resources',
      );
    });
  });

  group('mrpackSubdirFor', () {
    test('keeps the historical mrpack paths regardless of per-side state', () {
      expect(mrpackSubdirFor(Section.mods), 'mods');
      expect(mrpackSubdirFor(Section.resourcePacks), 'resourcepacks');
      expect(mrpackSubdirFor(Section.dataPacks), 'datapacks');
      expect(mrpackSubdirFor(Section.shaders), 'shaderpacks');
    });
  });

  group('resolveSourcePath', () {
    final cache = GitrinthCache(root: p.join('tmpcache', 'root'));

    test('modrinth source resolves via cache.modrinthPath', () {
      final path = resolveSourcePath(
        cache,
        _modrinth('jei'),
        projectDir: p.join('some', 'proj'),
      );
      expect(
        path,
        cache.modrinthPath(
          projectId: 'PRJ',
          versionId: 'VER',
          filename: 'jei.jar',
        ),
      );
    });

    test('url source resolves via cache.urlPath keyed by sha512', () {
      final entry = _url('custom');
      final path = resolveSourcePath(
        cache,
        entry,
        projectDir: p.join('some', 'proj'),
      );
      expect(
        path,
        cache.urlPath(sha512: entry.file!.sha512!, filename: 'custom.jar'),
      );
    });

    test('path source is joined against projectDir when relative', () {
      final projectDir = p.join(p.separator, 'work', 'pack');
      final path = resolveSourcePath(
        cache,
        _path('local', p.join('mods', 'local.jar')),
        projectDir: projectDir,
      );
      expect(path, p.normalize(p.join(projectDir, 'mods', 'local.jar')));
    });

    test('absolute path source is returned as-is', () {
      final abs = p.join(p.separator, 'abs', 'to', 'mod.jar');
      final path = resolveSourcePath(
        cache,
        _path('abs', abs),
        projectDir: p.join(p.separator, 'elsewhere'),
      );
      expect(path, abs);
    });

    test('modrinth entry missing projectId throws ValidationError', () {
      final broken = LockedEntry(
        slug: 'broken',
        sourceKind: LockedSourceKind.modrinth,
        file: const LockedFile(name: 'broken.jar'),
      );
      expect(
        () => resolveSourcePath(cache, broken, projectDir: '.'),
        throwsA(isA<ValidationError>()),
      );
    });

    test(
      'url entry missing sha512 falls back to the _unverified cache path',
      () {
        final entry = LockedEntry(
          slug: 'unhashed',
          sourceKind: LockedSourceKind.url,
          file: const LockedFile(name: 'unhashed.jar'),
        );
        final path = resolveSourcePath(cache, entry, projectDir: '.');
        expect(path, contains('_unverified'));
        expect(path, contains('unhashed'));
        expect(path, endsWith('unhashed.jar'));
      },
    );
  });

  group('destFilenameFor', () {
    test('uses file.name when available', () {
      expect(destFilenameFor(_modrinth('jei')), 'jei.jar');
    });

    test('falls back to basename of path for path sources', () {
      final entry = _path('local', p.join('mods', 'Local-Mod-1.0.jar'));
      expect(destFilenameFor(entry), 'Local-Mod-1.0.jar');
    });
  });
}
