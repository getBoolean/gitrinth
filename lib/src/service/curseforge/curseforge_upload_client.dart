import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../cli/exceptions.dart';
import 'curseforge_url.dart';

class CurseForgeUploadResult {
  final int fileId;
  const CurseForgeUploadResult(this.fileId);
}

class CurseForgeUploadFailure extends UserError {
  final bool unknownOutcome;
  const CurseForgeUploadFailure(super.message, {required this.unknownOutcome});
}

/// Upload credentials are never read from the resolver's download key.
/// Protocol: https://support.curseforge.com/support/solutions/articles/9000197321
class CurseForgeUploadClient {
  final Dio dio;
  final String baseUrl;
  CurseForgeUploadClient(
    this.dio, {
    this.baseUrl = defaultCurseForgeUploadBaseUrl,
  });

  Future<CurseForgeUploadResult> upload({
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
          validateStatus: (_) => true,
          sendTimeout: dio.options.sendTimeout ?? const Duration(minutes: 5),
          receiveTimeout:
              dio.options.receiveTimeout ?? const Duration(minutes: 2),
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw DioException.badResponse(
          statusCode: status,
          requestOptions: response.requestOptions,
          response: response,
        );
      }
      final data = response.data;
      final id = data is Map ? data['id'] : null;
      if (id is! int || id <= 0) {
        throw const CurseForgeUploadFailure(
          'CurseForge upload returned no positive file ID; the remote outcome is unknown. Inspect remote files before retrying.',
          unknownOutcome: true,
        );
      }
      return CurseForgeUploadResult(id);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const AuthenticationError(
          'CurseForge rejected the publish token.',
        );
      }
      final status = e.response?.statusCode;
      throw CurseForgeUploadFailure(
        'CurseForge upload failed (HTTP ${e.response?.statusCode ?? "unavailable"}).',
        unknownOutcome: status == null || status >= 500 || status == 408,
      );
    }
  }
}
