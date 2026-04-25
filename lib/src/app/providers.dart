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
import '../service/offline_guard_interceptor.dart';
import '../version.dart';
import 'env.dart';
import 'offline_notifier.dart';

final consoleProvider = Provider<Console>((ref) => const Console());

final offlineProvider = NotifierProvider<OfflineNotifier, bool>(
  OfflineNotifier.new,
);

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio()
    ..interceptors.add(
      OfflineGuardInterceptor(() => ref.read(offlineProvider)),
    )
    ..interceptors.add(ModrinthErrorInterceptor())
    ..options.headers['User-Agent'] =
        'gitrinth/$packageVersion (+github.com/getBoolean/gitrinth)';
  ref.onDispose(dio.close);
  return dio;
});

final modrinthApiProvider = Provider<ModrinthApi>(
  (ref) => ModrinthApi(
    ref.read(dioProvider),
    baseUrl: resolveModrinthBaseUrl(ref.read(environmentProvider)),
  ),
);

final cacheProvider = Provider<GitrinthCache>(
  (ref) =>
      GitrinthCache(root: resolveCacheRoot(ref.read(environmentProvider))),
);

final downloaderProvider = Provider<Downloader>(
  (ref) =>
      Downloader(dio: ref.read(dioProvider), cache: ref.read(cacheProvider)),
);

final loaderVersionResolverProvider = Provider<LoaderVersionResolver>(
  (ref) => LoaderVersionResolver(
    dio: ref.read(dioProvider),
    environment: ref.read(environmentProvider),
  ),
);
