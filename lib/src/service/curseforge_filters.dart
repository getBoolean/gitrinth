import '../model/curseforge/cf_constants.dart';
import '../model/curseforge/cf_mod.dart';
import '../model/curseforge/cf_mod_file.dart';
import '../model/manifest/mods_yaml.dart';
import 'curseforge_api.dart';

/// Maximum [CurseForgeApi.listFiles] page size. CurseForge caps page
/// size at 50 for the files endpoint.
const int _filesPageSize = 50;

/// Lists files for [projectId] that are compatible with the requested
/// pack context, sorted newest-first.
///
/// `gameVersions` is the union of the pack's `mc_version` and the
/// entry's `accepts_mc` — CurseForge's `gameVersion` query parameter is
/// single-string only, so a file is kept when its `gameVersions` array
/// intersects the requested set client-side. The channel floor maps to
/// the set returned by [cfReleaseTypesFor].
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

  final all = <ModFile>[];
  var index = 0;
  while (true) {
    final page = await api.listFiles(
      projectId,
      modLoaderType: modLoaderType,
      index: index,
      pageSize: _filesPageSize,
    );
    all.addAll(page.data);
    if (page.data.isEmpty) break;
    index += page.data.length;
    if (index >= page.pagination.totalCount) break;
  }

  final wanted = gameVersions.toSet();
  return all
      .where((f) => f.gameVersions.any(wanted.contains))
      .where((f) => allowedReleaseTypes.contains(f.releaseType))
      .toList()
    ..sort((a, b) => b.fileDate.compareTo(a.fileDate));
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
