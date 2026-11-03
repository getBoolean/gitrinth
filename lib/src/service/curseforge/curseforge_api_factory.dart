import 'package:dio/dio.dart';

import '../../version.dart';
import '../console.dart';
import '../offline_guard_interceptor.dart';
import 'curseforge_api.dart';
import 'curseforge_auth_interceptor.dart';
import 'curseforge_error_interceptor.dart';
import 'curseforge_rate_limit_interceptor.dart';

/// Builds and caches a single [CurseForgeApi] (with its own [Dio] +
/// reactive [CurseForgeRateLimitInterceptor]) for the CurseForge read
/// API.
///
/// Unlike [ModrinthApiFactory], CurseForge has one canonical host so the
/// factory caches a single client bundle rather than a host-keyed map.
class CurseForgeApiFactory {
  final Console _console;
  final CurseForgeAuthInterceptor _auth;
  final bool Function() _offline;
  final String baseUrl;

  _Bundle? _bundle;

  CurseForgeApiFactory({
    required Console console,
    required CurseForgeAuthInterceptor auth,
    required bool Function() offline,
    required this.baseUrl,
  }) : _console = console,
       _auth = auth,
       _offline = offline;

  /// Returns the cached [CurseForgeApi], building one on first access.
  CurseForgeApi get api {
    final cached = _bundle;
    if (cached != null) return cached.api;
    final dio = Dio();
    dio
      ..interceptors.add(OfflineGuardInterceptor(_offline))
      ..interceptors.add(_auth)
      ..interceptors.add(
        CurseForgeRateLimitInterceptor(
          dio: dio,
          baseUrl: baseUrl,
          console: _console,
        ),
      )
      ..interceptors.add(CurseForgeErrorInterceptor())
      ..options.headers['User-Agent'] =
          'gitrinth/$packageVersion (+github.com/getBoolean/gitrinth)';
    final cf = CurseForgeApi(dio, baseUrl: baseUrl);
    _bundle = _Bundle(dio: dio, api: cf);
    return cf;
  }

  /// Raw provider catalog retains numeric loader types and version names.
  Future<List<Map<String, dynamic>>> listMinecraftLoaders() async {
    api; // Initialize the same authenticated bundle used by resolution.
    final client = dio;
    if (client == null) {
      throw StateError('CurseForge bundle was not initialized.');
    }
    final response = await client.get<dynamic>(
      '$baseUrl/v1/minecraft/modloader',
      options: Options(extra: const {kCurseForgeAuthRequired: true}),
    );
    final raw = response.data;
    final data = raw is Map ? raw['data'] : null;
    if (data is! List) {
      throw const FormatException(
        'CurseForge loader catalog must contain a data list.',
      );
    }
    return data
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  /// Returns the underlying [Dio] for the cached bundle. Visible for
  /// tests that need to inspect interceptor wiring.
  Dio? get dio => _bundle?.dio;

  /// Disposes the cached client.
  void close() {
    _bundle?.dio.close(force: true);
    _bundle = null;
  }
}

class _Bundle {
  final Dio dio;
  final CurseForgeApi api;

  _Bundle({required this.dio, required this.api});
}
