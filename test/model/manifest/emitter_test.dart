import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

void main() {
  ModsLock sample() => const ModsLock(
        gitrinthVersion: '0.1.0',
        loader: LoaderConfig(mods: Loader.neoforge),
        mcVersion: '1.21.1',
        mods: {
          'create': LockedEntry(
            slug: 'create',
            sourceKind: LockedSourceKind.modrinth,
            version: '6.0.10+mc1.21.1',
            projectId: 'LNytGWDc',
            versionId: 'abc123',
            file: LockedFile(
              name: 'create-1.21.1-6.0.10.jar',
              url: 'https://cdn.modrinth.com/data/create.jar',
              sha512: 'AABBCC',
              size: 12345,
            ),
            env: Environment.both,
          ),
          'flywheel': LockedEntry(
            slug: 'flywheel',
            sourceKind: LockedSourceKind.modrinth,
            version: '1.0.0',
            projectId: 'PROJ2',
            versionId: 'VER2',
            file: LockedFile(
              name: 'flywheel.jar',
              url: 'https://cdn.modrinth.com/data/flywheel.jar',
              sha512: '112233',
              size: 10000,
            ),
            auto: true,
          ),
        },
      );

  test('emits deterministic alphabetical ordering with sha512 lower-case', () {
    final out = emitModsLock(sample());
    expect(out, contains('mods:'));
    expect(out, contains('aabbcc')); // lower-cased
    final createIdx = out.indexOf('create:');
    final flywheelIdx = out.indexOf('flywheel:');
    expect(createIdx < flywheelIdx, isTrue, reason: 'alphabetical order');
  });

  test('emit -> parse -> emit is byte-identical', () {
    final lock = sample();
    final once = emitModsLock(lock);
    final parsed = parseModsLock(once, filePath: 'mods.lock');
    final twice = emitModsLock(parsed);
    expect(twice, once);
  });

  test('auto: true is emitted, auto: false is omitted', () {
    final out = emitModsLock(sample());
    final flywheelBlock = out
        .substring(out.indexOf('flywheel:'))
        .split('\n')
        .takeWhile((l) => l.isNotEmpty && (l.startsWith('  ') || l == 'flywheel:'))
        .join('\n');
    expect(flywheelBlock, contains('auto: true'));
    final createBlock = out
        .substring(out.indexOf('create:'), out.indexOf('flywheel:'))
        .trim();
    expect(createBlock, isNot(contains('auto:')));
  });
}
