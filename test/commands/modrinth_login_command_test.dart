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
    tempHome = Directory.systemTemp.createTempSync('gitrinth_login_');
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

  group('gitrinth modrinth login', () {
    test('stores token via --token after /user validation succeeds',
        () async {
      fake.registerToken('mrp_good', username: 'alice');

      final result = await runCli(
        ['modrinth', 'login', '--token', 'mrp_good'],
        environment: env,
      );

      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('Logged in to ${fake.baseUrl} as alice.'));
      expect(result.stdout, contains('VERSION_CREATE'));

      final cfg = UserConfigStore(configPath).read();
      expect(cfg.tokenFor(fake.baseUrl), equals('mrp_good'));
    });

    test('stores token via piped stdin when --token is omitted', () async {
      fake.registerToken('mrp_good', username: 'alice');

      final result = await runCli(
        ['modrinth', 'login'],
        environment: env,
        stdinInput: 'mrp_good\n',
      );

      expect(result.exitCode, equals(exitOk));
      final cfg = UserConfigStore(configPath).read();
      expect(cfg.tokenFor(fake.baseUrl), equals('mrp_good'));
    });

    test('rejects an invalid token with exit code 4', () async {
      final result = await runCli(
        ['modrinth', 'login', '--token', 'mrp_bad'],
        environment: env,
      );

      expect(result.exitCode, equals(exitAuthenticationFailure));
      expect(result.stderr, contains('rejected'));
      expect(File(configPath).existsSync(), isFalse,
          reason: 'failed login must not persist a token');
    });

    test('warns when GITRINTH_TOKEN is set', () async {
      fake.registerToken('mrp_good', username: 'alice');

      final result = await runCli(
        ['modrinth', 'login', '--token', 'mrp_good'],
        environment: {...env, 'GITRINTH_TOKEN': 'mrp_env'},
      );

      expect(result.exitCode, equals(exitOk));
      expect(result.stderr, contains('GITRINTH_TOKEN'));
    });

    test('rejects empty stdin input', () async {
      final result = await runCli(
        ['modrinth', 'login'],
        environment: env,
        stdinInput: '\n',
      );
      expect(result.exitCode, equals(exitUserError));
      expect(result.stderr, contains('No token provided'));
    });
  });

  group('gitrinth modrinth logout', () {
    test('removes a stored token', () async {
      UserConfigStore(configPath).write(
        const UserConfig().withToken(fake.baseUrl, 'mrp_good'),
      );

      final result = await runCli(['modrinth', 'logout'], environment: env);

      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('Logged out of ${fake.baseUrl}.'));
      expect(UserConfigStore(configPath).read().tokens, isEmpty);
    });

    test('reports gracefully when nothing is stored', () async {
      final result = await runCli(['modrinth', 'logout'], environment: env);
      expect(result.exitCode, equals(exitOk));
      expect(result.stdout, contains('Not logged in'));
    });
  });
}
