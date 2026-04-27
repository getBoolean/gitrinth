import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import 'cache.dart';
import 'downloader.dart';

/// Fetches the official Mojang `server.jar` for a given Minecraft
/// version. Used by `gitrinth build server` when the pack declares
/// neither a plugin loader nor a mod loader (pure-vanilla server).
///
/// Resolution chases Mojang's piston-meta indirection: the top-level
/// version manifest enumerates every release and points at a per-
/// version metadata blob that carries the actual server-jar URL.
class VanillaServerSource {
  static const String _versionManifestUrl =
      'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';

  /// Marker baked into the install marker file by [ServerInstaller] so
  /// re-runs are idempotent.
  static const String installMarker = 'vanilla';

  final Dio dio;
  final Downloader downloader;
  final GitrinthCache cache;

  VanillaServerSource({
    required this.dio,
    required this.downloader,
    required this.cache,
  });

  Future<File> fetchServerJar({
    required String mcVersion,
    required bool offline,
  }) async {
    final dest = cache.pluginServerJarPath(
      artifactKey: 'vanilla',
      mcVersion: mcVersion,
      version: mcVersion,
      filename: 'server.jar',
    );
    final destFile = File(dest);
    if (destFile.existsSync()) return destFile;
    if (offline) {
      throw UserError(
        'no cached vanilla server jar for Minecraft $mcVersion under '
        '${cache.pluginServersRoot}/vanilla/$mcVersion/. Rerun without '
        '--offline to fetch one from piston-meta.mojang.com.',
      );
    }
    final manifestEntry = await _findManifestEntry(mcVersion);
    final versionMeta = await _fetchJson(
      manifestEntry['url'] as String,
      'piston-meta.mojang.com',
    );
    final downloads = versionMeta['downloads'];
    if (downloads is! Map || downloads['server'] is! Map) {
      throw UserError(
        'piston-meta entry for Minecraft $mcVersion has no `downloads.server` '
        'block (likely an old version with no server distribution).',
      );
    }
    final server = (downloads['server'] as Map).cast<String, dynamic>();
    final url = server['url'];
    if (url is! String) {
      throw UserError(
        'piston-meta entry for Minecraft $mcVersion has no server jar URL.',
      );
    }
    // piston-meta publishes sha1, not sha512; the Downloader only
    // checks sha512, so the integrity check is deferred to the
    // launcher's first start (a corrupt jar fails immediately there).
    return downloader.downloadTo(url: url, destinationPath: dest);
  }

  Future<Map<String, dynamic>> _findManifestEntry(String mcVersion) async {
    final manifest = await _fetchJson(
      _versionManifestUrl,
      'piston-meta.mojang.com',
    );
    final versions = manifest['versions'];
    if (versions is! List) {
      throw const UserError(
        'piston-meta version manifest had no `versions` array.',
      );
    }
    for (final v in versions) {
      if (v is Map && v['id'] == mcVersion) {
        return v.cast<String, dynamic>();
      }
    }
    throw UserError(
      'Minecraft version "$mcVersion" not found in piston-meta version '
      'manifest.',
    );
  }

  Future<Map<String, dynamic>> _fetchJson(String url, String host) async {
    try {
      final r = await dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final body = r.data;
      if (body is! String) {
        throw UserError('$host: response was not text JSON.');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw UserError('$host: response was not a JSON object.');
      }
      return decoded.cast<String, dynamic>();
    } on DioException catch (e) {
      throw UserError('failed to fetch $url: $e');
    } on FormatException catch (e) {
      throw UserError('$host returned malformed JSON: ${e.message}');
    }
  }
}
