import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/loader_catalog_cache.dart';
import '../service/loader_descriptor_config.dart';
import '../service/loader_registry.dart';
import '../service/modrinth/modrinth_url.dart';
import '../service/user_config.dart';
import 'env.dart';
import 'providers.dart';
import 'runner_settings.dart';

class LoaderRegistryNotifier extends Notifier<LoaderRegistry> {
  @override
  LoaderRegistry build() {
    final settings = ref.watch(runnerSettingsProvider);
    final explicit = settings.loaderDescriptorsPath;
    String path;
    try {
      path =
          explicit ??
          p.join(
            p.dirname(
              resolveUserConfigPath(
                ref.read(environmentProvider),
                override: settings.configPath,
              ),
            ),
            'loaders.yaml',
          );
    } on UserError {
      return LoaderRegistry.builtins;
    }
    return LoaderDescriptorConfig.read(path, required: explicit != null);
  }

  void replace(LoaderRegistry registry) => state = registry;
}

final loaderRegistryProvider =
    NotifierProvider<LoaderRegistryNotifier, LoaderRegistry>(
      LoaderRegistryNotifier.new,
    );

Future<LoaderRegistry> prepareLoaderRegistry(
  ProviderContainer container,
  ModsYaml manifest, {
  required bool offline,
}) async {
  final cfFactory = container.read(curseForgeApiFactoryProvider);
  var registry = container.read(loaderRegistryProvider);
  final defaultHost = resolveModrinthBaseUrl(
    container.read(environmentProvider),
  );
  final hosts = {
    manifest.modrinthHost ?? defaultHost,
    for (final section in Section.values)
      for (final entry in manifest.sectionEntries(section).values)
        manifest.effectiveModrinthHost(entry, defaultHost),
  };
  final discoverMr =
      manifest.gitrinth.isPlatformEnabled(SourceKind.modrinth) ||
      Section.values.any(
        (section) => manifest
            .sectionEntries(section)
            .values
            .any(
              (entry) => entry.sources?.contains(SourceKind.modrinth) ?? false,
            ),
      );
  final discoverCf =
      manifest.gitrinth.isPlatformEnabled(SourceKind.curseforge) ||
      Section.values.any(
        (section) => manifest
            .sectionEntries(section)
            .values
            .any(
              (entry) =>
                  entry.sources?.contains(SourceKind.curseforge) ?? false,
            ),
      );
  final ids = [
    manifest.loader.mods,
    ?manifest.loader.plugins,
    ?manifest.loader.shaders,
  ];
  final catalogTag =
      !offline &&
      [
        (manifest.loader.mods, manifest.loader.modLoaderVersion),
        if (manifest.loader.plugins != null)
          (manifest.loader.plugins, manifest.loader.pluginLoaderVersion),
      ].any(
        (pair) =>
            registry[pair.$1]?.versionSource == VersionSourceFamily.catalog &&
            const {'stable', 'latest'}.contains(pair.$2),
      );
  final needsCatalog =
      catalogTag ||
      ids.any(
        (id) =>
            registry[id] == null ||
            (discoverMr &&
                registry[id]?.role != LoaderRole.vanilla &&
                hosts.any((host) => registry[id]?.modrinthTag(host) == null)),
      );
  if (needsCatalog) {
    for (final host in hosts) {
      final service = LoaderRegistryService(
        configured: registry,
        cache: LoaderCatalogCache(container.read(cacheProvider)),
        dio: container.read(dioProvider),
      );
      registry = await service.snapshot(
        modrinthHost: host,
        curseforgeHost: cfFactory.baseUrl,
        needed: ids,
        offline: offline,
        refresh: catalogTag,
        discoverModrinth: discoverMr,
        readCurseforge: discoverCf ? cfFactory.listMinecraftLoaders : null,
      );
    }
  }
  for (final pair in [
    (
      manifest.loader.mods,
      manifest.loader.hasModRuntime ? LoaderRole.mod : LoaderRole.vanilla,
    ),
    if (manifest.loader.plugins != null)
      (manifest.loader.plugins, LoaderRole.plugin),
    if (manifest.loader.shaders != null)
      (manifest.loader.shaders, LoaderRole.shader),
  ]) {
    final id = pair.$1;
    if (id == null) continue;
    final role = registry[id]?.role;
    if (role != pair.$2 && id != LoaderId.vanilla) {
      throw ValidationError(
        'Loader ${id.name} has role ${role?.name}, not ${pair.$2.name}.',
      );
    }
  }
  container.read(loaderRegistryProvider.notifier).replace(registry);
  return registry;
}
