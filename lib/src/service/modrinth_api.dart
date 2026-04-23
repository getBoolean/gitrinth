import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../model/modrinth/project.dart';
import '../model/modrinth/version.dart';

part 'modrinth_api.g.dart';

@RestApi(parser: Parser.DartMappable)
abstract class ModrinthApi {
  factory ModrinthApi(Dio dio, {String baseUrl}) = _ModrinthApi;

  @GET('/project/{slug}')
  Future<Project> getProject(@Path('slug') String slug);

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
}

String encodeFilterArray(List<String> values) => jsonEncode(values);
