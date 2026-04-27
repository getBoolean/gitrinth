import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import '../util/url_template.dart';
import 'dio_error_helpers.dart';

/// Resolved metadata for a SpongeForge / SpongeNeo / SpongeVanilla
/// recommended build.
class SpongeBuild {
  final String version;
  final String filename;
  final Uri downloadUrl;

  const SpongeBuild({
    required this.version,
    required this.filename,
    required this.downloadUrl,
  });
}

/// Small typed wrapper over the SpongePowered downloads v2 REST API.
///
/// The real API requires two calls: first the artifact-level versions
/// list (filtered to recommended for the target MC), then a per-version
/// detail call to get the assets array. The list endpoint does not
/// inline assets.
class SpongeApiClient {
  final Dio _dio;
  final String _versionsUrlTemplate;
  final String _versionDetailUrlTemplate;

  SpongeApiClient({
    required Dio dio,
    Map<String, String>? environment,
    String? versionsUrlTemplate,
    String? versionDetailUrlTemplate,
  }) : _dio = dio,
       _versionsUrlTemplate =
           versionsUrlTemplate ??
           (environment ?? Platform.environment)['GITRINTH_SPONGE_API_URL'] ??
           'https://dl-api.spongepowered.org/v2/groups/org.spongepowered/'
               'artifacts/{artifact}/versions?recommended=true&'
               'tags=minecraft:{mc}',
       _versionDetailUrlTemplate =
           versionDetailUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_SPONGE_DETAIL_URL'] ??
           'https://dl-api.spongepowered.org/v2/groups/org.spongepowered/'
               'artifacts/{artifact}/versions/{version}';

  /// Returns the latest recommended build of [artifact] (`spongeforge`,
  /// `spongeneo`, or `spongevanilla`) for Minecraft [mc]. Throws
  /// [UserError] when none is available.
  Future<SpongeBuild> latestRecommendedBuild({
    required String artifact,
    required String mc,
  }) async {
    final listUrl = fillUrlTemplate(_versionsUrlTemplate, {
      'artifact': artifact,
      'mc': mc,
    });
    final listMap = await _getJsonMap(listUrl);
    final artifactsRaw = listMap['artifacts'];
    if (artifactsRaw is! Map || artifactsRaw.isEmpty) {
      throw UserError(
        'Sponge reported no recommended $artifact build for Minecraft $mc.',
      );
    }
    // Pick the lexicographically-highest version key. Sponge keys are
    // `<mc>-<loader>-<api>` (e.g. `1.21.1-52.1.5-12.0.3`) so descending
    // string sort surfaces the newest API version for that MC.
    final versionKeys = artifactsRaw.keys.whereType<String>().toList()..sort();
    final bestVersion = versionKeys.isEmpty ? null : versionKeys.last;
    if (bestVersion == null) {
      throw UserError(
        'Sponge API at $listUrl returned no usable artifact entries '
        'for $artifact.',
      );
    }

    final detailUrl = fillUrlTemplate(_versionDetailUrlTemplate, {
      'artifact': artifact,
      'version': bestVersion,
    });
    final detailMap = await _getJsonMap(detailUrl);
    final assets = detailMap['assets'];
    if (assets is! List || assets.isEmpty) {
      throw UserError(
        'Sponge $artifact $bestVersion has no downloadable assets.',
      );
    }
    String? filename;
    String? downloadUrl;
    for (final asset in assets) {
      if (asset is! Map) continue;
      // Primary jar uses an empty classifier and the `jar` extension.
      // Source/javadoc/accessors variants ship under non-empty
      // classifiers and are skipped.
      if (asset['extension'] != 'jar') continue;
      final classifier = asset['classifier'];
      if (classifier != null && classifier != '') continue;
      final candidateUrl = asset['downloadUrl'];
      if (candidateUrl is! String || candidateUrl.isEmpty) continue;
      downloadUrl = candidateUrl;
      final segs = Uri.parse(candidateUrl).pathSegments;
      filename = segs.isEmpty ? '$artifact-$bestVersion.jar' : segs.last;
      break;
    }
    if (downloadUrl == null || filename == null) {
      throw UserError(
        'Sponge $artifact $bestVersion lists no primary jar asset.',
      );
    }
    return SpongeBuild(
      version: bestVersion,
      filename: filename,
      downloadUrl: Uri.parse(downloadUrl),
    );
  }

  Future<Map<String, dynamic>> _getJsonMap(String url) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(url);
    } on DioException catch (e) {
      unwrapOrThrow(e, context: 'failed to query Sponge API at $url');
    }
    final decoded = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (decoded is! Map) {
      throw UserError('Sponge API at $url returned unexpected payload.');
    }
    return decoded.cast<String, dynamic>();
  }
}
