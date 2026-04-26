import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/resolver/constraint.dart';
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
    tempRoot = Directory.systemTemp.createTempSync('gitrinth_migrate_');
    packDir = Directory(p.join(tempRoot.path, 'pack'))..createSync();
    cacheDir = Directory(p.join(tempRoot.path, 'cache'))..createSync();
    modrinth = FakeModrinth();
    // Pad gameVersions with 1.21.4 so mc-version validation passes.
    modrinth.gameVersions = [
      ...modrinth.gameVersions,
      {
        'version': '1.21.4',
        'version_type': 'release',
        'date': '2024-12-03T00:00:00Z',
        'major': false,
      },
    ];
    await modrinth.start();
    env = {
      'GITRINTH_MODRINTH_URL': modrinth.baseUrl,
      'GITRINTH_CACHE': cacheDir.path,
      'GITRINTH_FABRIC_META_URL': modrinth.fabricMetaUrl,
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

  Future<CapturedOutput> runGet([List<String> extra = const []]) =>
      runCli(['-C', packDir.path, 'get', ...extra], environment: env);

  Future<CapturedOutput> runMigrateMc(
    String version, [
    List<String> extra = const [],
  ]) => runCli(
    ['-C', packDir.path, 'migrate', 'mc', version, ...extra],
    environment: env,
  );

  test('migrate mc: bumps manifest mc-version, rewrites carets, '
      're-resolves lock', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'a', versionNumber: '2.0.0', gameVersion: '1.21.4');
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

    final out = await runMigrateMc('1.21.4');
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final manifest = readManifest();
    expect(manifest, contains('mc-version: 1.21.4'));
    expect(manifest, contains('a: ^2.0.0'));
    final lock = readLock();
    expect(lock, contains('mc-version: 1.21.4'));
    expect(lock, contains('version: 2.0.0'));
  });

  test('migrate mc --dry-run: writes nothing', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'a', versionNumber: '2.0.0', gameVersion: '1.21.4');
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

    final manifestBefore = readManifest();
    final lockBefore = readLock();

    final out = await runMigrateMc('1.21.4', ['--dry-run']);
    // Mirrors `upgrade --dry-run`: exit 2 when changes would be applied.
    expect(out.exitCode, 2, reason: '${out.stderr}\n${out.stdout}');
    expect(readManifest(), equals(manifestBefore));
    expect(readLock(), equals(lockBefore));
  });

  test('migrate mc: marks long-form entry not-found, preserves '
      'client/server', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      // `b` was published on 1.21.1 but never on 1.21.4.
      ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'a', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b:
    version: ^1.0.0
    client: optional
    server: required
''');
    expect((await runGet()).exitCode, 0);

    final out = await runMigrateMc('1.21.4');
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final manifest = readManifest();
    // `a` migrated normally.
    expect(manifest, contains('a: ^2.0.0'));
    // `b` got the marker; client/server preserved.
    expect(manifest, contains('version: $notFoundMarker'));
    expect(manifest, contains('client: optional'));
    expect(manifest, contains('server: required'));
    // Lock omits the marker entry but keeps the migrated one.
    final lock = readLock();
    expect(lock, contains('a:'));
    expect(lock, isNot(contains('b:')));
  });

  test('migrate mc: marks short-form entry not-found by rewriting the '
      'scalar', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'a', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    final out = await runMigrateMc('1.21.4');
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final manifest = readManifest();
    expect(manifest, contains('a: ^2.0.0'));
    expect(manifest, contains('b: $notFoundMarker'));
    // Lock omits b.
    expect(readLock(), isNot(contains('b:')));
  });

  test('re-migrate recovers a previously-marked entry to a fresh caret',
      () async {
    // First state: b is published only on 1.21.1.
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'a', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);
    expect((await runMigrateMc('1.21.4')).exitCode, 0);
    expect(readManifest(), contains('b: $notFoundMarker'));

    // Now upstream publishes b@2.0.0 for 1.21.4.
    modrinth.registerVersion(
      slug: 'b',
      versionNumber: '2.0.0',
      gameVersion: '1.21.4',
    );
    final out = await runMigrateMc('1.21.4');
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final manifest = readManifest();
    expect(manifest, isNot(contains(notFoundMarker)));
    expect(manifest, contains('b: ^2.0.0'));
    expect(readLock(), contains('version: 2.0.0'));
  });

  test('re-migrate leaves a still-unavailable marker entry alone', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'a', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);
    expect((await runMigrateMc('1.21.4')).exitCode, 0);
    final markedManifest = readManifest();
    expect(markedManifest, contains('b: $notFoundMarker'));

    // No new b version published. Re-migrate to the same target.
    final out = await runMigrateMc('1.21.4');
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(readManifest(), equals(markedManifest));
  });

  test('upgrade --major-versions recovers a marker entry when it becomes '
      'available on the current target', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.20.1');
    // Pack is on 1.21.1; b is only published for 1.20.1 → marker.
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
  b:
    version: $notFoundMarker
    client: required
    server: required
''');
    expect((await runGet()).exitCode, 0);
    expect(readLock(), isNot(contains('b:')));

    // Upstream publishes b on 1.21.1.
    modrinth.registerVersion(
      slug: 'b',
      versionNumber: '1.0.0',
      gameVersion: '1.21.1',
    );

    // Plain `upgrade` leaves the marker alone (recovery rewrites a
    // constraint, which only --major-versions is allowed to do).
    final plain = await runCli(
      ['-C', packDir.path, 'upgrade'],
      environment: env,
    );
    expect(plain.exitCode, 0, reason: '${plain.stderr}\n${plain.stdout}');
    expect(readManifest(), contains('version: $notFoundMarker'));

    final out = await runCli(
      ['-C', packDir.path, 'upgrade', '--major-versions'],
      environment: env,
    );
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    final manifest = readManifest();
    expect(manifest, isNot(contains(notFoundMarker)));
    expect(manifest, contains('version: ^1.0.0'));
    expect(readLock(), contains('b:'));
  });

  test('get tolerates marker entries: skips them, surfaces nag, '
      'enforce-lockfile passes', () async {
    modrinth
      ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
      ..registerVersion(slug: 'a', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);
    expect((await runMigrateMc('1.21.4')).exitCode, 0);

    // Run get on the post-migrate manifest: must not error on the marker
    // entry, and must surface the nag line.
    final out = await runGet();
    expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
    expect(out.stdout, contains('marked $notFoundMarker'));

    final enforce = await runGet(['--enforce-lockfile']);
    expect(
      enforce.exitCode,
      0,
      reason:
          '--enforce-lockfile must ignore marker entries.\n${enforce.stderr}',
    );
  });

  test('migrate mc: rejects an unknown Minecraft version', () async {
    modrinth.registerVersion(
      slug: 'a',
      versionNumber: '1.0.0',
      gameVersion: '1.21.1',
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
  a: ^1.0.0
''');
    expect((await runGet()).exitCode, 0);

    final out = await runMigrateMc('9.9.9');
    expect(out.exitCode, isNot(0));
  });

  test('migrate: missing positional → usage error', () async {
    await writeManifest('''
slug: pack
name: Pack
version: 0.1.0
description: x
loader:
  mods: "neoforge:21.1.50"
mc-version: 1.21.1
mods: {}
''');
    final out = await runCli(
      ['-C', packDir.path, 'migrate', 'mc'],
      environment: env,
    );
    expect(out.exitCode, isNot(0));
  });

  test(
    'migrate disables both endpoints of a mutual-incompatibility conflict, '
    'writes a lock for the shrunk pack, exits 0 with a warning',
    () async {
      // a v2 on 1.21.4 declares b incompatible → both disabled; c clean.
      modrinth
        ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(slug: 'c', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(
          slug: 'a',
          versionNumber: '2.0.0',
          gameVersion: '1.21.4',
          incompatibleDeps: const ['b'],
        )
        ..registerVersion(slug: 'b', versionNumber: '2.0.0', gameVersion: '1.21.4')
        ..registerVersion(slug: 'c', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
  c: ^1.0.0
''');
      expect((await runGet()).exitCode, 0);

      final out = await runMigrateMc('1.21.4');
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final manifest = readManifest();
      expect(manifest, contains('a: $disabledByConflictMarker'));
      expect(manifest, contains('b: $disabledByConflictMarker'));
      // c is unrelated — migrates normally to ^2.0.0.
      expect(manifest, contains('c: ^2.0.0'));
      // Warning names both disabled mods.
      expect(out.stdout, contains('disabled'));
      expect(out.stdout, contains('a'));
      expect(out.stdout, contains('b'));
      // Lock contains c but not a or b.
      final lock = readLock();
      expect(lock, contains('c:'));
      expect(lock, isNot(contains('a:')));
      expect(lock, isNot(contains('b:')));
    },
  );

  test(
    're-running migrate with a still-conflicting graph keeps the '
    'disabled-by-conflict markers in place',
    () async {
      modrinth
        ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(
          slug: 'a',
          versionNumber: '2.0.0',
          gameVersion: '1.21.4',
          incompatibleDeps: const ['b'],
        )
        ..registerVersion(slug: 'b', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
''');
      expect((await runGet()).exitCode, 0);
      expect((await runMigrateMc('1.21.4')).exitCode, 0);
      final markedManifest = readManifest();
      expect(markedManifest, contains('a: $disabledByConflictMarker'));
      expect(markedManifest, contains('b: $disabledByConflictMarker'));

      // No upstream change. Re-run: relaxSet pulls both markers in for a
      // recovery attempt; the same conflict surfaces; the auto-disable
      // re-applies the same markers. Manifest must be byte-identical.
      final out = await runMigrateMc('1.21.4');
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      expect(readManifest(), equals(markedManifest));
    },
  );

  test(
    're-running migrate recovers a disabled-by-conflict entry once the '
    'conflict is gone',
    () async {
      modrinth
        ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(
          slug: 'a',
          versionNumber: '2.0.0',
          gameVersion: '1.21.4',
          incompatibleDeps: const ['b'],
        )
        ..registerVersion(slug: 'b', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
''');
      expect((await runGet()).exitCode, 0);
      expect((await runMigrateMc('1.21.4')).exitCode, 0);
      expect(readManifest(), contains('a: $disabledByConflictMarker'));
      expect(readManifest(), contains('b: $disabledByConflictMarker'));

      // Upstream publishes a newer `a` v2.5.0 that drops the
      // incompatibility declaration → conflict gone → both recover to
      // fresh carets.
      modrinth.registerVersion(
        slug: 'a',
        versionNumber: '2.5.0',
        gameVersion: '1.21.4',
      );
      final out = await runMigrateMc('1.21.4');
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      final manifest = readManifest();
      expect(manifest, isNot(contains(disabledByConflictMarker)));
      expect(manifest, contains('a: ^2.5.0'));
      expect(manifest, contains('b: ^2.0.0'));
      expect(readLock(), contains('a:'));
      expect(readLock(), contains('b:'));
    },
  );

  test(
    'migrate --dry-run reports the would-be disable set but writes nothing',
    () async {
      modrinth
        ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(
          slug: 'a',
          versionNumber: '2.0.0',
          gameVersion: '1.21.4',
          incompatibleDeps: const ['b'],
        )
        ..registerVersion(slug: 'b', versionNumber: '2.0.0', gameVersion: '1.21.4');
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
  b: ^1.0.0
''');
      expect((await runGet()).exitCode, 0);
      final manifestBefore = readManifest();
      final lockBefore = readLock();

      final out = await runMigrateMc('1.21.4', ['--dry-run']);
      // Dry-run convention: exit 2 when changes would be applied.
      expect(out.exitCode, 2, reason: '${out.stderr}\n${out.stdout}');
      // Output names what would be disabled.
      expect(out.stdout, contains('disabled'));
      expect(out.stdout, contains('a'));
      expect(out.stdout, contains('b'));
      // No writes.
      expect(readManifest(), equals(manifestBefore));
      expect(readLock(), equals(lockBefore));
    },
  );

  test(
    'get tolerates disabled-by-conflict marker entries: skips them, '
    'surfaces nag, enforce-lockfile passes',
    () async {
      modrinth
        ..registerVersion(slug: 'a', versionNumber: '1.0.0', gameVersion: '1.21.1')
        ..registerVersion(slug: 'b', versionNumber: '1.0.0', gameVersion: '1.21.1');
      // Hand-author the post-conflict state — `b` was disabled by a
      // prior migrate's conflict catch. Until the catch is implemented we
      // can still cover the resolver-skip/exempt/nag plumbing by writing
      // the marker directly. (Auto-disable end-to-end is a later test.)
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
  b: $disabledByConflictMarker
''');

      final out = await runGet();
      expect(out.exitCode, 0, reason: '${out.stderr}\n${out.stdout}');
      // Resolver-skip: lock has a but not b.
      final lock = readLock();
      expect(lock, contains('a:'));
      expect(lock, isNot(contains('b:')));
      // Nag: stdout names the marker count and points at the retry commands.
      expect(out.stdout, contains('marked $disabledByConflictMarker'));
      expect(out.stdout, contains('migrate'));
      expect(out.stdout, contains('--major-versions'));

      // Enforce-lockfile: marker entries are exempt from the
      // "must be in mods.lock" check.
      final enforce = await runGet(['--enforce-lockfile']);
      expect(
        enforce.exitCode,
        0,
        reason:
            '--enforce-lockfile must ignore disabled-by-conflict entries.\n'
            '${enforce.stderr}',
      );
    },
  );

  group('parseConstraint with not-found marker', () {
    test('throws ValidationError naming `gitrinth migrate` as the fix', () {
      expect(
        () => parseConstraint(notFoundMarker),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('gitrinth migrate'),
          ),
        ),
      );
    });

    test('isNotFoundMarker is whitespace-tolerant', () {
      expect(isNotFoundMarker(notFoundMarker), isTrue);
      expect(isNotFoundMarker('  $notFoundMarker  '), isTrue);
      expect(isNotFoundMarker('^1.2.3'), isFalse);
      expect(isNotFoundMarker(null), isFalse);
      expect(isNotFoundMarker(''), isFalse);
    });
  });
}
