import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart';

import '../service/build_tools_runner.dart';
import '../service/cache.dart';
import '../service/cache_root.dart';
import '../service/console.dart';
import '../service/downloader.dart';
import '../service/java_runtime_fetcher.dart';
import '../service/java_runtime_resolver.dart';
import '../service/loader_binary_fetcher.dart';
import '../service/loader_client_installer.dart';
import '../service/mod_loader_version_resolver.dart';
import '../service/minecraft_launcher_locator.dart';
import '../service/paper_api_client.dart';
import '../service/plugin_loader_version_resolver.dart';
import '../service/server_installer.dart';
import '../service/sponge_api_client.dart';
import '../service/vanilla_server_source.dart';
import '../service/modrinth_api_factory.dart';
import '../service/modrinth_auth_interceptor.dart';
import '../service/modrinth_error_interceptor.dart';
import '../service/modrinth_rate_limit_interceptor.dart';
import '../service/modrinth_url.dart';
import '../service/offline_guard_interceptor.dart';
import '../service/user_config.dart';
import '../cli/exceptions.dart';
import '../version.dart';
import 'env.dart';
import 'offline_notifier.dart';
import 'runner_settings.dart';

final consoleProvider = Provider<Console>((ref) {
  final settings = ref.watch(runnerSettingsProvider);
  final env = ref.read(environmentProvider);
  return Console(
    level: settings.level,
    useAnsi: Console.resolveUseAnsi(settings.color, env),
  );
});

final offlineProvider = NotifierProvider<OfflineNotifier, bool>(
  OfflineNotifier.new,
);

final modrinthAuthInterceptorProvider = Provider<ModrinthAuthInterceptor>((
  ref,
) {
  final env = ref.read(environmentProvider);
  return ModrinthAuthInterceptor(
    // No config path resolvable (no --config, no GITRINTH_CONFIG, no HOME)
    // means there's nowhere to read tokens from — fall back to empty.
    tokensProvider: () {
      try {
        return ref.read(userConfigStoreProvider).read().tokens;
      } on UserError {
        return const <String, String>{};
      }
    },
    envTokenLookup: () => env['GITRINTH_TOKEN'],
    defaultBaseUrl: resolveModrinthBaseUrl(env),
  );
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio();
  dio
    ..interceptors.add(OfflineGuardInterceptor(() => ref.read(offlineProvider)))
    ..interceptors.add(ref.read(modrinthAuthInterceptorProvider))
    ..interceptors.add(
      ModrinthRateLimitInterceptor(
        dio: dio,
        modrinthBaseUrl: resolveModrinthBaseUrl(ref.read(environmentProvider)),
        console: ref.read(consoleProvider),
      ),
    )
    ..interceptors.add(ModrinthErrorInterceptor())
    ..options.headers['User-Agent'] =
        'gitrinth/$packageVersion (+github.com/getBoolean/gitrinth)';
  ref.onDispose(dio.close);
  return dio;
});

final modrinthApiFactoryProvider = Provider<ModrinthApiFactory>((ref) {
  final factory = ModrinthApiFactory(
    console: ref.read(consoleProvider),
    auth: ref.read(modrinthAuthInterceptorProvider),
    offline: () => ref.read(offlineProvider),
    defaultBaseUrl: resolveModrinthBaseUrl(ref.read(environmentProvider)),
  );
  ref.onDispose(factory.close);
  return factory;
});

final cacheProvider = Provider<GitrinthCache>(
  (ref) => GitrinthCache(
    root: resolveCacheRoot(ref.read(environmentProvider)),
    console: ref.read(consoleProvider),
  ),
);

final downloaderProvider = Provider<Downloader>(
  (ref) =>
      Downloader(dio: ref.read(dioProvider), cache: ref.read(cacheProvider)),
);

final modLoaderVersionResolverProvider = Provider<ModLoaderVersionResolver>(
  (ref) => ModLoaderVersionResolver(
    dio: ref.read(dioProvider),
    environment: ref.read(environmentProvider),
  ),
);

final loaderBinaryFetcherProvider = Provider<LoaderBinaryFetcher>(
  (ref) => LoaderBinaryFetcher(
    cache: ref.read(cacheProvider),
    downloader: ref.read(downloaderProvider),
    environment: ref.read(environmentProvider),
  ),
);

final javaRuntimeFetcherProvider = Provider<JavaRuntimeFetcher>(
  (ref) => JavaRuntimeFetcher(
    cache: ref.read(cacheProvider),
    downloader: ref.read(downloaderProvider),
    console: ref.read(consoleProvider),
    environment: ref.read(environmentProvider),
  ),
);

final javaRuntimeResolverProvider = Provider<JavaRuntimeResolver>(
  (ref) => JavaRuntimeResolver(
    fetcher: ref.read(javaRuntimeFetcherProvider),
    environment: ref.read(environmentProvider),
    console: ref.read(consoleProvider),
  ),
);

final vanillaServerSourceProvider = Provider<VanillaServerSource>(
  (ref) => VanillaServerSource(
    dio: ref.read(dioProvider),
    downloader: ref.read(downloaderProvider),
    cache: ref.read(cacheProvider),
  ),
);

final serverInstallerProvider = Provider<ServerInstaller>(
  (ref) => ServerInstaller(
    environment: ref.read(environmentProvider),
    resolver: ref.read(javaRuntimeResolverProvider),
    console: ref.read(consoleProvider),
  ),
);

final minecraftLauncherLocatorProvider = Provider<MinecraftLauncherLocator>(
  (ref) => MinecraftLauncherLocator(environment: ref.read(environmentProvider)),
);

final loaderClientInstallerProvider = Provider<LoaderClientInstaller>(
  (ref) => LoaderClientInstaller(
    environment: ref.read(environmentProvider),
    resolver: ref.read(javaRuntimeResolverProvider),
    console: ref.read(consoleProvider),
  ),
);

final paperApiClientProvider = Provider<PaperApiClient>(
  (ref) => PaperApiClient(
    dio: ref.read(dioProvider),
    environment: ref.read(environmentProvider),
  ),
);

final spongeApiClientProvider = Provider<SpongeApiClient>(
  (ref) => SpongeApiClient(
    dio: ref.read(dioProvider),
    environment: ref.read(environmentProvider),
  ),
);

final pluginLoaderVersionResolverProvider =
    Provider<PluginLoaderVersionResolver>(
      (ref) => PluginLoaderVersionResolver(
        dio: ref.read(dioProvider),
        paperApi: ref.read(paperApiClientProvider),
        spongeApi: ref.read(spongeApiClientProvider),
        environment: ref.read(environmentProvider),
      ),
    );

final buildToolsRunnerProvider = Provider<BuildToolsRunner>(
  (ref) => BuildToolsRunner(
    downloader: ref.read(downloaderProvider),
    cache: ref.read(cacheProvider),
    resolver: ref.read(javaRuntimeResolverProvider),
    environment: ref.read(environmentProvider),
  ),
);
