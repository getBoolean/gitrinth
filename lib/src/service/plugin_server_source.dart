import 'dart:io';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import 'build_tools_runner.dart';
import 'cache.dart';
import 'console.dart';
import 'downloader.dart';
import 'paper_api_client.dart';
import 'sponge_api_client.dart';

/// Resolves a server binary for a [PluginLoader]. One implementation per
/// loader; selected via [PluginServerSource.forLoader].
abstract class PluginServerSource {
  /// Returns the cached server jar. May trigger a long-running build
  /// (BuildTools for spigot/craftbukkit). Honours [offline].
  Future<File> fetchServerJar({
    required String mcVersion,
    required String pluginLoaderVersion,
    required bool offline,
    required Console console,
    String? javaPath,
    bool allowManagedJava = true,
  });

  /// Identifier baked into the install marker file so re-runs are
  /// idempotent across builds.
  String get installMarker;

  /// Strategy lookup — single switch, single source of truth. Future
  /// loaders add a row here and a class below. The Sponge variants
  /// (`spongeforge` / `spongeneo` / `spongevanilla`) are distinct
  /// `PluginLoader` values so the artifact is selected directly here
  /// without consulting `loader.mods`.
  static PluginServerSource forLoader(
    PluginLoader loader, {
    required PaperApiClient paperApi,
    required SpongeApiClient spongeApi,
    required BuildToolsRunner buildTools,
    required GitrinthCache cache,
    required Downloader downloader,
  }) {
    switch (loader) {
      case PluginLoader.paper:
      case PluginLoader.folia:
        return _PaperLikeSource(
          loader: loader,
          paperApi: paperApi,
          cache: cache,
          downloader: downloader,
        );
      case PluginLoader.spongeforge:
        return _SpongeSource(
          modLoader: SpongeLoader.forge,
          spongeApi: spongeApi,
          cache: cache,
          downloader: downloader,
        );
      case PluginLoader.spongeneo:
        return _SpongeSource(
          modLoader: SpongeLoader.neoforge,
          spongeApi: spongeApi,
          cache: cache,
          downloader: downloader,
        );
      case PluginLoader.spongevanilla:
        return _SpongeSource(
          modLoader: SpongeLoader.vanilla,
          spongeApi: spongeApi,
          cache: cache,
          downloader: downloader,
        );
      case PluginLoader.spigot:
        return _BuildToolsSource(
          flavor: SpigotFlavor.spigot,
          buildTools: buildTools,
        );
      case PluginLoader.bukkit:
        return _BuildToolsSource(
          flavor: SpigotFlavor.craftbukkit,
          buildTools: buildTools,
        );
    }
  }
}

class _PaperLikeSource implements PluginServerSource {
  final PluginLoader loader;
  final PaperApiClient paperApi;
  final GitrinthCache cache;
  final Downloader downloader;

  _PaperLikeSource({
    required this.loader,
    required this.paperApi,
    required this.cache,
    required this.downloader,
  });

  @override
  String get installMarker => 'plugin-${loader.name}';

  @override
  Future<File> fetchServerJar({
    required String mcVersion,
    required String pluginLoaderVersion,
    required bool offline,
    required Console console,
    String? javaPath,
    bool allowManagedJava = true,
  }) async {
    final project = loader.name; // paper / folia
    if (offline) {
      final cached = _findCached(project, mcVersion, pluginLoaderVersion);
      if (cached != null) return cached;
      throw UserError(
        'no cached $project server jar for Minecraft $mcVersion '
        'build $pluginLoaderVersion under '
        '${cache.pluginServersRoot}/$project/$mcVersion/$pluginLoaderVersion/. '
        'Rerun without --offline to fetch one.',
      );
    }
    final build = await paperApi.buildByNumber(
      project: project,
      mc: mcVersion,
      build: int.parse(pluginLoaderVersion),
    );
    final dest = cache.pluginServerJarPath(
      artifactKey: project,
      mcVersion: mcVersion,
      version: pluginLoaderVersion,
      filename: build.filename,
    );
    return downloader.downloadTo(
      url: build.downloadUrl.toString(),
      destinationPath: dest,
    );
  }

  File? _findCached(String project, String mc, String pluginLoaderVersion) {
    final dir = Directory(
      '${cache.pluginServersRoot}/$project/$mc/$pluginLoaderVersion',
    );
    if (!dir.existsSync()) return null;
    File? newest;
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      for (final inner in entry.listSync()) {
        if (inner is File && inner.path.toLowerCase().endsWith('.jar')) {
          if (newest == null ||
              inner.lastModifiedSync().isAfter(newest.lastModifiedSync())) {
            newest = inner;
          }
        }
      }
    }
    return newest;
  }
}

class _SpongeSource implements PluginServerSource {
  final SpongeLoader modLoader;
  final SpongeApiClient spongeApi;
  final GitrinthCache cache;
  final Downloader downloader;

  _SpongeSource({
    required this.modLoader,
    required this.spongeApi,
    required this.cache,
    required this.downloader,
  });

  String get _artifact => switch (modLoader) {
    SpongeLoader.forge => 'spongeforge',
    SpongeLoader.neoforge => 'spongeneo',
    SpongeLoader.vanilla => 'spongevanilla',
  };

  @override
  String get installMarker => 'plugin-$_artifact';

  @override
  Future<File> fetchServerJar({
    required String mcVersion,
    required String pluginLoaderVersion,
    required bool offline,
    required Console console,
    String? javaPath,
    bool allowManagedJava = true,
  }) async {
    if (offline) {
      final cached = _findCached(mcVersion, pluginLoaderVersion);
      if (cached != null) return cached;
      throw UserError(
        'no cached $_artifact server jar for Minecraft $mcVersion '
        'version $pluginLoaderVersion under '
        '${cache.pluginServersRoot}/$_artifact/$mcVersion/$pluginLoaderVersion/. '
        'Rerun without --offline to fetch one.',
      );
    }
    final build = await spongeApi.buildByVersion(
      artifact: _artifact,
      version: pluginLoaderVersion,
      mc: mcVersion,
    );
    final dest = cache.pluginServerJarPath(
      artifactKey: _artifact,
      mcVersion: mcVersion,
      version: pluginLoaderVersion,
      filename: build.filename,
    );
    return downloader.downloadTo(
      url: build.downloadUrl.toString(),
      destinationPath: dest,
    );
  }

  File? _findCached(String mc, String pluginLoaderVersion) {
    final dir = Directory(
      '${cache.pluginServersRoot}/$_artifact/$mc/$pluginLoaderVersion',
    );
    if (!dir.existsSync()) return null;
    File? newest;
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      for (final inner in entry.listSync()) {
        if (inner is File && inner.path.toLowerCase().endsWith('.jar')) {
          if (newest == null ||
              inner.lastModifiedSync().isAfter(newest.lastModifiedSync())) {
            newest = inner;
          }
        }
      }
    }
    return newest;
  }
}

class _BuildToolsSource implements PluginServerSource {
  final SpigotFlavor flavor;
  final BuildToolsRunner buildTools;

  _BuildToolsSource({required this.flavor, required this.buildTools});

  @override
  String get installMarker => 'plugin-${flavor.name}';

  @override
  Future<File> fetchServerJar({
    required String mcVersion,
    required String pluginLoaderVersion,
    required bool offline,
    required Console console,
    String? javaPath,
    bool allowManagedJava = true,
  }) {
    return buildTools.buildSpigotFamily(
      mc: mcVersion,
      flavor: flavor,
      buildToolsVersion: pluginLoaderVersion,
      console: console,
      offline: offline,
      javaPath: javaPath,
      allowManagedJava: allowManagedJava,
    );
  }
}
