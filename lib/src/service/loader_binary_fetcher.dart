import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import '../util/url_template.dart';
import 'cache.dart';
import 'dio_error_helpers.dart';
import 'downloader.dart';

/// Fetches and caches the loader binary needed to run a server distribution
/// (Forge/NeoForge installer JAR, or fabric-server-launch JAR). The actual
/// "installation" step (running `--installServer` on Forge/NeoForge installers)
/// is the [ServerInstaller]'s job; this service is only responsible for the
/// download + cache layout.
///
/// Mirrors the URL-override pattern in [ModLoaderVersionResolver]: the constructor
/// takes optional URL templates with `{mc}`/`{v}` placeholders, falling back
/// to environment variables, and finally to the real upstream URLs.
class LoaderBinaryFetcher {
  final LoaderRegistry _registry;
  final GitrinthCache _cache;
  final Downloader _downloader;
  final String _forgeInstallerUrlTemplate;
  final String _neoforgeInstallerUrlTemplate;
  final String _neoforgeLegacyInstallerUrlTemplate;
  final String _fabricServerJarUrlTemplate;
  final String _fabricInstallerUrlTemplate;
  final String _fabricInstallerVersion;
  final String _quiltInstallerMetaUrl;

  LoaderBinaryFetcher({
    LoaderRegistry registry = LoaderRegistry.builtins,
    required GitrinthCache cache,
    required Downloader downloader,
    Map<String, String>? environment,
    String? forgeInstallerUrlTemplate,
    String? neoforgeInstallerUrlTemplate,
    String? neoforgeLegacyInstallerUrlTemplate,
    String? fabricServerJarUrlTemplate,
    String? fabricInstallerUrlTemplate,
    String? fabricInstallerVersion,
  }) : _quiltInstallerMetaUrl =
           (environment ??
               Platform.environment)['GITRINTH_QUILT_INSTALLER_META_URL'] ??
           'https://meta.quiltmc.org/v3/versions/installer',
       _registry = registry,
       _cache = cache,
       _downloader = downloader,
       _forgeInstallerUrlTemplate =
           forgeInstallerUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_FORGE_INSTALLER_URL'] ??
           'https://maven.minecraftforge.net/net/minecraftforge/forge/'
               '{mc}-{v}/forge-{mc}-{v}-installer.jar',
       _neoforgeInstallerUrlTemplate =
           neoforgeInstallerUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_NEOFORGE_INSTALLER_URL'] ??
           'https://maven.neoforged.net/releases/net/neoforged/neoforge/'
               '{v}/neoforge-{v}-installer.jar',
       _neoforgeLegacyInstallerUrlTemplate =
           neoforgeLegacyInstallerUrlTemplate ??
           (environment ??
               Platform
                   .environment)['GITRINTH_NEOFORGE_LEGACY_INSTALLER_URL'] ??
           'https://maven.neoforged.net/releases/net/neoforged/forge/'
               '{mc}-{v}/forge-{mc}-{v}-installer.jar',
       _fabricServerJarUrlTemplate =
           fabricServerJarUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_FABRIC_SERVER_JAR_URL'] ??
           'https://meta.fabricmc.net/v2/versions/loader/'
               '{mc}/{v}/server/jar',
       _fabricInstallerUrlTemplate =
           fabricInstallerUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_FABRIC_INSTALLER_URL'] ??
           'https://maven.fabricmc.net/net/fabricmc/fabric-installer/'
               '{installerVersion}/fabric-installer-{installerVersion}.jar',
       _fabricInstallerVersion =
           fabricInstallerVersion ??
           (environment ??
               Platform.environment)['GITRINTH_FABRIC_INSTALLER_VERSION'] ??
           '1.0.1';

  /// Returns the cached loader server binary for [loader] +
  /// (`mcVersion`, `modLoaderVersion`). Downloads and caches on first call;
  /// later calls re-use the cached file. The returned file is keyed by
  /// [GitrinthCache.loaderArtifactPath] so the location is deterministic
  /// from inputs alone.
  Future<File> fetchServerArtifact({
    required ModLoader loader,
    required String mcVersion,
    required String modLoaderVersion,
  }) async {
    _validateVersion(mcVersion);
    _validateVersion(modLoaderVersion);
    if (_registry[loader]?.installer == InstallerFamily.quilt) {
      return _fetchQuiltInstaller(loader, mcVersion, modLoaderVersion);
    }
    final (url, filename) = _serverUrlAndFilename(
      loader: loader,
      mcVersion: mcVersion,
      modLoaderVersion: modLoaderVersion,
    );
    final dest = _cache.loaderArtifactPath(
      loader: loader,
      mcVersion: mcVersion,
      modLoaderVersion: modLoaderVersion,
      filename: filename,
    );
    try {
      return await _downloader.downloadTo(url: url, destinationPath: dest);
    } on GitrinthException {
      rethrow;
    } on DioException catch (e) {
      unwrapOrThrow(
        e,
        context: 'failed to download ${loader.name} server binary from $url',
      );
    }
  }

  /// Returns the cached loader **client** installer JAR for [loader] +
  /// (`mcVersion`, `modLoaderVersion`). For Forge/NeoForge the client and
  /// server use the same installer JAR (run with `--installClient`
  /// vs `--installServer`); for Fabric the universal installer JAR is a
  /// distinct artifact from the server-launch JAR.
  Future<File> fetchClientInstaller({
    required ModLoader loader,
    required String mcVersion,
    required String modLoaderVersion,
  }) async {
    _validateVersion(mcVersion);
    _validateVersion(modLoaderVersion);
    switch (_registry[loader]?.installer) {
      case InstallerFamily.vanilla:
        throw StateError(
          'fetchClientInstaller called for vanilla; gate on '
          'LoaderConfig.hasModRuntime.',
        );
      case InstallerFamily.forge:
        return fetchServerArtifact(
          loader: loader,
          mcVersion: mcVersion,
          modLoaderVersion: modLoaderVersion,
        );
      case InstallerFamily.fabric:
        final url = _fabricInstallerUrlTemplate.replaceAll(
          '{installerVersion}',
          _fabricInstallerVersion,
        );
        final dest = _cache.loaderArtifactPath(
          loader: loader,
          mcVersion: mcVersion,
          modLoaderVersion: modLoaderVersion,
          filename: 'fabric-installer.jar',
        );
        try {
          return await _downloader.downloadTo(url: url, destinationPath: dest);
        } on GitrinthException {
          rethrow;
        } on DioException catch (e) {
          unwrapOrThrow(
            e,
            context: 'failed to download Fabric installer from $url',
          );
        }
      case InstallerFamily.quilt:
        return _fetchQuiltInstaller(loader, mcVersion, modLoaderVersion);
      default:
        throw ValidationError(
          'Loader ${loader.name} has no installed adapter for this operation.',
        );
    }
  }

  (String url, String filename) _serverUrlAndFilename({
    required ModLoader loader,
    required String mcVersion,
    required String modLoaderVersion,
  }) {
    switch (_registry[loader]?.versionSource) {
      case null:
        throw StateError(
          '_serverUrlAndFilename called for vanilla; gate on '
          'LoaderConfig.hasModRuntime.',
        );
      case VersionSourceFamily.forge:
        final url = fillUrlTemplate(_forgeInstallerUrlTemplate, {
          'mc': mcVersion,
          'v': modLoaderVersion,
        });
        return (url, 'forge-$mcVersion-$modLoaderVersion-installer.jar');
      case VersionSourceFamily.neoforge:
        if (mcVersion == '1.20.1') {
          final url = fillUrlTemplate(_neoforgeLegacyInstallerUrlTemplate, {
            'mc': mcVersion,
            'v': modLoaderVersion,
          });
          return (url, 'forge-$mcVersion-$modLoaderVersion-installer.jar');
        }
        final url = fillUrlTemplate(_neoforgeInstallerUrlTemplate, {
          'v': modLoaderVersion,
        });
        return (url, 'neoforge-$modLoaderVersion-installer.jar');
      case VersionSourceFamily.fabric:
        final url = fillUrlTemplate(_fabricServerJarUrlTemplate, {
          'mc': mcVersion,
          'v': modLoaderVersion,
        });
        return (url, 'fabric-server-launch.jar');
      default:
        throw ValidationError(
          'Loader ${loader.name} has no installed adapter for this operation.',
        );
    }
  }

  static String serverArtifactFilename(
    LoaderId loader,
    String mc,
    String version, {
    LoaderRegistry registry = LoaderRegistry.builtins,
  }) {
    final descriptor = registry[loader];
    return switch (descriptor?.installer) {
      InstallerFamily.fabric => 'fabric-server-launch.jar',
      InstallerFamily.quilt => 'quilt-installer.jar',
      InstallerFamily.forge =>
        descriptor?.versionSource == VersionSourceFamily.neoforge &&
                mc != '1.20.1'
            ? 'neoforge-$version-installer.jar'
            : 'forge-$mc-$version-installer.jar',
      _ => throw ValidationError(
        'Loader ${loader.name} has no cached server runtime recipe.',
      ),
    };
  }

  static void _validateVersion(String value) {
    if (!isSafeRuntimeToken(value)) {
      throw ValidationError('Unsafe runtime version "$value".');
    }
  }

  Future<File> _fetchQuiltInstaller(
    LoaderId loader,
    String mc,
    String version,
  ) async {
    final destination = _cache.loaderArtifactPath(
      loader: loader,
      mcVersion: mc,
      modLoaderVersion: version,
      filename: 'quilt-installer.jar',
    );
    final metadataFile = File('$destination.metadata.json');
    Map<String, dynamic>? selected;
    if (metadataFile.existsSync()) {
      final raw = jsonDecode(metadataFile.readAsStringSync());
      if (raw is Map<String, dynamic>) selected = raw;
    }
    if (selected == null) {
      final response = await _downloader.dio.get<dynamic>(
        _quiltInstallerMetaUrl,
      );
      final raw = response.data;
      if (raw is! List || raw.isEmpty || raw.first is! Map) {
        throw const ValidationError('Quilt installer metadata is empty.');
      }
      selected = Map<String, dynamic>.from(raw.first as Map);
    }
    final installerVersion = selected['version'];
    final hashes = selected['hashes'];
    final hash = hashes is Map ? hashes['sha512'] : null;
    if (installerVersion is! String ||
        hash is! String ||
        !RegExp(r'^[a-fA-F0-9]{128}$').hasMatch(hash)) {
      throw const ValidationError(
        'Quilt installer metadata lacks a version or SHA512.',
      );
    }
    _validateVersion(installerVersion);
    final url =
        'https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/$installerVersion/quilt-installer-$installerVersion.jar';
    if (selected['url'] != url) {
      throw const ValidationError(
        'Quilt installer metadata has an untrusted artifact URL.',
      );
    }
    final artifact = await _downloader.downloadTo(
      url: url,
      destinationPath: destination,
      expectedSha512: hash,
    );
    metadataFile.parent.createSync(recursive: true);
    metadataFile.writeAsStringSync(jsonEncode(selected), flush: true);
    return artifact;
  }
}
