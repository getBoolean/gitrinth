import 'dart:io';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import '../util/url_template.dart';
import 'dio_error_helpers.dart';
import 'paper_api_client.dart';
import 'sponge_api_client.dart';

class PluginLoaderVersionResolver {
  final Dio _dio;
  final PaperApiClient _paperApi;
  final SpongeApiClient _spongeApi;
  final String _buildToolsBuildNumberUrlTemplate;
  final String _buildToolsJarUrlTemplate;

  PluginLoaderVersionResolver({
    required Dio dio,
    required PaperApiClient paperApi,
    required SpongeApiClient spongeApi,
    Map<String, String>? environment,
    String? buildToolsBuildNumberUrlTemplate,
    String? buildToolsJarUrlTemplate,
  }) : _dio = dio,
       _paperApi = paperApi,
       _spongeApi = spongeApi,
       _buildToolsBuildNumberUrlTemplate =
           buildToolsBuildNumberUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_BUILDTOOLS_BUILD_NUMBER_URL'] ??
           'https://hub.spigotmc.org/jenkins/job/BuildTools/'
               'lastSuccessfulBuild/buildNumber',
       _buildToolsJarUrlTemplate =
           buildToolsJarUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_BUILDTOOLS_BUILD_URL'] ??
           'https://hub.spigotmc.org/jenkins/job/BuildTools/{build}/'
               'artifact/target/BuildTools.jar';

  Future<String> resolve({
    required PluginLoader loader,
    required String tag,
    required String mcVersion,
  }) async {
    switch (loader) {
      case PluginLoader.paper:
      case PluginLoader.folia:
        return _resolvePaperLike(loader.name, tag, mcVersion);
      case PluginLoader.spongeforge:
      case PluginLoader.spongeneo:
      case PluginLoader.spongevanilla:
        return _resolveSponge(loader, tag, mcVersion);
      case PluginLoader.spigot:
      case PluginLoader.bukkit:
        return _resolveBuildTools(tag);
    }
  }

  Future<String> _resolvePaperLike(
    String project,
    String tag,
    String mcVersion,
  ) async {
    final build = switch (tag) {
      'stable' => await _paperApi.latestStableBuild(
        project: project,
        mc: mcVersion,
      ),
      'latest' => await _paperApi.latestBuild(project: project, mc: mcVersion),
      _ => await _paperApi.buildByNumber(
        project: project,
        mc: mcVersion,
        build: _parsePositiveInt(tag, 'loader.plugins $project concrete tag'),
      ),
    };
    return build.build.toString();
  }

  Future<String> _resolveSponge(
    PluginLoader loader,
    String tag,
    String mcVersion,
  ) async {
    final artifact = switch (loader) {
      PluginLoader.spongeforge => 'spongeforge',
      PluginLoader.spongeneo => 'spongeneo',
      PluginLoader.spongevanilla => 'spongevanilla',
      _ => throw StateError('_resolveSponge called for ${loader.name}'),
    };
    final build = switch (tag) {
      'stable' => await _spongeApi.latestRecommendedBuild(
        artifact: artifact,
        mc: mcVersion,
      ),
      'latest' => await _spongeApi.latestBuild(
        artifact: artifact,
        mc: mcVersion,
      ),
      _ => await _spongeApi.buildByVersion(
        artifact: artifact,
        version: tag,
        mc: mcVersion,
      ),
    };
    return build.version;
  }

  Future<String> _resolveBuildTools(String tag) async {
    if (tag == 'stable' || tag == 'latest') {
      final url = _buildToolsBuildNumberUrlTemplate;
      final Response<dynamic> response;
      try {
        response = await _dio.get<dynamic>(url);
      } on DioException catch (e) {
        unwrapOrThrow(e, context: 'failed to query BuildTools at $url');
      }
      final text = response.data.toString().trim();
      _parsePositiveInt(text, 'BuildTools latest successful build');
      return text;
    }

    final build = _parsePositiveInt(tag, 'BuildTools concrete tag').toString();
    final url = fillUrlTemplate(_buildToolsJarUrlTemplate, {'build': build});
    try {
      await _dio.head<dynamic>(url);
    } on DioException catch (e) {
      unwrapOrThrow(
        e,
        context: 'failed to validate BuildTools build $build at $url',
      );
    }
    return build;
  }
}

int _parsePositiveInt(String raw, String label) {
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed <= 0) {
    throw ValidationError('$label must be a positive integer, got "$raw".');
  }
  return parsed;
}
