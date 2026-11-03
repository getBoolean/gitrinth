import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import '../model/loader/loader_descriptor.dart';
import '../model/loader/loader_id.dart';
import 'loader_catalog_cache.dart';
import 'modrinth/modrinth_url.dart';

export '../model/loader/loader_descriptor.dart';
export '../model/loader/loader_id.dart';

/// Produces immutable snapshots; it never changes a process-wide registry.
class LoaderRegistryService {
  final LoaderRegistry configured;
  final LoaderCatalogCache cache;
  final Dio dio;
  const LoaderRegistryService({
    required this.configured,
    required this.cache,
    required this.dio,
  });

  Future<LoaderRegistry> snapshot({
    required String modrinthHost,
    required String curseforgeHost,
    required Iterable<LoaderId> needed,
    bool offline = false,
    bool refresh = false,
    bool discoverModrinth = true,
    Future<List<Map<String, dynamic>>> Function()? readCurseforge,
  }) async {
    final mrHost = normalizeServerKey(modrinthHost);
    final cfHost = normalizeServerKey(curseforgeHost);
    var registry = configured;
    void mergeCached(
      String provider,
      String host,
      LoaderRegistry Function(LoaderRegistry, List<Map<String, dynamic>>) merge,
    ) {
      try {
        final entries = cache.read(provider, host);
        if (entries != null) registry = merge(registry, entries);
      } on ValidationError {
        if (offline) rethrow;
      }
    }

    if (discoverModrinth) {
      mergeCached(
        'modrinth',
        mrHost,
        (current, entries) => mergeModrinth(current, mrHost, entries),
      );
    }
    if (readCurseforge != null) {
      mergeCached('curseforge', cfHost, mergeCurseforge);
    }
    final missing = needed
        .where(
          (id) =>
              registry[id] == null ||
              (discoverModrinth &&
                  registry[id]?.role != LoaderRole.vanilla &&
                  registry[id]?.modrinthTag(mrHost) == null),
        )
        .toList();
    if (offline) {
      if (missing.isNotEmpty) {
        throw ValidationError(
          'No offline loader capability snapshot for ${missing.join(', ')}. Run online once or supply loaders.yaml.',
        );
      }
      return registry;
    }
    if (!refresh && missing.isEmpty) return registry;
    if (discoverModrinth) {
      final response = await _request(
        () => dio.get<dynamic>('$mrHost/tag/loader'),
        mrHost,
      );
      if (response.data is! List) {
        throw const ValidationError(
          'Modrinth loader discovery returned no catalog.',
        );
      }
      final mr = (response.data as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      registry = mergeModrinth(registry, mrHost, mr);
      cache.write('modrinth', mrHost, mr);
    }
    if (readCurseforge != null) {
      final cf = await _request(readCurseforge, cfHost);
      registry = mergeCurseforge(registry, cf);
      cache.write('curseforge', cfHost, cf);
    }
    for (final id in needed) {
      if (registry[id] == null) {
        throw ValidationError(
          'Loader $id was not discovered by the selected providers; supply an explicit loaders.yaml mapping.',
        );
      }
    }
    return registry;
  }

  static Future<T> _request<T>(
    Future<T> Function() request,
    String host,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      final cause = e.error;
      if (cause is GitrinthException) throw cause;
      throw UserError(
        'Loader discovery failed for $host (HTTP ${e.response?.statusCode ?? "unavailable"}).',
      );
    }
  }

  static LoaderRegistry mergeModrinth(
    LoaderRegistry registry,
    String host,
    List<Map<String, dynamic>> entries,
  ) {
    final additions = <LoaderDescriptor>[];
    final projectTypes = <LoaderId, Set<String>>{};
    for (final entry in entries) {
      final rawName = entry['name'];
      final rawTypes = entry['supported_project_types'];
      if (rawName is! String ||
          rawTypes is! List ||
          rawTypes.any((value) => value is! String)) {
        throw ValidationError('Invalid loader catalog fields from $host.');
      }
      final LoaderId id;
      try {
        id = LoaderId(rawName);
      } on FormatException catch (e) {
        throw ValidationError(
          'Invalid loader catalog identity from $host: ${e.message}',
        );
      }
      (projectTypes[id] ??= {}).addAll(rawTypes.cast<String>());
    }
    for (final entry in projectTypes.entries) {
      final id = entry.key;
      final types = entry.value;
      final existing = registry[id];
      if (existing != null) {
        // Exact names are identities, never aliases for a different provider ID.
        final mapped = existing.modrinthTag(host);
        if (mapped != null && mapped != id.name) {
          throw ValidationError('Loader alias collision for $host/${id.name}.');
        }
        additions.add(existing.withProvider(host: host, tag: id.name));
        continue;
      }
      final role = types.contains('plugin')
          ? LoaderRole.plugin
          : types.contains('shader')
          ? LoaderRole.shader
          : types.contains('mod')
          ? LoaderRole.mod
          : null;
      if (role == null) continue;
      additions.add(
        LoaderDescriptor(
          id: id,
          role: role,
          modrinthTags: {host: id.name},
          versionSource: VersionSourceFamily.catalog,
        ),
      );
    }
    return registry.merge(additions);
  }

  static LoaderRegistry mergeCurseforge(
    LoaderRegistry registry,
    List<Map<String, dynamic>> entries,
  ) {
    final byType = <int, List<LoaderCatalogVersion>>{};
    for (final entry in entries) {
      final type = entry['type'];
      final name = entry['name'];
      if (type is! int || type <= 0 || name is! String) continue;
      (byType[type] ??= []).add(
        LoaderCatalogVersion(
          name: name,
          gameVersion: entry['gameVersion'] is String
              ? entry['gameVersion'] as String
              : null,
          latest: entry['latest'] == true,
          recommended: entry['recommended'] == true,
        ),
      );
    }
    final additions = <LoaderDescriptor>[];
    for (final entry in byType.entries) {
      final existing = registry.descriptors.values
          .where((d) => d.curseforgeType == entry.key)
          .firstOrNull;
      if (existing != null) {
        additions.add(
          existing.withProvider(
            versions: entry.value.map((v) => v.name).toList(),
            catalogVersions: entry.value,
          ),
        );
      } else {
        additions.add(
          LoaderDescriptor(
            id: LoaderId('curseforge-type-${entry.key}'),
            role: LoaderRole.mod,
            curseforgeType: entry.key,
            versions: entry.value.map((v) => v.name).toList(),
            catalogVersions: entry.value,
            versionSource: VersionSourceFamily.catalog,
          ),
        );
      }
    }
    return registry.merge(additions);
  }
}

/// Rejects hybrid combinations whose explicit compatibility excludes the mod runtime.
void validateLoaderCompatibility(
  LoaderRegistry registry,
  LoaderId mods,
  LoaderId? plugins,
) {
  final descriptor = registry[plugins];
  if (mods != LoaderId.vanilla &&
      descriptor != null &&
      descriptor.compatibleMods.isNotEmpty &&
      !descriptor.compatibleMods.contains(mods)) {
    throw ValidationError(
      'Plugin loader ${descriptor.id.name} does not support mod loader ${mods.name}; compatible mod loaders: ${descriptor.compatibleMods.join(', ')}.',
    );
  }
}
