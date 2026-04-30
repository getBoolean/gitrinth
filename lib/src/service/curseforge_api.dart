import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../model/curseforge/cf_search_response.dart';

part 'curseforge_api.g.dart';

/// Marker key on `RequestOptions.extra` that opts a request into
/// CurseForge auth. When `extra[kCurseForgeAuthRequired] == true`,
/// [CurseForgeAuthInterceptor] resolves and attaches the
/// `x-api-key` header. Every CurseForge endpoint requires auth, so all
/// retrofit methods set the marker — but the marker is exposed so a raw
/// `dio.get` caller can opt in too.
const String kCurseForgeAuthRequired = 'gitrinth.cf.auth';

@RestApi(parser: Parser.DartMappable)
abstract class CurseForgeApi {
  factory CurseForgeApi(Dio dio, {String baseUrl}) = _CurseForgeApi;

  /// Fetches a single mod by its numeric project ID.
  @GET('/v1/mods/{id}')
  @Extra({kCurseForgeAuthRequired: true})
  Future<ModEnvelope> getMod(@Path('id') int id);

  /// Searches for mods on [gameId] (Minecraft is 432). [classId] scopes
  /// the result to a content type (mods=6, plugins=5, etc. — see
  /// `cf_constants.dart`). [slug] does an exact slug match; pass
  /// [searchFilter] for a substring search instead.
  @GET('/v1/mods/search')
  @Extra({kCurseForgeAuthRequired: true})
  Future<ModSearchResponse> searchMods({
    @Query('gameId') required int gameId,
    @Query('classId') int? classId,
    @Query('slug') String? slug,
    @Query('searchFilter') String? searchFilter,
    @Query('index') int? index,
    @Query('pageSize') int? pageSize,
  });

  /// Lists the files attached to a mod project.
  ///
  /// CurseForge's `gameVersion` query parameter only accepts a single
  /// value — packs that declare `accepts_mc:` need to filter
  /// client-side, which `listCompatibleFiles` does on top of this raw
  /// call.
  @GET('/v1/mods/{modId}/files')
  @Extra({kCurseForgeAuthRequired: true})
  Future<ModFileSearchResponse> listFiles(
    @Path('modId') int modId, {
    @Query('gameVersion') String? gameVersion,
    @Query('modLoaderType') int? modLoaderType,
    @Query('index') int? index,
    @Query('pageSize') int? pageSize,
  });

  /// Fetches a specific file by its `(modId, fileId)` pair.
  @GET('/v1/mods/{modId}/files/{fileId}')
  @Extra({kCurseForgeAuthRequired: true})
  Future<ModFileEnvelope> getFile(
    @Path('modId') int modId,
    @Path('fileId') int fileId,
  );
}
