import '../../model/curseforge/cf_search_response.dart';
import '../curseforge/curseforge_api.dart';

/// A graph solve uses one metadata snapshot while selected dependency edges
/// change. Cache request futures only for that solve, including pagination.
class CurseForgeResolutionApi implements CurseForgeApi {
  final CurseForgeApi delegate;
  final _projects = <int, Future<ModEnvelope>>{};
  final _files = <(int, int), Future<ModFileEnvelope>>{};
  final _listings =
      <(int, String?, int?, int?, int?), Future<ModFileSearchResponse>>{};
  final _searches =
      <(int, int?, String?, String?, int?, int?), Future<ModSearchResponse>>{};

  CurseForgeResolutionApi(this.delegate);

  @override
  Future<ModEnvelope> getMod(int id) =>
      _projects.putIfAbsent(id, () => delegate.getMod(id));

  @override
  Future<ModFileEnvelope> getFile(int modId, int fileId) => _files.putIfAbsent((
    modId,
    fileId,
  ), () => delegate.getFile(modId, fileId));

  @override
  Future<ModFileSearchResponse> listFiles(
    int modId, {
    String? gameVersion,
    int? modLoaderType,
    int? index,
    int? pageSize,
  }) => _listings.putIfAbsent(
    (modId, gameVersion, modLoaderType, index, pageSize),
    () => delegate.listFiles(
      modId,
      gameVersion: gameVersion,
      modLoaderType: modLoaderType,
      index: index,
      pageSize: pageSize,
    ),
  );

  @override
  Future<ModSearchResponse> searchMods({
    required int gameId,
    int? classId,
    String? slug,
    String? searchFilter,
    int? index,
    int? pageSize,
  }) => _searches.putIfAbsent(
    (gameId, classId, slug, searchFilter, index, pageSize),
    () => delegate.searchMods(
      gameId: gameId,
      classId: classId,
      slug: slug,
      searchFilter: searchFilter,
      index: index,
      pageSize: pageSize,
    ),
  );
}
