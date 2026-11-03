import '../../cli/exceptions.dart';
import '../../model/curseforge/cf_constants.dart';
import '../../model/curseforge/cf_mod.dart';
import '../../model/curseforge/cf_mod_file.dart';
import '../../model/manifest/mods_yaml.dart';
import 'curseforge_api.dart';

/// Maximum [CurseForgeApi.listFiles] page size. CurseForge caps page
/// size at 50 for the files endpoint.
const int _filesPageSize = 50;
const int _filesWindow = 10000;

/// Lists files for [projectId] that are compatible with the requested
/// pack context, sorted newest-first.
///
/// `gameVersions` is the union of the pack's `mc_version` and the
/// entry's `accepts_mc` — CurseForge's `gameVersion` query parameter is
/// single-string only, so each distinct version gets a filtered query.
/// Files returned by multiple queries are deduplicated before sorting.
/// The channel floor maps to the set returned by [cfReleaseTypesFor].
///
/// Plugin sections require [pluginLoader] and the pluginLoader must
/// satisfy [pluginLoaderEligibleForCurseforge] — Folia/Sponge throw
/// [ArgumentError] before any HTTP request to mirror the source
/// eligibility matrix.
Future<List<ModFile>> listCompatibleFiles({
  required CurseForgeApi api,
  required int projectId,
  required Section section,
  ModLoader? modLoader,
  PluginLoader? pluginLoader,
  required List<String> gameVersions,
  required Channel channel,
}) async {
  if (section == Section.plugins) {
    if (pluginLoader == null ||
        !pluginLoaderEligibleForCurseforge(pluginLoader)) {
      throw ArgumentError(
        'CurseForge does not support plugin loader $pluginLoader',
      );
    }
  }

  final allowedReleaseTypes = cfReleaseTypesFor(channel);
  // Plugin sections don't filter by mod loader on the wire — CF's
  // plugin universe is Bukkit/Spigot/Paper-shape regardless of the
  // pack's `loader.mods`.
  final modLoaderType = section == Section.plugins
      ? null
      : modLoader?.cfModLoaderType;

  final all = <int, ModFile>{};
  final wanted = gameVersions.toSet();
  for (final gameVersion in wanted) {
    var index = 0;
    while (true) {
      final remaining = _filesWindow - index;
      final page = await api.listFiles(
        projectId,
        gameVersion: gameVersion,
        modLoaderType: modLoaderType,
        index: index,
        pageSize: remaining < _filesPageSize ? remaining : _filesPageSize,
      );
      if (page.pagination.totalCount > _filesWindow) {
        throw ValidationError(
          'CurseForge project $projectId has more than 10,000 files for '
          'Minecraft $gameVersion. This filtered history exceeds the supported '
          'API window; resolution cannot use an incomplete candidate list.',
        );
      }
      for (final file in page.data) {
        all.putIfAbsent(file.id, () => file);
      }
      index += page.data.length;
      if (index >= page.pagination.totalCount) break;
      if (page.data.isEmpty || index >= _filesWindow) {
        throw ValidationError(
          'CurseForge returned an incomplete file history for project '
          '$projectId and Minecraft $gameVersion at index $index. '
          'Retry when the service can return the complete filtered history.',
        );
      }
    }
  }

  final compatible = all.values
      .where((f) => f.gameVersions.any(wanted.contains))
      .where((f) => allowedReleaseTypes.contains(f.releaseType))
      .toList();
  final available = compatible.where((f) => f.isAvailable).toList();
  if (compatible.isNotEmpty && available.isEmpty) {
    throw ValidationError(
      'All compatible CurseForge files for project $projectId are unavailable.',
    );
  }
  return available..sort((a, b) => b.fileDate.compareTo(a.fileDate));
}

/// Looks up a mod by exact-slug match within [section]. Returns null
/// when CurseForge has no project with that slug for the section's
/// classId.
Future<Mod?> findModBySlug(
  CurseForgeApi api, {
  required String slug,
  required Section section,
}) async {
  final response = await api.searchMods(
    gameId: kCurseForgeGameIdMinecraft,
    classId: section.cfClassId,
    slug: slug,
  );
  return response.data.isEmpty ? null : response.data.first;
}
