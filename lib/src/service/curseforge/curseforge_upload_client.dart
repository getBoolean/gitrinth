import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../cli/exceptions.dart';
import 'curseforge_url.dart';

/// Upload credentials are never read from the resolver's download key.
/// Protocol: https://support.curseforge.com/support/solutions/articles/9000197321
class CurseForgeUploadClient {
  final Dio dio;
  final String baseUrl;
  CurseForgeUploadClient(
    this.dio, {
    this.baseUrl = defaultCurseForgeUploadBaseUrl,
  });

  Future<dynamic> upload({
    required int projectId,
    required String token,
    required File archive,
    required Map<String, dynamic> metadata,
  }) async {
    if (projectId <= 0) {
      throw const UsageError('CurseForge project ID must be positive.');
    }
    try {
      final response = await dio.post<dynamic>(
        '${baseUrl.replaceFirst(RegExp(r"/$"), "")}/api/projects/$projectId/upload-file',
        data: FormData.fromMap({
          'metadata': jsonEncode(metadata),
          'file': await MultipartFile.fromFile(
            archive.path,
            filename: p.basename(archive.path),
            contentType: DioMediaType('application', 'zip'),
          ),
        }),
        options: Options(
          headers: {'X-Api-Token': token},
          followRedirects: false,
          sendTimeout: dio.options.sendTimeout ?? const Duration(minutes: 5),
          receiveTimeout:
              dio.options.receiveTimeout ?? const Duration(minutes: 2),
        ),
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const AuthenticationError(
          'CurseForge rejected the publish token.',
        );
      }
      throw UserError(
        'CurseForge upload failed (HTTP ${e.response?.statusCode ?? "unavailable"}).',
      );
    }
  }
}
