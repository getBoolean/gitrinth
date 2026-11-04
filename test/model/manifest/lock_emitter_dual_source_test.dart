import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

const _modrinthBlock = LockedModrinthSource(
  projectId: 'mr-pid',
  versionId: 'mr-vid',
  versionNumber: '21.3.0',
  file: LockedFile(
    name: 'jei-21.3.0.jar',
    url: 'https://cdn.modrinth.com/data/mr-pid/versions/mr-vid/jei-21.3.0.jar',
    sha1: 'aabb',
    sha512: 'cafebabe',
    size: 1234567,
  ),
  gameVersions: ['1.21.4', '1.21.5'],
);

const _curseforgeBlock = LockedCurseforgeSource(
  projectId: 238222,
  fileId: 5512345,
  slug: 'jei',
  file: LockedFile(
    name: 'jei-21.3.0.jar',
    url: 'https://edge.forgecdn.net/files/5512/345/jei-21.3.0.jar',
    sha1: 'aabb',
    size: 1234567,
  ),
  gameVersions: ['1.21.4', '1.21.5'],
);

ModsLock _lockWith({
  Map<String, LockedEntry> mods = const {},
  Map<String, LockedEntry> plugins = const {},
}) => ModsLock(
  gitrinthVersion: '0.1.0',
  loader: const LoaderConfig(
    mods: ModLoader.fabric,
    modLoaderVersion: '0.16.0',
  ),
  mcVersion: '1.21.5',
  mods: mods,
  plugins: plugins,
);

void main() {
  group('emit + parse round-trip with per-platform source blocks', () {
    test('dual-source entry: both modrinth and curseforge populate', () {
      final lock = _lockWith(
        mods: {
          'jei': const LockedEntry(
            slug: 'jei',
            kind: LockedEntryKind.resolved,
            version: '21.3.0',
            modrinth: _modrinthBlock,
            curseforge: _curseforgeBlock,
          ),
        },
      );
      final out = emitModsLock(lock);
      expect(out, contains('  jei:'));
      expect(out, contains('    modrinth:'));
      expect(out, contains('      project_id: mr-pid'));
      expect(out, contains('    curseforge:'));
      expect(out, contains('      project_id: 238222'));
      expect(out, contains('      file_id: 5512345'));
      // SHA1 round-trips lowercased.
      expect(out, contains('sha1: aabb'));

      final parsed = parseModsLock(out, filePath: 'mods.lock');
      final entry = parsed.mods['jei']!;
      expect(entry.modrinth!.projectId, 'mr-pid');
      expect(entry.curseforge!.projectId, 238222);
      expect(entry.curseforge!.fileId, 5512345);
      expect(emitModsLock(parsed), out);
    });

    test('modrinth-only entry: curseforge field omitted', () {
      final lock = _lockWith(
        mods: {
          'modrinth-only': const LockedEntry(
            slug: 'modrinth-only',
            kind: LockedEntryKind.resolved,
            version: '21.3.0',
            modrinth: _modrinthBlock,
          ),
        },
      );
      final out = emitModsLock(lock);
      expect(out, contains('    modrinth:'));
      expect(out, isNot(contains('    curseforge:')));

      final parsed = parseModsLock(out, filePath: 'mods.lock');
      expect(parsed.mods['modrinth-only']!.curseforge, isNull);
      expect(parsed.mods['modrinth-only']!.modrinth, isNotNull);
    });

    test('curseforge-only entry: modrinth field omitted', () {
      final lock = _lockWith(
        mods: {
          'cf-only': const LockedEntry(
            slug: 'cf-only',
            kind: LockedEntryKind.resolved,
            version: '21.3.0',
            curseforge: _curseforgeBlock,
          ),
        },
      );
      final out = emitModsLock(lock);
      expect(out, contains('    curseforge:'));
      expect(out, isNot(contains('    modrinth:')));

      final parsed = parseModsLock(out, filePath: 'mods.lock');
      expect(parsed.mods['cf-only']!.modrinth, isNull);
      expect(parsed.mods['cf-only']!.curseforge, isNotNull);
    });

    test('url entry: kind=url with urlFile, no platform blocks', () {
      final lock = _lockWith(
        mods: {
          'manual-jar': const LockedEntry(
            slug: 'manual-jar',
            kind: LockedEntryKind.url,
            url: 'https://example.com/foo-1.0.jar',
            urlFile: LockedFile(name: 'foo-1.0.jar'),
          ),
        },
      );
      final out = emitModsLock(lock);
      expect(out, contains('    kind: url'));
      expect(out, contains('    url: "https://example.com/foo-1.0.jar"'));
      expect(out, isNot(contains('    modrinth:')));
      expect(out, isNot(contains('    curseforge:')));

      final parsed = parseModsLock(out, filePath: 'mods.lock');
      expect(parsed.mods['manual-jar']!.kind, LockedEntryKind.url);
      expect(parsed.mods['manual-jar']!.url, 'https://example.com/foo-1.0.jar');
    });

    test('plugins section emits per-platform blocks the same way', () {
      final lock = ModsLock(
        gitrinthVersion: '0.1.0',
        loader: const LoaderConfig(
          mods: ModLoader.fabric,
          modLoaderVersion: '0.16.0',
          plugins: PluginLoader.paper,
          pluginLoaderVersion: '1.21.5',
        ),
        mcVersion: '1.21.5',
        plugins: const {
          'luckperms': LockedEntry(
            slug: 'luckperms',
            kind: LockedEntryKind.resolved,
            version: '5.4.0',
            modrinth: _modrinthBlock,
            curseforge: _curseforgeBlock,
          ),
        },
      );
      final out = emitModsLock(lock);
      expect(out, contains('plugins:'));
      expect(out, contains('  luckperms:'));
      expect(out, contains('    modrinth:'));
      expect(out, contains('    curseforge:'));

      final parsed = parseModsLock(out, filePath: 'mods.lock');
      expect(parsed.plugins['luckperms']!.modrinth, isNotNull);
      expect(parsed.plugins['luckperms']!.curseforge, isNotNull);
    });

    test(
      'allow_mod_distribution: false survives round-trip and omits file.url',
      () {
        final lock = _lockWith(
          mods: {
            'opaque-cf': const LockedEntry(
              slug: 'opaque-cf',
              kind: LockedEntryKind.resolved,
              version: 'x',
              curseforge: LockedCurseforgeSource(
                projectId: 9999,
                fileId: 100,
                file: LockedFile(name: 'opaque.jar'),
                allowModDistribution: false,
              ),
            ),
          },
        );
        final out = emitModsLock(lock);
        expect(out, contains('allow_mod_distribution: false'));
        // file.url is null, so the emitter omits the url line.
        final cfBlock = out.substring(out.indexOf('    curseforge:'));
        expect(cfBlock, isNot(contains('      url:')));

        final parsed = parseModsLock(out, filePath: 'mods.lock');
        expect(
          parsed.mods['opaque-cf']!.curseforge!.allowModDistribution,
          isFalse,
        );
        expect(parsed.mods['opaque-cf']!.curseforge!.file.url, isNull);
      },
    );
  });
}
