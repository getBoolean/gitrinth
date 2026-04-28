import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import '../util/url_template.dart';
import 'dio_error_helpers.dart';

/// Resolved metadata for the latest Paper / Folia stable build.
class PaperBuild {
  final int build;
  final String filename;
  final Uri downloadUrl;

  const PaperBuild({
    required this.build,
    required this.filename,
    required this.downloadUrl,
  });
}

/// Small typed wrapper over the PaperMC v2 REST API. Mirrors the URL-
/// template + env-var override pattern used by [LoaderBinaryFetcher].
class PaperApiClient {
  final Dio _dio;
  final String _buildsUrlTemplate;
  final String _downloadUrlTemplate;

  PaperApiClient({
    required Dio dio,
    Map<String, String>? environment,
    String? buildsUrlTemplate,
    String? downloadUrlTemplate,
  }) : _dio = dio,
       _buildsUrlTemplate =
           buildsUrlTemplate ??
           (environment ?? Platform.environment)['GITRINTH_PAPER_API_URL'] ??
           'https://api.papermc.io/v2/projects/{project}/versions/{mc}/builds',
       _downloadUrlTemplate =
           downloadUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_PAPER_DOWNLOAD_URL'] ??
           'https://api.papermc.io/v2/projects/{project}/versions/{mc}/'
               'builds/{build}/downloads/{filename}';

  /// Returns the latest stable (`channel: "default"`) build of [project]
  /// for Minecraft [mc]. Throws [UserError] when no stable build exists.
  Future<PaperBuild> latestStableBuild({
    required String project,
    required String mc,
  }) async {
    final builds = await _listBuilds(project: project, mc: mc);
    // PaperMC's `channel` is uppercase (`STABLE` / `EXPERIMENTAL`). Match
    // case-insensitively to tolerate any future casing changes. Within
    // stable builds, pick the highest build number rather than relying on
    // API ordering.
    Map<String, dynamic>? latest;
    int latestBuild = -1;
    for (final raw in builds) {
      if (raw is! Map) continue;
      final channel = raw['channel'];
      if (channel is! String) continue;
      final normalized = channel.toLowerCase();
      if (normalized != 'stable' && normalized != 'default') continue;
      final build = raw['build'];
      if (build is! int) continue;
      if (build > latestBuild) {
        latestBuild = build;
        latest = raw.cast<String, dynamic>();
      }
    }
    if (latest == null) {
      throw UserError(
        'PaperMC reported no stable $project build for Minecraft $mc; '
        'only experimental channels were returned.',
      );
    }
    return _buildFromEntry(project: project, mc: mc, entry: latest);
  }

  /// Returns the highest numbered build for [project] and [mc], regardless
  /// of channel.
  Future<PaperBuild> latestBuild({
    required String project,
    required String mc,
  }) async {
    final builds = await _listBuilds(project: project, mc: mc);
    Map<String, dynamic>? latest;
    int latestBuild = -1;
    for (final raw in builds) {
      if (raw is! Map) continue;
      final build = raw['build'];
      if (build is! int) continue;
      if (build > latestBuild) {
        latestBuild = build;
        latest = raw.cast<String, dynamic>();
      }
    }
    if (latest == null) {
      throw UserError('PaperMC reported no usable $project builds for $mc.');
    }
    return _buildFromEntry(project: project, mc: mc, entry: latest);
  }

  /// Returns exactly [build] for [project] and [mc].
  Future<PaperBuild> buildByNumber({
    required String project,
    required String mc,
    required int build,
  }) async {
    final builds = await _listBuilds(project: project, mc: mc);
    for (final raw in builds) {
      if (raw is! Map) continue;
      if (raw['build'] == build) {
        return _buildFromEntry(
          project: project,
          mc: mc,
          entry: raw.cast<String, dynamic>(),
        );
      }
    }
    throw UserError(
      'PaperMC reported no $project build $build for Minecraft $mc.',
    );
  }

  Future<List<dynamic>> _listBuilds({
    required String project,
    required String mc,
  }) async {
    final url = fillUrlTemplate(_buildsUrlTemplate, {
      'project': project,
      'mc': mc,
    });
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(url);
    } on DioException catch (e) {
      unwrapOrThrow(e, context: 'failed to query PaperMC API at $url');
    }
    final decoded = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (decoded is! Map) {
      throw UserError('PaperMC API at $url returned unexpected payload.');
    }
    final data = decoded.cast<String, dynamic>();
    final builds = data['builds'];
    if (builds is! List || builds.isEmpty) {
      throw UserError('PaperMC reported no $project builds for Minecraft $mc.');
    }
    return builds;
  }

  PaperBuild _buildFromEntry({
    required String project,
    required String mc,
    required Map<String, dynamic> entry,
  }) {
    final build = entry['build'];
    final downloads = entry['downloads'];
    if (build is! int || downloads is! Map) {
      throw UserError(
        'PaperMC returned a malformed build entry for $project $mc.',
      );
    }
    final application = downloads['application'];
    if (application is! Map) {
      throw UserError(
        'PaperMC build $build for $project did not list an `application` '
        'download.',
      );
    }
    final filename = application['name'];
    if (filename is! String || filename.isEmpty) {
      throw UserError(
        'PaperMC build $build for $project did not name its application jar.',
      );
    }
    final downloadUrl = Uri.parse(
      fillUrlTemplate(_downloadUrlTemplate, {
        'project': project,
        'mc': mc,
        'build': build.toString(),
        'filename': filename,
      }),
    );
    return PaperBuild(
      build: build,
      filename: filename,
      downloadUrl: downloadUrl,
    );
  }
}
