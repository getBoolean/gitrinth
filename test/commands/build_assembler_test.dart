import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/commands/build_assembler.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';

LockedEntry _modrinth(String slug, {Environment env = Environment.both}) =>
    LockedEntry(
      slug: slug,
      sourceKind: LockedSourceKind.modrinth,
      projectId: 'PRJ',
      versionId: 'VER',
      file: LockedFile(
        name: '$slug.jar',
        url: 'https://example.invalid/$slug.jar',
        sha512: 'a' * 128, // 64-byte hex, matches expected sha512 length
        size: 0,
      ),
      env: env,
    );

LockedEntry _url(String slug, {Environment env = Environment.both}) =>
    LockedEntry(
      slug: slug,
      sourceKind: LockedSourceKind.url,
      file: LockedFile(
        name: '$slug.jar',
        url: 'https://example.invalid/$slug.jar',
        sha512: 'b' * 128,
      ),
      env: env,
    );

LockedEntry _path(
  String slug,
  String path, {
  Environment env = Environment.both,
}) => LockedEntry(
  slug: slug,
  sourceKind: LockedSourceKind.path,
  path: path,
  env: env,
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

  group('shouldIncludeEntry', () {
    test('shaders are client-only regardless of entry env', () {
      final shader = _modrinth('cr', env: Environment.both);
      expect(
        shouldIncludeEntry(Section.shaders, shader, BuildEnv.client),
        isTrue,
      );
      expect(
        shouldIncludeEntry(Section.shaders, shader, BuildEnv.server),
        isFalse,
      );
    });

    test('mods with env=both ship to both sides', () {
      final mod = _modrinth('jei');
      expect(shouldIncludeEntry(Section.mods, mod, BuildEnv.client), isTrue);
      expect(shouldIncludeEntry(Section.mods, mod, BuildEnv.server), isTrue);
    });

    test('mods with env=client ship only client-side', () {
      final mod = _modrinth('iris', env: Environment.client);
      expect(shouldIncludeEntry(Section.mods, mod, BuildEnv.client), isTrue);
      expect(shouldIncludeEntry(Section.mods, mod, BuildEnv.server), isFalse);
    });

    test('mods with env=server ship only server-side', () {
      final mod = _modrinth('netherportalfix', env: Environment.server);
      expect(shouldIncludeEntry(Section.mods, mod, BuildEnv.client), isFalse);
      expect(shouldIncludeEntry(Section.mods, mod, BuildEnv.server), isTrue);
    });

    test('resource_packs and data_packs partition the same way as mods', () {
      final rp = _modrinth('rp', env: Environment.client);
      final dp = _modrinth('dp', env: Environment.server);
      expect(
        shouldIncludeEntry(Section.resourcePacks, rp, BuildEnv.client),
        isTrue,
      );
      expect(
        shouldIncludeEntry(Section.resourcePacks, rp, BuildEnv.server),
        isFalse,
      );
      expect(
        shouldIncludeEntry(Section.dataPacks, dp, BuildEnv.client),
        isFalse,
      );
      expect(
        shouldIncludeEntry(Section.dataPacks, dp, BuildEnv.server),
        isTrue,
      );
    });
  });

  group('outputSubdirFor', () {
    test('maps sections to launcher-style directory names', () {
      expect(outputSubdirFor(Section.mods), 'mods');
      expect(outputSubdirFor(Section.resourcePacks), 'resourcepacks');
      expect(outputSubdirFor(Section.dataPacks), 'datapacks');
      expect(outputSubdirFor(Section.shaders), 'shaderpacks');
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
        // Mirrors the downloader: when a url-source artifact has no
        // sha512 yet, it lives at <cache>/url/_unverified/<slug>/<name>.
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
