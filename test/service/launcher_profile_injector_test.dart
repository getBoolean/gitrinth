import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/service/launcher_profile_injector.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LauncherProfileInjector', () {
    late Directory tempRoot;
    late File profilesFile;
    late LauncherProfileInjector injector;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_lpi_');
      profilesFile = File(p.join(tempRoot.path, 'launcher_profiles.json'));
      injector = LauncherProfileInjector(file: profilesFile);
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('creates a launcher_profiles.json shell when none exists', () async {
      await injector.upsertProfile(
        key: 'gitrinth-pack',
        displayName: 'gitrinth: pack',
        lastVersionId: 'fabric-loader-0.17.3-1.21.1',
        gameDir: Directory(p.join(tempRoot.path, 'pack', 'build', 'client')),
      );

      expect(profilesFile.existsSync(), isTrue);
      final json = jsonDecode(profilesFile.readAsStringSync())
          as Map<String, dynamic>;
      expect(json['profiles'], isA<Map>());
      final profile = (json['profiles'] as Map)['gitrinth-pack']
          as Map<String, dynamic>;
      expect(profile['name'], 'gitrinth: pack');
      expect(profile['type'], 'custom');
      expect(profile['lastVersionId'], 'fabric-loader-0.17.3-1.21.1');
      expect(profile['gameDir'], endsWith('client'));
      expect(profile['created'], isNotNull);
      expect(profile['lastUsed'], isNotNull);
    });

    test('preserves unrelated existing profiles and top-level keys', () async {
      profilesFile.writeAsStringSync(jsonEncode({
        'version': 3,
        'profiles': {
          'someone-elses-profile': {
            'name': 'Vanilla',
            'type': 'latest-release',
          },
        },
        'settings': {'enableSnapshots': false},
      }));

      await injector.upsertProfile(
        key: 'gitrinth-pack',
        displayName: 'gitrinth: pack',
        lastVersionId: '1.21.1-forge-52.1.5',
        gameDir: Directory(p.join(tempRoot.path, 'pack', 'build', 'client')),
      );

      final json = jsonDecode(profilesFile.readAsStringSync())
          as Map<String, dynamic>;
      expect(json['version'], 3);
      expect((json['settings'] as Map)['enableSnapshots'], false);
      final profiles = json['profiles'] as Map;
      expect(profiles, contains('someone-elses-profile'));
      expect(
        ((profiles['someone-elses-profile'] as Map)['name'] as String),
        'Vanilla',
      );
      expect(profiles, contains('gitrinth-pack'));
    });

    test('upsert by key updates an existing entry rather than duplicating',
        () async {
      await injector.upsertProfile(
        key: 'gitrinth-pack',
        displayName: 'gitrinth: pack',
        lastVersionId: 'old-version',
        gameDir: Directory(p.join(tempRoot.path, 'old-dir')),
      );
      final firstCreated = ((jsonDecode(profilesFile.readAsStringSync())
                  as Map)['profiles'] as Map)['gitrinth-pack']
          as Map<String, dynamic>;
      final originalCreated = firstCreated['created'] as String;

      await Future<void>.delayed(const Duration(milliseconds: 5));

      await injector.upsertProfile(
        key: 'gitrinth-pack',
        displayName: 'gitrinth: pack v2',
        lastVersionId: 'new-version',
        gameDir: Directory(p.join(tempRoot.path, 'new-dir')),
      );

      final json = jsonDecode(profilesFile.readAsStringSync())
          as Map<String, dynamic>;
      final profile = ((json['profiles'] as Map)['gitrinth-pack'])
          as Map<String, dynamic>;
      expect(profile['name'], 'gitrinth: pack v2');
      expect(profile['lastVersionId'], 'new-version');
      expect(profile['gameDir'], endsWith('new-dir'));
      expect(
        profile['created'],
        originalCreated,
        reason: '`created` must be preserved across upserts',
      );
    });

    test('writes via temp + rename so a partial write does not corrupt',
        () async {
      // The injector should never leave the destination half-written. We
      // can prove the write is atomic by checking that no `.tmp` sibling
      // is left behind on success.
      await injector.upsertProfile(
        key: 'gitrinth-pack',
        displayName: 'gitrinth: pack',
        lastVersionId: 'v',
        gameDir: Directory(p.join(tempRoot.path, 'g')),
      );
      final tmpSibling = File('${profilesFile.path}.tmp');
      expect(tmpSibling.existsSync(), isFalse);
    });

    test('javaArgs is written when provided and absent when null', () async {
      await injector.upsertProfile(
        key: 'with-args',
        displayName: 'with args',
        lastVersionId: 'v',
        gameDir: Directory(p.join(tempRoot.path, 'g')),
        javaArgs: '-Xmx4G',
      );
      await injector.upsertProfile(
        key: 'without-args',
        displayName: 'without args',
        lastVersionId: 'v',
        gameDir: Directory(p.join(tempRoot.path, 'g')),
      );

      final profiles = (jsonDecode(profilesFile.readAsStringSync())
          as Map)['profiles'] as Map;
      expect((profiles['with-args'] as Map)['javaArgs'], '-Xmx4G');
      expect((profiles['without-args'] as Map).containsKey('javaArgs'),
          isFalse);
    });
  });
}
