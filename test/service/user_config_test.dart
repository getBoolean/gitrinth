import 'dart:io';

import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/user_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolveUserConfigPath', () {
    test('--config wins over GITRINTH_CONFIG and HOME', () {
      final path = resolveUserConfigPath(const {
        'GITRINTH_CONFIG': '/from/env.yaml',
        'HOME': '/h',
      }, override: '/from/flag.yaml');
      expect(path, equals(p.normalize(p.absolute('/from/flag.yaml'))));
    });

    test('GITRINTH_CONFIG wins over HOME default', () {
      final path = resolveUserConfigPath(const {
        'GITRINTH_CONFIG': '/from/env.yaml',
        'HOME': '/h',
      });
      expect(path, equals(p.normalize(p.absolute('/from/env.yaml'))));
    });

    test('falls back to <home>/.gitrinth/config.yaml', () {
      final env = Platform.isWindows
          ? const {'USERPROFILE': r'C:\Users\me'}
          : const {'HOME': '/home/me'};
      final path = resolveUserConfigPath(env);
      final expected = Platform.isWindows
          ? p.normalize(p.join(r'C:\Users\me', '.gitrinth', 'config.yaml'))
          : p.normalize(p.join('/home/me', '.gitrinth', 'config.yaml'));
      expect(path, equals(expected));
    });

    test('throws UserError when no override, env, or HOME', () {
      expect(() => resolveUserConfigPath(const {}), throwsA(isA<UserError>()));
    });

    test('empty override and empty env fall through', () {
      final env = Platform.isWindows
          ? const {'USERPROFILE': r'C:\Users\me'}
          : const {'HOME': '/home/me'};
      final path = resolveUserConfigPath({
        ...env,
        'GITRINTH_CONFIG': '',
      }, override: '');
      final expected = Platform.isWindows
          ? p.normalize(p.join(r'C:\Users\me', '.gitrinth', 'config.yaml'))
          : p.normalize(p.join('/home/me', '.gitrinth', 'config.yaml'));
      expect(path, equals(expected));
    });
  });

  group('UserConfigStore', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('gitrinth_cfg'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('reads empty config when file does not exist', () {
      final store = UserConfigStore(p.join(tempDir.path, 'missing.yaml'));
      final cfg = store.read();
      expect(cfg.tokens, isEmpty);
    });

    test('round-trips an empty config through write/read', () {
      final path = p.join(tempDir.path, 'config.yaml');
      final store = UserConfigStore(path);
      store.write(const UserConfig());
      expect(File(path).existsSync(), isTrue);
      final cfg = store.read();
      expect(cfg.tokens, isEmpty);
    });

    test('round-trips a populated tokens map', () {
      final path = p.join(tempDir.path, 'config.yaml');
      final store = UserConfigStore(path);
      store.write(
        const UserConfig(tokens: {'https://api.modrinth.com': 'mrt_xxx'}),
      );
      final cfg = store.read();
      expect(cfg.tokens, equals({'https://api.modrinth.com': 'mrt_xxx'}));
    });

    test('write creates parent directory lazily', () {
      final path = p.join(tempDir.path, 'nested', 'deeper', 'config.yaml');
      final store = UserConfigStore(path);
      store.write(const UserConfig());
      expect(File(path).existsSync(), isTrue);
    });
  });

  group('UserConfig.withToken / withoutToken', () {
    test('withToken normalizes the server URL into the map key', () {
      final next = const UserConfig().withToken(
        'HTTPS://API.Modrinth.COM/v2/',
        'mrp_token',
      );
      expect(next.tokens, equals({'https://api.modrinth.com/v2': 'mrp_token'}));
    });

    test('withToken overwrites an existing entry under the same key', () {
      final next = const UserConfig(
        tokens: {'https://api.modrinth.com/v2': 'old'},
      ).withToken('https://api.modrinth.com/v2/', 'new');
      expect(next.tokens['https://api.modrinth.com/v2'], equals('new'));
    });

    test('withoutToken removes the entry by normalized key', () {
      final next = const UserConfig(
        tokens: {'https://api.modrinth.com/v2': 'mrp'},
      ).withoutToken('HTTPS://api.modrinth.com/v2/');
      expect(next.tokens, isEmpty);
    });

    test('withoutToken is a no-op when no entry exists', () {
      const cfg = UserConfig(tokens: {'https://my.host/api': 'mrp'});
      final next = cfg.withoutToken('https://other.host');
      expect(next.tokens, equals(cfg.tokens));
    });

    test('tokenFor reads via the normalized key', () {
      const cfg = UserConfig(
        tokens: {'https://api.modrinth.com/v2': 'mrp_token'},
      );
      expect(cfg.tokenFor('HTTPS://api.modrinth.com/v2/'), equals('mrp_token'));
    });
  });
}
