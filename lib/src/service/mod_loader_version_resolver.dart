import 'dart:io';

import 'package:dio/dio.dart';
import 'package:pub_semver/pub_semver.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import '../util/mc_version.dart';

/// Resolves the docker-style `<loader>:<tag>` syntax in `mods.yaml` to a
/// concrete loader version.
///
/// `tag` is one of:
///   - `stable`  — newest loader version flagged stable upstream.
///   - `latest`  — newest loader version regardless of stability.
///   - any other string — treated as a concrete version. Validated against
///     the upstream version list; resolves to the same string on success
///     or raises `UserError` if the build doesn't exist.
///
/// Concrete tags are validated against the upstream version list. The
/// orchestrator at [resolve_and_sync.dart] short-circuits this re-resolution
/// when `mods.lock` already records the same loader+version pair (so steady
/// state never hits the network), or when `--offline` is set.
class ModLoaderVersionResolver {
  final Dio _dio;
  final String _fabricMetaUrl;
  final String _forgePromotionsUrl;
  final String _forgeVersionsUrl;
  final String _neoforgeVersionsUrl;
  final String _neoforgeLegacyVersionsUrl;

  ModLoaderVersionResolver({
    required Dio dio,
    Map<String, String>? environment,
    String? fabricMetaUrl,
    String? forgePromotionsUrl,
    String? forgeVersionsUrl,
    String? neoforgeVersionsUrl,
    String? neoforgeLegacyVersionsUrl,
  }) : _dio = dio,
       _fabricMetaUrl =
           fabricMetaUrl ??
           (environment ?? Platform.environment)['GITRINTH_FABRIC_META_URL'] ??
           'https://meta.fabricmc.net/v2/versions/loader',
       _forgePromotionsUrl =
           forgePromotionsUrl ??
           (environment ??
               Platform.environment)['GITRINTH_FORGE_PROMOTIONS_URL'] ??
           'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json',
       _forgeVersionsUrl =
           forgeVersionsUrl ??
           (environment ??
               Platform.environment)['GITRINTH_FORGE_VERSIONS_URL'] ??
           'https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json',
       _neoforgeVersionsUrl =
           neoforgeVersionsUrl ??
           (environment ??
               Platform.environment)['GITRINTH_NEOFORGE_VERSIONS_URL'] ??
           'https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge',
       _neoforgeLegacyVersionsUrl =
           neoforgeLegacyVersionsUrl ??
           (environment ??
               Platform.environment)['GITRINTH_NEOFORGE_LEGACY_VERSIONS_URL'] ??
           'https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/forge';

  /// Returns the concrete loader version for [loader] given [tag].
  /// [mcVersion] is required for Forge and NeoForge resolution which is
  /// per-Minecraft-version. Fabric ignores it.
  Future<String> resolve({
    required ModLoader loader,
    required String tag,
    required String mcVersion,
  }) async {
    switch (loader) {
      case ModLoader.fabric:
        return _resolveFabric(tag);
      case ModLoader.forge:
        return _resolveForge(tag, mcVersion);
      case ModLoader.neoforge:
        return mcVersion == '1.20.1'
            ? _resolveNeoforgeLegacy(tag)
            : _resolveNeoforge(tag, mcVersion);
      case ModLoader.vanilla:
        throw StateError(
          'loader-version resolution is not defined for vanilla; '
          'callers must guard with LoaderConfig.hasModRuntime.',
        );
    }
  }

  Future<String> _resolveFabric(String tag) async {
    final body = await _fetchJson(_fabricMetaUrl, 'meta.fabricmc.net');
    if (body is! List || body.isEmpty) {
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
      if (tag != 'stable' && tag != 'latest' && version == tag) return tag;
    }
    if (tag == 'stable' || tag == 'latest') {
      throw UserError(
        'no Fabric loader version matched tag `$tag` '
        '(received ${body.length} entries).',
      );
    }
    throw UserError(
      'Fabric loader version `fabric:$tag` is not a published version '
      '(see https://meta.fabricmc.net/v2/versions/loader for the list, '
      'or use `fabric:stable` / `fabric:latest`).',
    );
  }

  Future<String> _resolveForge(String tag, String mcVersion) async {
    if (tag == 'stable' || tag == 'latest') {
      final body = await _fetchJson(
        _forgePromotionsUrl,
        'files.minecraftforge.net',
      );
      if (body is! Map || body['promos'] is! Map) {
        throw const UserError(
          'Forge promotions response from files.minecraftforge.net was empty '
          'or malformed.',
        );
      }
      final promos = (body['promos'] as Map).cast<String, dynamic>();
      final recommended = promos['$mcVersion-recommended'];
      final latest = promos['$mcVersion-latest'];
      if (latest is! String) {
        throw UserError(
          'no Forge build for Minecraft $mcVersion in upstream promotions; '
          'specify a concrete build (see '
          'https://files.minecraftforge.net/net/minecraftforge/forge/).',
        );
      }
      if (tag == 'latest') return latest;
      if (recommended is String) return recommended;
      throw UserError(
        'no stable Forge build for Minecraft $mcVersion (upstream lists no '
        '`-recommended` promotion); use `forge:latest` or specify a '
        'concrete build (see '
        'https://files.minecraftforge.net/net/minecraftforge/forge/).',
      );
    }

    // Concrete: validate against maven-metadata.json which lists every build
    // (promotions only carries the curated `-recommended`/`-latest` entries).
    final body = await _fetchJson(
      _forgeVersionsUrl,
      'files.minecraftforge.net',
    );
    if (body is! Map) {
      throw const UserError(
        'Forge versions response from files.minecraftforge.net was empty '
        'or malformed.',
      );
    }
    final builds = body[mcVersion];
    final fullVersion = '$mcVersion-$tag';
    if (builds is List && builds.contains(fullVersion)) {
      return tag;
    }
    throw UserError(
      'Forge build `forge:$tag` is not a published version for Minecraft '
      '$mcVersion (see '
      'https://files.minecraftforge.net/net/minecraftforge/forge/ for the '
      'list, or use `forge:stable` / `forge:latest`).',
    );
  }

  Future<String> _resolveNeoforge(String tag, String mcVersion) async {
    final parsed = _parseMcMinorPatch(mcVersion, ModLoader.neoforge, tag);
    final prefix = '${parsed.minor}.${parsed.patch}.';
    final body = await _fetchJson(_neoforgeVersionsUrl, 'maven.neoforged.net');
    final versions = _neoforgeVersionList(body);
    final isConcrete = tag != 'stable' && tag != 'latest';

    if (isConcrete) {
      if (!tag.startsWith(prefix)) {
        throw UserError(
          'NeoForge build `neoforge:$tag` is not published for Minecraft '
          '$mcVersion (expected version prefix `$prefix`; see '
          'https://maven.neoforged.net for available builds, or use '
          '`neoforge:stable` / `neoforge:latest`).',
        );
      }
      if (!versions.contains(tag)) {
        throw UserError(
          'NeoForge build `neoforge:$tag` is not published for Minecraft '
          '$mcVersion (expected version prefix `$prefix`; see '
          'https://maven.neoforged.net for available builds, or use '
          '`neoforge:stable` / `neoforge:latest`).',
        );
      }
      return tag;
    }

    // Newest-first scan (upstream returns ascending order).
    String? sawAnyMatching;
    for (var i = versions.length - 1; i >= 0; i--) {
      final v = versions[i];
      if (!v.startsWith(prefix)) continue;
      sawAnyMatching = sawAnyMatching ?? v;
      if (tag == 'latest') return v;
      if (!v.contains('-beta')) return v;
    }
    if (sawAnyMatching == null) {
      throw UserError(
        'no NeoForge build for Minecraft $mcVersion in upstream maven '
        'listing; specify a concrete build (see '
        'https://maven.neoforged.net).',
      );
    }
    // tag == 'stable', only -beta matched
    throw UserError(
      'no stable NeoForge build for Minecraft $mcVersion (only `-beta` '
      'versions available upstream); use `neoforge:latest` or specify a '
      'concrete build (see https://maven.neoforged.net).',
    );
  }

  Future<String> _resolveNeoforgeLegacy(String tag) async {
    const mcVersion = '1.20.1';
    const versionPrefix = '$mcVersion-';
    final body = await _fetchJson(
      _neoforgeLegacyVersionsUrl,
      'maven.neoforged.net',
    );
    final versions = _neoforgeVersionList(body);
    final isConcrete = tag != 'stable' && tag != 'latest';

    if (isConcrete) {
      final fullVersion = '$versionPrefix$tag';
      if (versions.contains(fullVersion)) {
        return tag;
      }
      throw UserError(
        'NeoForge build `neoforge:$tag` is not published for Minecraft '
        '$mcVersion (expected version prefix `$versionPrefix`; see '
        'https://maven.neoforged.net for available builds, or use '
        '`neoforge:stable` / `neoforge:latest`).',
      );
    }

    String? sawAnyMatching;
    for (var i = versions.length - 1; i >= 0; i--) {
      final v = versions[i];
      if (!v.startsWith(versionPrefix)) continue;
      sawAnyMatching = sawAnyMatching ?? v;
      final stripped = _stripLegacyPrefix(v, versionPrefix);
      if (tag == 'latest') return stripped;
      if (!v.contains('-beta')) return stripped;
    }
    if (sawAnyMatching == null) {
      throw UserError(
        'no NeoForge build for Minecraft $mcVersion in upstream maven '
        'listing; specify a concrete build (see '
        'https://maven.neoforged.net).',
      );
    }
    throw UserError(
      'no stable NeoForge build for Minecraft $mcVersion (only `-beta` '
      'versions available upstream); use `neoforge:latest` or specify a '
      'concrete build (see https://maven.neoforged.net).',
    );
  }

  String _stripLegacyPrefix(String version, String prefix) {
    if (!version.startsWith(prefix)) {
      throw UserError(
        'unexpected NeoForge legacy version format from maven.neoforged.net: '
        '"$version" (expected "$prefix<build>").',
      );
    }
    return version.substring(prefix.length);
  }

  /// Extracts `(minor, patch)` from MC `1.A.B` or `1.A`. `1.A` returns
  /// `(A, 0)` so the NeoForge prefix derivation is uniform. Only accepts
  /// the legacy `1.A[.B]` shape — Forge's prefix scheme is built on
  /// `1.<minor>` and the `26.x` year-based scheme would need a different
  /// derivation path.
  ({int minor, int patch}) _parseMcMinorPatch(
    String mc,
    ModLoader loader,
    String tag,
  ) {
    final Version v;
    try {
      v = parseMcVersion(mc);
    } on FormatException {
      throw UserError(
        'mc-version "$mc" is not a valid Minecraft release version '
        '(expected `1.A` or `1.A.B`); cannot resolve `${loader.name}:$tag`.',
      );
    }
    if (v.major != 1) {
      throw UserError(
        'mc-version "$mc" is not a valid Minecraft release version '
        '(expected `1.A` or `1.A.B`); cannot resolve `${loader.name}:$tag`.',
      );
    }
    return (minor: v.minor, patch: v.patch);
  }

  List<String> _neoforgeVersionList(dynamic body) {
    if (body is! Map || body['versions'] is! List) {
      throw const UserError(
        'NeoForge versions response from maven.neoforged.net was empty or '
        'malformed.',
      );
    }
    final list = (body['versions'] as List).whereType<String>().toList();
    if (list.isEmpty) {
      throw const UserError(
        'NeoForge versions response from maven.neoforged.net was empty or '
        'malformed.',
      );
    }
    return list;
  }

  Future<dynamic> _fetchJson(String url, String upstreamLabel) async {
    try {
      final resp = await _dio.get<dynamic>(url);
      return resp.data;
    } on DioException catch (e) {
      final err = e.error;
      if (err is GitrinthException) throw err;
      throw UserError(
        'failed to fetch loader versions from $upstreamLabel: '
        '${e.message ?? e.toString()}',
      );
    }
  }
}
