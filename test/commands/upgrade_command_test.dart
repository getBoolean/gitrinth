import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  late Directory tempRoot;
  late Directory packDir;
  late Directory cacheDir;
  late FakeModrinth modrinth;
  late Map<String, String> env;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_upgrade_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
    cacheDir = Directory(p.join(tempRoot.path, 'cache'))..createSync();
    modrinth = FakeModrinth();
    await modrinth.start();
    env = {
      'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
      'GITRINTH_CACHE': cacheDir.path,
    };
  });

  tearDown(() async {
    await modrinth.stop();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<void> writeManifest(String body) async {
    File(p.join(packDir.path, 'mods.yaml')).writeAsStringSync(body);
  }

  String readLock() =>
      File(p.join(packDir.path, 'mods.lock')).readAsStringSync();

  String readManifest() =>
      File(p.join(packDir.path, 'mods.yaml')).readAsStringSync();

  Future<CapturedOutput> runGet() =>
      runCli(['-C', packDir.path, 'get'], environment: env);

  Future<CapturedOutput> runUpgrade(List<String> extra) =>
      runCli(['-C', packDir.path, 'upgrade', ...extra], environment: env);

  test('upgrade-all bumps every mod to newest within constraint', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0')
      ..registerVersion(slug: 'b', versionNumber: '2.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
  b: ^2.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.5.0')
      ..registerVersion(slug: 'b', versionNumber: '2.7.3');

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, contains('version: 2.7.3'));
  });

  test('subset upgrade bumps only the named slug', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0')
      ..registerVersion(slug: 'b', versionNumber: '2.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
  b: ^2.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.5.0')
      ..registerVersion(slug: 'b', versionNumber: '2.7.3');

    final out = await runUpgrade(['a']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, contains('version: 2.0.0'));
    expect(lock, isNot(contains('version: 2.7.3')));
  });

  test('caret constraint respected by default (does not cross major)', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '6.5.2')
      ..registerVersion(slug: 'a', versionNumber: '7.0.0');

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 6.5.2'));
    expect(lock, isNot(contains('version: 7.0.0')));
  });

  test('--major-versions crosses caret and rewrites mods.yaml', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '7.1.0');

    final out = await runUpgrade(['--major-versions', 'a']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 7.1.0'));
    expect(readManifest(), contains('a: ^7.1.0'));
  });

  test('--major-versions skips entries already allowed by constraint', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '6.0.10')
      ..registerVersion(slug: 'a', versionNumber: '6.5.2');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['--major-versions']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 6.5.2'));
    // resolved 6.5.2 still allowed by ^6.0.10 → no rewrite.
    expect(readManifest(), contains('a: ^6.0.10'));
  });

  test('--tighten rewrites caret base after in-major bump', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '6.5.2');

    final out = await runUpgrade(['--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), contains('version: 6.5.2'));
    expect(readManifest(), contains('a: ^6.5.2'));
  });

  test('--tighten is a no-op for entries that did not move', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '6.0.10');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
''');
    expect((await runGet()).exitCode, 0);

    final before = readManifest();
    final out = await runUpgrade(['--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readManifest(), before);
  });

  test('--tighten ignores non-caret constraints (channel-only)', () async {
    modrinth
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.0.0',
        versionType: 'release',
      )
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.5.0',
        versionType: 'release',
      );
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: release
''');
    expect((await runGet()).exitCode, 0);

    final before = readManifest();
    final out = await runUpgrade(['--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readManifest(), before);
    // Lock still picked the newest release.
    expect(readLock(), contains('version: 1.5.0'));
  });

  test('--major-versions --tighten: combined cross + in-major rewrites', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '6.0.10')
      ..registerVersion(slug: 'b', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^6.0.10
  b: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth
      ..registerVersion(slug: 'a', versionNumber: '7.1.0') // crosses caret
      ..registerVersion(slug: 'b', versionNumber: '1.4.0'); // in-major

    final out = await runUpgrade(['--major-versions', '--tighten']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final yaml = readManifest();
    expect(yaml, contains('a: ^7.1.0'));
    expect(yaml, contains('b: ^1.4.0'));
  });

  test('--dry-run returns exit 2 and writes nothing when changes occur',
      () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '1.5.0');
    final lockBefore = readLock();
    final yamlBefore = readManifest();

    final out = await runUpgrade(['--major-versions', '--tighten', '--dry-run']);
    expect(out.exitCode, 2, reason: '${out.stderr}\n${out.stdout}');
    expect(readLock(), lockBefore);
    expect(readManifest(), yamlBefore);
  });

  test('--dry-run returns exit 0 when no changes would occur', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['--dry-run']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
  });

  test('unknown slug → exit 64', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['does-not-exist']);
    expect(out.exitCode, 64, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stderr, contains('does-not-exist'));
  });

  test('url entries are skipped, not errored', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a: ^1.0.0
  custom:
    url: ${modrinth.downloadBaseUrl}/a/a-1.0.0.jar
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade(['custom']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
  });

  test('channel floor still respected during upgrade', () async {
    modrinth
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.0.0',
        versionType: 'release',
      )
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.5.0',
        versionType: 'release',
      )
      ..registerVersion(
        slug: 'a',
        versionNumber: '1.7.0-beta',
        versionType: 'beta',
      );
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a:
    version: ^1.0.0
    channel: release
''');
    expect((await runGet()).exitCode, 0);

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, isNot(contains('1.7.0-beta')));
  });

  test('per-side state preserved through upgrade', () async {
    modrinth.registerVersion(slug: 'a', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  a:
    version: ^1.0.0
    client: optional
    server: optional
''');
    expect((await runGet()).exitCode, 0);

    modrinth.registerVersion(slug: 'a', versionNumber: '1.5.0');

    final out = await runUpgrade([]);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    expect(lock, contains('version: 1.5.0'));
    expect(lock, contains('client: optional'));
    expect(lock, contains('server: optional'));
  });

  test(
    '`^1.21.1` (bare MMP) admits `1.21.1-<label>` releases and resolves '
    'to the newest by date_published',
    () async {
      // Direct repro of the user-reported regression: with constraint
      // `^1.21.1` the resolver was picking `1.21.3-june-2025` because
      // standard semver carets exclude pre-release-suffixed versions of
      // the same MMP, leaving only the higher-MMP june release inside
      // the range. The Modrinth-aware caret admits the labelled
      // releases, and the date_published sort then picks december over
      // both april and june.
      modrinth
        ..registerVersion(
          slug: 'faithful-32x',
          versionNumber: '1.21.1-april-2025',
          loader: 'minecraft',
          datePublished: '2025-04-15T00:00:00Z',
        )
        ..registerVersion(
          slug: 'faithful-32x',
          versionNumber: '1.21.3-june-2025',
          loader: 'minecraft',
          datePublished: '2025-06-15T00:00:00Z',
        )
        ..registerVersion(
          slug: 'faithful-32x',
          versionNumber: '1.21.1-december-2025',
          loader: 'minecraft',
          datePublished: '2025-12-15T00:00:00Z',
        );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
resource_packs:
  faithful-32x: ^1.21.1
''');
      final out = await runGet();
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final lock = readLock();
      expect(lock, contains('version: 1.21.1-december-2025'));
      expect(lock, isNot(contains('version: 1.21.3-june-2025')));
      expect(lock, isNot(contains('version: 1.21.1-april-2025')));
    },
  );

  test(
    'resource pack with date-encoded labels: upgrade picks newest by '
    'date_published, not highest MMP',
    () async {
      // Faithful 32x ships versions named `<max-mc>-<release-label>`
      // — the leading `1.21.x` is the highest-supported MC, not a
      // version of the pack. With pure semver-desc sort, `1.21.3-june-2025`
      // would beat `1.21.1-december-2025` even though june was published
      // six months *before* december. This test guards against that
      // regression end-to-end.
      modrinth
        ..registerVersion(
          slug: 'faithful-32x',
          versionNumber: '1.21.1-april-2025',
          loader: 'minecraft',
          datePublished: '2025-04-15T00:00:00Z',
        )
        ..registerVersion(
          slug: 'faithful-32x',
          versionNumber: '1.21.3-june-2025',
          loader: 'minecraft',
          datePublished: '2025-06-15T00:00:00Z',
        );
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
resource_packs:
  faithful-32x: ^1.21.1-april-2025
''');
      expect((await runGet()).exitCode, 0);

      // Newer release lands later, with a higher publish date and a
      // *lower* leading MMP than the june-2025 entry. Upgrade must pick it.
      modrinth.registerVersion(
        slug: 'faithful-32x',
        versionNumber: '1.21.1-december-2025',
        loader: 'minecraft',
        datePublished: '2025-12-15T00:00:00Z',
      );

      final out = await runUpgrade([]);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final lock = readLock();
      expect(lock, contains('version: 1.21.1-december-2025'));
      expect(lock, isNot(contains('version: 1.21.3-june-2025')));
    },
  );

  // The four cases below mirror dart-lang/pub's
  // test/upgrade/upgrade_transitive_test.dart, ported to gitrinth's
  // FakeModrinth-driven integration setup. `foo`/`bar`/`baz` follow
  // dart pub's naming so the parity is easy to verify.
  group('--unlock-transitive (mirrors dart pub)', () {
    test(
      'without --unlock-transitive, transitive dependencies stay locked',
      () async {
        modrinth
          ..registerVersion(
            slug: 'foo',
            versionNumber: '1.0.0',
            requiredDeps: const ['bar'],
          )
          ..registerVersion(slug: 'bar', versionNumber: '1.0.0');
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
''');
        expect((await runGet()).exitCode, 0);

        modrinth
          ..registerVersion(
            slug: 'foo',
            versionNumber: '1.5.0',
            requiredDeps: const ['bar'],
          )
          ..registerVersion(slug: 'bar', versionNumber: '1.5.0');

        final out = await runUpgrade(['foo']);
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final lock = readLock();
        expect(lock, contains('version: 1.5.0'));
        expect(lock, contains('version: 1.0.0'));
        expect(
          lock,
          isNot(contains('version: 1.5.0\n    project-id: bar_ID')),
          reason: 'bar must stay at 1.0.0',
        );
      },
    );

    test('--unlock-transitive dependencies get unlocked', () async {
      modrinth
        ..registerVersion(
          slug: 'foo',
          versionNumber: '1.0.0',
          requiredDeps: const ['bar'],
        )
        ..registerVersion(slug: 'bar', versionNumber: '1.0.0')
        ..registerVersion(slug: 'baz', versionNumber: '1.0.0');
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
  baz: ^1.0.0
''');
      expect((await runGet()).exitCode, 0);

      modrinth
        ..registerVersion(
          slug: 'foo',
          versionNumber: '1.5.0',
          requiredDeps: const ['bar'],
        )
        ..registerVersion(slug: 'bar', versionNumber: '1.5.0')
        ..registerVersion(slug: 'baz', versionNumber: '1.5.0');

      final out = await runUpgrade(['--unlock-transitive', 'foo']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final lock = readLock();
      // foo and bar both move; baz (root, unrelated) keeps its pin.
      expect(
        lock,
        contains(RegExp(r'foo:\s+source: modrinth\s+version: 1\.5\.0')),
      );
      expect(
        lock,
        contains(RegExp(r'bar:\s+source: modrinth\s+version: 1\.5\.0')),
      );
      expect(
        lock,
        contains(RegExp(r'baz:\s+source: modrinth\s+version: 1\.0\.0')),
      );
    });

    test(
      '--major-versions without --unlock-transitive does not bump transitives',
      () async {
        modrinth
          ..registerVersion(
            slug: 'foo',
            versionNumber: '1.0.0',
            requiredDeps: const ['bar'],
          )
          ..registerVersion(slug: 'bar', versionNumber: '1.0.0');
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
''');
        expect((await runGet()).exitCode, 0);

        modrinth
          ..registerVersion(
            slug: 'foo',
            versionNumber: '2.0.0',
            requiredDeps: const ['bar'],
          )
          ..registerVersion(slug: 'bar', versionNumber: '1.5.0');

        final out = await runUpgrade(['--major-versions', 'foo']);
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final lock = readLock();
        expect(
          lock,
          contains(RegExp(r'foo:\s+source: modrinth\s+version: 2\.0\.0')),
        );
        expect(
          lock,
          contains(RegExp(r'bar:\s+source: modrinth\s+version: 1\.0\.0')),
          reason: 'bar must stay locked at 1.0.0',
        );
        expect(readManifest(), contains('foo: ^2.0.0'));
      },
    );

    test(
      '--unlock-transitive --major-versions bumps transitives along with named',
      () async {
        modrinth
          ..registerVersion(
            slug: 'foo',
            versionNumber: '1.0.0',
            requiredDeps: const ['bar'],
          )
          ..registerVersion(slug: 'bar', versionNumber: '1.0.0')
          ..registerVersion(slug: 'baz', versionNumber: '1.0.0');
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
  baz: ^1.0.0
''');
        expect((await runGet()).exitCode, 0);

        modrinth
          ..registerVersion(
            slug: 'foo',
            versionNumber: '2.0.0',
            requiredDeps: const ['bar'],
          )
          ..registerVersion(slug: 'bar', versionNumber: '1.5.0')
          ..registerVersion(slug: 'baz', versionNumber: '1.5.0');

        final out = await runUpgrade([
          '--major-versions',
          '--unlock-transitive',
          'foo',
        ]);
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final lock = readLock();
        expect(
          lock,
          contains(RegExp(r'foo:\s+source: modrinth\s+version: 2\.0\.0')),
        );
        expect(
          lock,
          contains(RegExp(r'bar:\s+source: modrinth\s+version: 1\.5\.0')),
        );
        expect(
          lock,
          contains(RegExp(r'baz:\s+source: modrinth\s+version: 1\.0\.0')),
          reason: 'baz is not in foo\'s closure; must stay locked',
        );
      },
    );
  });

  // The legacy "no edges in lock → fall back" branch is gone. After
  // moving the dep graph from the lock to the cache, the cache-cold
  // case is the equivalent fall-through, covered separately by
  // `'--unlock-transitive falls back to seeds when cache is cold'`.

  // Ported from dart-lang/pub test/upgrade/upgrade_major_versions_test.dart
  // ("upgrades only the selected package") and
  // test/upgrade/upgrade_tighten_test.dart ("can tighten a specific package").
  // Confirms that named-slug `<slug>...` arguments scope rewrites to that
  // slug only — non-targeted entries' mods.yaml constraints are untouched.
  group('subset rewrites (mirrors dart pub)', () {
    test('--major-versions <slug> only bumps the named slug', () async {
      modrinth
        ..registerVersion(slug: 'foo', versionNumber: '1.0.0')
        ..registerVersion(slug: 'bar', versionNumber: '0.1.0');
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
  bar: ^0.1.0
''');
      expect((await runGet()).exitCode, 0);

      modrinth
        ..registerVersion(slug: 'foo', versionNumber: '2.0.0')
        ..registerVersion(slug: 'bar', versionNumber: '0.2.0');

      final out = await runUpgrade(['--major-versions', 'foo']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final yaml = readManifest();
      expect(yaml, contains('foo: ^2.0.0'));
      expect(yaml, contains('bar: ^0.1.0'));
      expect(yaml, isNot(contains('bar: ^0.2.0')));
    });

    test('--tighten <slug> only rewrites the named slug', () async {
      modrinth
        ..registerVersion(slug: 'foo', versionNumber: '1.0.0')
        ..registerVersion(slug: 'bar', versionNumber: '1.0.0');
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
  bar: ^1.0.0
''');
      expect((await runGet()).exitCode, 0);

      modrinth
        ..registerVersion(slug: 'foo', versionNumber: '1.5.0')
        ..registerVersion(slug: 'bar', versionNumber: '1.5.0');

      final out = await runUpgrade(['--tighten', 'foo']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final yaml = readManifest();
      expect(yaml, contains('foo: ^1.5.0'));
      expect(yaml, contains('bar: ^1.0.0'));
      expect(yaml, isNot(contains('bar: ^1.5.0')));
    });

    test(
      'subsequent --tighten <other-slug> --major-versions only touches that slug',
      () async {
        modrinth
          ..registerVersion(slug: 'foo', versionNumber: '1.0.0')
          ..registerVersion(slug: 'bar', versionNumber: '1.0.0');
        await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
  bar: ^1.0.0
''');
        expect((await runGet()).exitCode, 0);

        modrinth
          ..registerVersion(slug: 'foo', versionNumber: '1.5.0')
          ..registerVersion(slug: 'bar', versionNumber: '1.5.0');
        expect(
          (await runUpgrade(['--tighten', 'foo'])).exitCode,
          0,
        );
        expect(readManifest(), contains('foo: ^1.5.0'));
        expect(readManifest(), contains('bar: ^1.0.0'));

        modrinth
          ..registerVersion(slug: 'foo', versionNumber: '2.0.0')
          ..registerVersion(slug: 'bar', versionNumber: '2.0.0');

        final out = await runUpgrade([
          '--tighten',
          'bar',
          '--major-versions',
        ]);
        expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
        final yaml = readManifest();
        expect(yaml, contains('foo: ^1.5.0'));
        expect(yaml, contains('bar: ^2.0.0'));
      },
    );
  });

  test('--unlock-transitive terminates on cycles in the cache', () async {
    modrinth
      ..registerVersion(slug: 'foo', versionNumber: '1.0.0')
      ..registerVersion(slug: 'bar', versionNumber: '1.0.0');
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
  bar: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    // Overwrite the cached version.json files to inject a foo<->bar
    // cycle. The resolver would not normally produce one (Modrinth
    // deps are acyclic in practice), but a corrupt cache or a
    // hand-edited file can — the closure walker must terminate.
    void writeCachedDeps(String slug, String depProjectId) {
      final pid = '${slug}_ID';
      final vid = '${slug}_1_0_0';
      final dir = Directory(
        p.join(cacheDir.path, 'modrinth', pid, vid),
      )..createSync(recursive: true);
      File(p.join(dir.path, 'version.json')).writeAsStringSync(
        '{"dependencies":[{"project_id":"$depProjectId",'
        '"dependency_type":"required"}]}',
      );
    }

    writeCachedDeps('foo', 'bar_ID');
    writeCachedDeps('bar', 'foo_ID');

    modrinth
      ..registerVersion(slug: 'foo', versionNumber: '1.5.0')
      ..registerVersion(slug: 'bar', versionNumber: '1.5.0');

    final out = await runUpgrade(['--unlock-transitive', 'foo']);
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final lock = readLock();
    // The closure of {foo} over the cyclic edges is {foo, bar}; both
    // get unlocked and bumped.
    expect(lock, contains('version: 1.5.0'));
    expect(lock, isNot(contains('version: 1.0.0')));
  });

  test(
    '--unlock-transitive falls back to seeds when cache is cold',
    () async {
      // No cached version.json for foo means no edges visible — only
      // foo (the named seed) gets unlocked. bar (a transitive dep)
      // stays at its locked version because the closure walker can't
      // discover the edge.
      modrinth
        ..registerVersion(slug: 'foo', versionNumber: '1.0.0')
        ..registerVersion(slug: 'bar', versionNumber: '1.0.0');
      await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods:
  foo: ^1.0.0
  bar: ^1.0.0
''');
      expect((await runGet()).exitCode, 0);

      // Wipe the cache so version.json is missing for both entries.
      Directory(p.join(cacheDir.path, 'modrinth')).deleteSync(recursive: true);

      modrinth
        ..registerVersion(slug: 'foo', versionNumber: '1.5.0')
        ..registerVersion(slug: 'bar', versionNumber: '1.5.0');

      final out = await runUpgrade(['--unlock-transitive', 'foo']);
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      // foo bumps because it's a named seed. bar stays put because
      // we never walked into it (cold cache, no edges).
      final lock = readLock();
      // foo: ^1.0.0 satisfies 1.5.0 → bar stays since it's not in seed
      // and no edges were discovered.
      expect(lock, contains('version: 1.5.0')); // foo
      expect(lock, contains('version: 1.0.0')); // bar pinned
    },
  );
}
