import 'dart:io';

import 'package:gitrinth/src/cli/exit_codes.dart';
import 'package:gitrinth/src/service/user_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/capture.dart';
import '../helpers/fake_modrinth.dart';

void main() {
  late Directory tempHome;
  late String configPath;
  late FakeModrinth fake;
  late Map<String, String> env;

  setUp(() async {
    tempHome = Directory.systemTemp.createTempSync('gitrinth_token_');
    configPath = p.join(tempHome.path, 'config.yaml');
    fake = FakeModrinth();
    await fake.start();
    env = {
      'GITRINTH_CONFIG': configPath,
      'GITRINTH_MODRINTH_URL': fake.baseUrl,
    };
  });

  tearDown(() async {
    await fake.stop();
    if (tempHome.existsSync()) tempHome.deleteSync(recursive: true);
  });

  group('gitrinth modrinth token add', () {
    test(
      'stores a token via --token after /user validation succeeds',
      () async {
        fake.registerToken('mrp_other', username: 'bob');

        final result = await runCli([
          'modrinth',
          'token',
          'add',
          fake.baseUrl,
          '--token',
          'mrp_other',
        ], environment: env);

        expect(result.exitCode, equals(exitOk));
        expect(result.stdout, contains('Stored token'));
        expect(result.stdout, contains('bob'));

        final cfg = UserConfigStore(configPath).read();
        expect(cfg.tokenFor(fake.baseUrl), equals('mrp_other'));
      },
    );

    test('rejects invalid token with auth-failure exit code', () async {
      final result = await runCli([
        'modrinth',
        'token',
        'add',
        fake.baseUrl,
        '--token',
        'mrp_bad',
      ], environment: env);
      expect(result.exitCode, equals(exitAuthenticationFailure));
      expect(File(configPath).existsSync(), isFalse);
    });

    test('errors when <server-url> is missing', () async {
      final result = await runCli([
        'modrinth',
        'token',
        'add',
      ], environment: env);
      expect(result.exitCode, equals(exitUsageError));
    });
  });

  group('gitrinth modrinth token list', () {
    test('masks every stored token', () async {
      UserConfigStore(configPath).write(
        const UserConfig().withToken(fake.baseUrl, 'mrp_abcdefghijklmnop'),
      );

      final result = await runCli([
        'modrinth',
        'token',
        'list',
      ], environment: env);

      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('mrp_'));
      expect(result.stdout, contains('mnop'));
      expect(result.stdout, isNot(contains('mrp_abcdefghijklmnop')));
    });

    test('flags GITRINTH_TOKEN override when set', () async {
      UserConfigStore(
        configPath,
      ).write(const UserConfig().withToken(fake.baseUrl, 'mrp_storedabcdef'));

      final result = await runCli(
        ['modrinth', 'token', 'list'],
        environment: {...env, 'GITRINTH_TOKEN': 'mrp_envoverride'},
      );

      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('GITRINTH_TOKEN override'));
    });

    test('reports gracefully on an empty config', () async {
      final result = await runCli([
        'modrinth',
        'token',
        'list',
      ], environment: env);
      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('no stored tokens'));
    });
  });

  group('gitrinth modrinth token remove', () {
    test('removes a stored token', () async {
      UserConfigStore(
        configPath,
      ).write(const UserConfig().withToken(fake.baseUrl, 'mrp_other'));

      final result = await runCli([
        'modrinth',
        'token',
        'remove',
        fake.baseUrl,
      ], environment: env);

      expect(result.exitCode, equals(exitOk));
      expect(UserConfigStore(configPath).read().tokens, isEmpty);
    });

    test('errors when no entry exists', () async {
      final result = await runCli([
        'modrinth',
        'token',
        'remove',
        fake.baseUrl,
      ], environment: env);
      expect(result.exitCode, equals(exitUserError));
      expect(result.stderr, contains('No stored token'));
    });
  });
}
