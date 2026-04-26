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
/// Mirrors the URL-override pattern in [LoaderVersionResolver]: the constructor
/// takes optional URL templates with `{mc}`/`{v}` placeholders, falling back
/// to environment variables, and finally to the real upstream URLs.
class LoaderBinaryFetcher {
  final GitrinthCache _cache;
  final Downloader _downloader;
  final String _forgeInstallerUrlTemplate;
  final String _neoforgeInstallerUrlTemplate;
  final String _neoforgeLegacyInstallerUrlTemplate;
  final String _fabricServerJarUrlTemplate;
  final String _fabricInstallerUrlTemplate;
  final String _fabricInstallerVersion;

  LoaderBinaryFetcher({
    required GitrinthCache cache,
    required Downloader downloader,
    Map<String, String>? environment,
    String? forgeInstallerUrlTemplate,
    String? neoforgeInstallerUrlTemplate,
    String? neoforgeLegacyInstallerUrlTemplate,
    String? fabricServerJarUrlTemplate,
    String? fabricInstallerUrlTemplate,
    String? fabricInstallerVersion,
  }) : _cache = cache,
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
  /// (`mcVersion`, `loaderVersion`). Downloads and caches on first call;
  /// later calls re-use the cached file. The returned file is keyed by
  /// [GitrinthCache.loaderArtifactPath] so the location is deterministic
  /// from inputs alone.
  Future<File> fetchServerArtifact({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    final (url, filename) = _serverUrlAndFilename(
      loader: loader,
      mcVersion: mcVersion,
      loaderVersion: loaderVersion,
    );
    final dest = _cache.loaderArtifactPath(
      loader: loader,
      mcVersion: mcVersion,
      loaderVersion: loaderVersion,
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
  /// (`mcVersion`, `loaderVersion`). For Forge/NeoForge the client and
  /// server use the same installer JAR (run with `--installClient`
  /// vs `--installServer`); for Fabric the universal installer JAR is a
  /// distinct artifact from the server-launch JAR.
  Future<File> fetchClientInstaller({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    switch (loader) {
      case Loader.forge:
      case Loader.neoforge:
        return fetchServerArtifact(
          loader: loader,
          mcVersion: mcVersion,
          loaderVersion: loaderVersion,
        );
      case Loader.fabric:
        final url = _fabricInstallerUrlTemplate.replaceAll(
          '{installerVersion}',
          _fabricInstallerVersion,
        );
        final dest = _cache.loaderArtifactPath(
          loader: loader,
          mcVersion: mcVersion,
          loaderVersion: loaderVersion,
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
    }
  }

  (String url, String filename) _serverUrlAndFilename({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
  }) {
    switch (loader) {
      case Loader.forge:
        final url = fillUrlTemplate(_forgeInstallerUrlTemplate, {
          'mc': mcVersion,
          'v': loaderVersion,
        });
        return (url, 'forge-$mcVersion-$loaderVersion-installer.jar');
      case Loader.neoforge:
        if (mcVersion == '1.20.1') {
          final url = fillUrlTemplate(_neoforgeLegacyInstallerUrlTemplate, {
            'mc': mcVersion,
            'v': loaderVersion,
          });
          return (url, 'forge-$mcVersion-$loaderVersion-installer.jar');
        }
        final url = fillUrlTemplate(_neoforgeInstallerUrlTemplate, {
          'v': loaderVersion,
        });
        return (url, 'neoforge-$loaderVersion-installer.jar');
      case Loader.fabric:
        final url = fillUrlTemplate(_fabricServerJarUrlTemplate, {
          'mc': mcVersion,
          'v': loaderVersion,
        });
        return (url, 'fabric-server-launch.jar');
    }
  }
}
