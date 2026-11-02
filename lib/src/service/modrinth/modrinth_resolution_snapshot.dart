import 'package:retrofit/retrofit.dart';

import '../../model/modrinth/game_version.dart';
import '../../model/modrinth/project.dart';
import '../../model/modrinth/version.dart';
import 'modrinth_api.dart';
import 'modrinth_api_source.dart';
import 'modrinth_url.dart';

/// Public metadata shared by solver passes within a single resolution.
/// Construct a new snapshot for each preview or write; transport ownership
/// and authenticated requests remain with the underlying source.
final class ModrinthResolutionSnapshot implements ModrinthApiSource {
  final ModrinthApiSource _source;
  final _hosts = <String, ModrinthApi>{};

  ModrinthResolutionSnapshot(this._source);

  @override
  String get defaultBaseUrl => _source.defaultBaseUrl;

  @override
  ModrinthApi forHost(String? hostUrl) {
    final raw = hostUrl == null || hostUrl.trim().isEmpty
        ? defaultBaseUrl
        : hostUrl;
    final host = normalizeServerKey(raw);
    return _hosts.putIfAbsent(host, () => _SnapshotApi(_source.forHost(host)));
  }
}

final class _SnapshotApi implements ModrinthApi {
  final ModrinthApi _api;
  final _projects = <String, Future<Project>>{};
  final _members = <String, Future<HttpResponse<dynamic>>>{};
  final _versions = <(String, String?, String?), Future<List<Version>>>{};
  final _searches = <(String, String, int), Future<HttpResponse<dynamic>>>{};

  _SnapshotApi(this._api);

  @override
  Future<Project> getProject(String slug) => _projects.putIfAbsent(
    slug,
    () => _api
        .getProject(slug)
        .then(
          (project) => project.copyWith(
            loaders: List.unmodifiable(project.loaders),
            categories: List.unmodifiable(project.categories),
          ),
        ),
  );

  @override
  Future<HttpResponse<dynamic>> getProjectMembers(String slug) =>
      _members.putIfAbsent(
        slug,
        () => _api.getProjectMembers(slug).then(_immutableResponse),
      );

  @override
  Future<List<Version>> listVersions(
    String slug, {
    String? loadersJson,
    String? gameVersionsJson,
  }) => _versions.putIfAbsent(
    (slug, loadersJson, gameVersionsJson),
    () => _api
        .listVersions(
          slug,
          loadersJson: loadersJson,
          gameVersionsJson: gameVersionsJson,
        )
        .then((versions) => List<Version>.unmodifiable(versions)),
  );

  @override
  Future<HttpResponse<dynamic>> searchProjects({
    required String query,
    required String facets,
    int limit = 20,
  }) => _searches.putIfAbsent(
    (query, facets, limit),
    () => _api
        .searchProjects(query: query, facets: facets, limit: limit)
        .then(_immutableResponse),
  );

  @override
  Future<List<GameVersion>> getGameVersions() => _api.getGameVersions();

  @override
  Future<HttpResponse<dynamic>> checkProjectValidity(String slug) =>
      _api.checkProjectValidity(slug);

  @override
  Future<HttpResponse<dynamic>> getCurrentUser() => _api.getCurrentUser();
}

HttpResponse<dynamic> _immutableResponse(HttpResponse<dynamic> response) =>
    HttpResponse(_immutableJson(response.data), response.response);

dynamic _immutableJson(dynamic value) => switch (value) {
  List values => List<dynamic>.unmodifiable(values.map(_immutableJson)),
  Map values => Map<dynamic, dynamic>.unmodifiable(
    values.map((key, value) => MapEntry(key, _immutableJson(value))),
  ),
  _ => value,
};
