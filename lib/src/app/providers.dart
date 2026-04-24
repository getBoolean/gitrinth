import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart';

import '../service/cache.dart';
import '../service/cache_root.dart';
import '../service/console.dart';
import '../service/downloader.dart';
import '../service/loader_version_resolver.dart';
import '../service/modrinth_api.dart';
import '../service/modrinth_error_interceptor.dart';
import '../service/modrinth_url.dart';
import '../version.dart';

final consoleProvider = Provider<Console>((ref) => const Console());

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio()
    ..interceptors.add(ModrinthErrorInterceptor())
    ..options.headers['User-Agent'] =
        'gitrinth/$packageVersion (+github.com/BooleanDev/modrinth_git_modpacks)';
  ref.onDispose(dio.close);
  return dio;
});

final modrinthApiProvider = Provider<ModrinthApi>(
  (ref) =>
      ModrinthApi(ref.read(dioProvider), baseUrl: resolveModrinthBaseUrl()),
);

final cacheProvider = Provider<GitrinthCache>(
  (ref) => GitrinthCache(root: resolveCacheRoot()),
);

final downloaderProvider = Provider<Downloader>(
  (ref) =>
      Downloader(dio: ref.read(dioProvider), cache: ref.read(cacheProvider)),
);

final loaderVersionResolverProvider = Provider<LoaderVersionResolver>(
  (ref) => LoaderVersionResolver(dio: ref.read(dioProvider)),
);
