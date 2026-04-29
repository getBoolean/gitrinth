import 'package:dio/dio.dart';

import '../version.dart';
import 'console.dart';
import 'modrinth_api.dart';
import 'modrinth_auth_interceptor.dart';
import 'modrinth_error_interceptor.dart';
import 'modrinth_rate_limit_interceptor.dart';
import 'modrinth_url.dart';
import 'offline_guard_interceptor.dart';

/// Builds and caches one [ModrinthApi] (with its own [Dio] +
/// [ModrinthRateLimitInterceptor]) per Modrinth-protocol host.
///
/// Modrinth's rate-limit budget is per-IP-per-host, so each labrinth
/// deployment gets its own interceptor instance. Auth, offline, and
/// error behavior are wired the same way the global `dioProvider`
/// wires them — they're just one factory away now instead of one
/// shared singleton.
class ModrinthApiFactory {
  final Console _console;
  final ModrinthAuthInterceptor _auth;
  final bool Function() _offline;
  final String defaultBaseUrl;

  final Map<String, _HostBundle> _bundles = {};

  ModrinthApiFactory({
    required Console console,
    required ModrinthAuthInterceptor auth,
    required bool Function() offline,
    required this.defaultBaseUrl,
  }) : _console = console,
       _auth = auth,
       _offline = offline;

  /// Returns the cached [ModrinthApi] for [hostUrl], building one if
  /// missing. `null` / empty resolves to [_defaultBaseUrl].
  ModrinthApi forHost(String? hostUrl) {
    final raw = (hostUrl == null || hostUrl.trim().isEmpty)
        ? defaultBaseUrl
        : hostUrl.trim();
    final key = _normalize(raw);
    final cached = _bundles[key];
    if (cached != null) return cached.api;
    final dio = Dio();
    dio
      ..interceptors.add(OfflineGuardInterceptor(_offline))
      ..interceptors.add(_auth)
      ..interceptors.add(
        ModrinthRateLimitInterceptor(
          dio: dio,
          modrinthBaseUrl: raw,
          console: _console,
        ),
      )
      ..interceptors.add(ModrinthErrorInterceptor())
      ..options.headers['User-Agent'] =
          'gitrinth/$packageVersion (+github.com/getBoolean/gitrinth)';
    final api = ModrinthApi(dio, baseUrl: raw);
    _bundles[key] = _HostBundle(dio: dio, api: api);
    return api;
  }

  /// Disposes every cached client. Riverpod's `onDispose` plumbing
  /// calls this when the factory provider tears down.
  void close() {
    for (final bundle in _bundles.values) {
      bundle.dio.close(force: true);
    }
    _bundles.clear();
  }

  static String _normalize(String url) {
    try {
      return normalizeServerKey(url);
    } on FormatException {
      return url;
    }
  }
}

class _HostBundle {
  final Dio dio;
  final ModrinthApi api;

  _HostBundle({required this.dio, required this.api});
}
