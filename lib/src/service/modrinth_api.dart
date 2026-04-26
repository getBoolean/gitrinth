import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../model/modrinth/game_version.dart';
import '../model/modrinth/project.dart';
import '../model/modrinth/version.dart';
import 'modrinth_auth_interceptor.dart';

part 'modrinth_api.g.dart';

@RestApi(parser: Parser.DartMappable)
abstract class ModrinthApi {
  factory ModrinthApi(Dio dio, {String baseUrl}) = _ModrinthApi;

  @GET('/project/{slug}')
  Future<Project> getProject(@Path('slug') String slug);

  /// Modrinth's project-validity endpoint. Returns 200 with `{"id": ...}` if a
  /// project with the given slug already exists, or 404 if the slug is free.
  /// Despite the published docs page describing the route as HEAD, the actual
  /// labrinth source uses `#[get("/{id}/check")]`. The body is irrelevant —
  /// callers should inspect `HttpResponse.response.statusCode`.
  @GET('/project/{slug}/check')
  Future<HttpResponse<dynamic>> checkProjectValidity(
    @Path('slug') String slug,
  );

  /// Returns versions of [slug] filtered server-side by loader and game version.
  /// Modrinth's `loaders` and `game_versions` parameters are JSON-encoded
  /// arrays — pass them via the `loadersJson`/`gameVersionsJson` parameters
  /// (e.g. `'["neoforge"]'`, `'["1.21.1"]'`).
  @GET('/project/{slug}/version')
  Future<List<Version>> listVersions(
    @Path('slug') String slug, {
    @Query('loaders') String? loadersJson,
    @Query('game_versions') String? gameVersionsJson,
  });

  /// Lists every Minecraft version Modrinth knows about, newest first.
  /// Used at resolve time to validate `mc-version` in `mods.yaml` against
  /// upstream — once, when the mc-version differs from what `mods.lock`
  /// already records.
  @GET('/tag/game_version')
  Future<List<GameVersion>> getGameVersions();

  /// Returns the current user. 200 means the bearer token is valid;
  /// 401 means it isn't. Body is loosely typed — callers only need
  /// the `username` field for the post-login confirmation message.
  @GET('/user')
  @Extra({kModrinthAuthRequired: true})
  Future<HttpResponse<dynamic>> getCurrentUser();
}

String encodeFilterArray(List<String> values) => jsonEncode(values);
