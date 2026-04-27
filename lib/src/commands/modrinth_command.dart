import 'package:dio/dio.dart';

import '../app/env.dart';
import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../service/modrinth_url.dart';
import '../service/secret_input.dart';
import '../service/user_config.dart';
import 'modrinth_publish_command.dart';

class ModrinthCommand extends GitrinthCommand {
  @override
  String get name => 'modrinth';

  @override
  String get description =>
      'Authenticate against and publish to Modrinth servers.';

  @override
  String get invocation => 'gitrinth modrinth <subcommand>';

  ModrinthCommand() {
    addSubcommand(ModrinthLoginCommand());
    addSubcommand(ModrinthLogoutCommand());
    addSubcommand(ModrinthTokenCommand());
    addSubcommand(ModrinthPublishCommand());
  }

  @override
  Future<int> run() async {
    printUsage();
    return exitOk;
  }
}

class ModrinthLoginCommand extends GitrinthCommand {
  @override
  String get name => 'login';

  @override
  String get description =>
      'Store a Modrinth personal access token for the default server.';

  @override
  String get invocation => 'gitrinth modrinth login [--token <pat>]';

  ModrinthLoginCommand() {
    argParser.addOption(
      'token',
      valueHelp: 'pat',
      help:
          'Pass the personal access token directly (headless / CI). '
          'Falls back to a hidden stdin prompt when omitted.',
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
    final env = read(environmentProvider);
    final baseUrl = resolveModrinthBaseUrl(env);

    if ((env['GITRINTH_TOKEN'] ?? '').isNotEmpty) {
      console.warn(
        'GITRINTH_TOKEN is set; it will mask the stored token until unset.',
      );
    }

    final token = _resolveToken(baseUrl);

    final username = await _validateTokenAgainstUserEndpoint(
      read(dioProvider),
      baseUrl,
      token,
    );

    final store = read(userConfigStoreProvider);
    store.write(store.read().withToken(baseUrl, token));

    console.message('Logged in to $baseUrl as $username.');
    console.message(
      'For `gitrinth modrinth publish`, the PAT must include these scopes: '
      'USER_READ, PROJECT_READ, VERSION_CREATE.',
    );
    return exitOk;
  }

  String _resolveToken(String baseUrl) {
    final flag = (argResults!['token'] as String?)?.trim();
    if (flag != null && flag.isNotEmpty) return flag;
    final piped = readSecret(prompt: 'Modrinth token for $baseUrl: ').trim();
    if (piped.isEmpty) throw const UserError('No token provided.');
    return piped;
  }
}

class ModrinthLogoutCommand extends GitrinthCommand {
  @override
  String get name => 'logout';

  @override
  String get description =>
      'Clear the stored Modrinth token for the default server.';

  @override
  String get invocation => 'gitrinth modrinth logout';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
    final baseUrl = resolveModrinthBaseUrl(read(environmentProvider));

    final store = read(userConfigStoreProvider);
    final current = store.read();
    if (current.tokenFor(baseUrl) == null) {
      console.message('Not logged in to $baseUrl.');
      return exitOk;
    }
    store.write(current.withoutToken(baseUrl));
    console.message('Logged out of $baseUrl.');
    return exitOk;
  }
}

class ModrinthTokenCommand extends GitrinthCommand {
  @override
  String get name => 'token';

  @override
  String get description =>
      'Manage tokens for non-default Modrinth-compatible servers.';

  @override
  String get invocation => 'gitrinth modrinth token <subcommand>';

  ModrinthTokenCommand() {
    addSubcommand(ModrinthTokenAddCommand());
    addSubcommand(ModrinthTokenListCommand());
    addSubcommand(ModrinthTokenRemoveCommand());
  }

  @override
  Future<int> run() async {
    printUsage();
    return exitOk;
  }
}

class ModrinthTokenAddCommand extends GitrinthCommand {
  @override
  String get name => 'add';

  @override
  String get description =>
      'Prompt for a token and store it under <server-url>.';

  @override
  String get invocation =>
      'gitrinth modrinth token add <server-url> [--token <pat>]';

  ModrinthTokenAddCommand() {
    argParser.addOption(
      'token',
      valueHelp: 'pat',
      help:
          'Pass the personal access token directly (headless / CI). '
          'Falls back to a hidden stdin prompt when omitted.',
    );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError('Missing <server-url>.');
    }
    if (rest.length > 1) {
      throw UsageError('Unexpected arguments: ${rest.skip(1).join(' ')}');
    }
    final String key;
    try {
      key = normalizeServerKey(rest.single);
    } on FormatException catch (e) {
      throw UserError(e.message);
    }

    final flag = (argResults!['token'] as String?)?.trim();
    final String token;
    if (flag != null && flag.isNotEmpty) {
      token = flag;
    } else {
      final piped = readSecret(prompt: 'Modrinth token for $key: ').trim();
      if (piped.isEmpty) throw const UserError('No token provided.');
      token = piped;
    }

    final username = await _validateTokenAgainstUserEndpoint(
      read(dioProvider),
      key,
      token,
    );

    final store = read(userConfigStoreProvider);
    store.write(store.read().withToken(key, token));

    console.message('Stored token for $key (user: $username).');
    return exitOk;
  }
}

class ModrinthTokenListCommand extends GitrinthCommand {
  @override
  String get name => 'list';

  @override
  String get description =>
      'List every server with a stored token (tokens are masked).';

  @override
  String get invocation => 'gitrinth modrinth token list';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
    final env = read(environmentProvider);
    final defaultKey = normalizeServerKey(resolveModrinthBaseUrl(env));
    final envOverride = (env['GITRINTH_TOKEN'] ?? '').isNotEmpty;

    final cfg = read(userConfigStoreProvider).read();
    if (cfg.tokens.isEmpty) {
      console.message(
        envOverride
            ? '(no stored tokens; GITRINTH_TOKEN override active for $defaultKey)'
            : '(no stored tokens)',
      );
      return exitOk;
    }
    final entries = cfg.tokens.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final masked = _maskToken(entry.value);
      final suffix = (envOverride && entry.key == defaultKey)
          ? ' (GITRINTH_TOKEN override)'
          : '';
      console.message('${entry.key}  $masked$suffix');
    }
    if (envOverride && !cfg.tokens.containsKey(defaultKey)) {
      console.message('$defaultKey  <env>  (GITRINTH_TOKEN override)');
    }
    return exitOk;
  }
}

class ModrinthTokenRemoveCommand extends GitrinthCommand {
  @override
  String get name => 'remove';

  @override
  String get description => 'Clear the stored token for <server-url>.';

  @override
  String get invocation => 'gitrinth modrinth token remove <server-url>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError('Missing <server-url>.');
    }
    if (rest.length > 1) {
      throw UsageError('Unexpected arguments: ${rest.skip(1).join(' ')}');
    }
    final String key;
    try {
      key = normalizeServerKey(rest.single);
    } on FormatException catch (e) {
      throw UserError(e.message);
    }
    final store = read(userConfigStoreProvider);
    final current = store.read();
    if (!current.tokens.containsKey(key)) {
      throw UserError('No stored token for $key.');
    }
    store.write(current.withoutToken(key));
    console.message('Removed token for $key.');
    return exitOk;
  }
}

/// GETs `<baseUrl>/user` with [token] attached directly so the auth
/// interceptor's lookup doesn't substitute a different stored token.
/// Returns the username from the response body.
Future<String> _validateTokenAgainstUserEndpoint(
  Dio dio,
  String baseUrl,
  String token,
) async {
  final url = baseUrl.endsWith('/') ? '${baseUrl}user' : '$baseUrl/user';
  try {
    final response = await dio.get<dynamic>(
      url,
      options: Options(headers: {'Authorization': token}),
    );
    final body = response.data;
    if (body is Map && body['username'] is String) {
      return body['username'] as String;
    }
    return '<unknown>';
  } on DioException catch (e) {
    if (e.error is AuthenticationError) rethrow;
    if (e.response?.statusCode == 401) {
      throw AuthenticationError('Token rejected by $baseUrl.');
    }
    rethrow;
  }
}

String _maskToken(String token) {
  if (token.length <= 8) return '*' * token.length;
  return '${token.substring(0, 4)}…${token.substring(token.length - 4)}';
}
