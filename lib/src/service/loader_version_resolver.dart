import 'dart:io';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';

/// Resolves the docker-style `<loader>:<tag>` syntax in `mods.yaml` to a
/// concrete loader version.
///
/// `tag` is one of:
///   - `stable`  — newest loader version flagged stable upstream.
///   - `latest`  — newest loader version regardless of stability.
///   - any other string — treated as a concrete version and returned
///     unchanged (no network call, no validation).
///
/// Concrete tags are the load-bearing path: typing `fabric:0.17.3` skips
/// every network call. `stable`/`latest` exist precisely to drift, so
/// they always re-resolve.
class LoaderVersionResolver {
  final Dio _dio;

  LoaderVersionResolver({required Dio dio}) : _dio = dio;

  /// Returns the concrete loader version for [loader] given [tag].
  /// [mcVersion] is currently unused but reserved for forge/neoforge
  /// resolution which is per-Minecraft-version.
  Future<String> resolve({
    required Loader loader,
    required String tag,
    required String mcVersion,
  }) async {
    if (tag != 'stable' && tag != 'latest') {
      // Concrete version — trust the user. Modrinth pack clients will
      // surface a real install error if it doesn't exist.
      return tag;
    }
    switch (loader) {
      case Loader.fabric:
        return _resolveFabric(tag);
      case Loader.forge:
      case Loader.neoforge:
        throw UserError(
          'automatic loader-version resolution for ${loader.name} is '
          'not yet implemented; specify a concrete tag like '
          '`${loader.name}:<version>` in mods.yaml '
          '(see https://maven.neoforged.net or '
          'https://files.minecraftforge.net for available versions).',
        );
    }
  }

  Future<String> _resolveFabric(String tag) async {
    final List<dynamic> body;
    final url =
        Platform.environment['GITRINTH_FABRIC_META_URL'] ??
        'https://meta.fabricmc.net/v2/versions/loader';
    try {
      final resp = await _dio.get<List<dynamic>>(url);
      body = resp.data ?? const [];
    } on DioException catch (e) {
      throw UserError(
        'failed to fetch Fabric loader versions from meta.fabricmc.net: '
        '${e.message ?? e.toString()}',
      );
    }
    if (body.isEmpty) {
      throw const UserError(
        'Fabric loader version list from meta.fabricmc.net was empty.',
      );
    }
    // Newest first by upstream contract.
    for (final raw in body) {
      if (raw is! Map) continue;
      final version = raw['version'];
      if (version is! String) continue;
      if (tag == 'latest') return version;
      if (tag == 'stable' && raw['stable'] == true) return version;
    }
    throw UserError(
      'no Fabric loader version matched tag `$tag` '
      '(received ${body.length} entries).',
    );
  }
}
