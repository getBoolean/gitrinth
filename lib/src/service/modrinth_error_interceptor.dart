import 'dart:convert';

import 'package:dio/dio.dart';

import '../cli/exceptions.dart';

class ModrinthErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    final reqUri = err.requestOptions.uri;
    String? bodyMessage;
    if (response != null) {
      final data = response.data;
      if (data is Map && data['error'] is String) {
        bodyMessage = data['error'] as String;
      } else if (data is String && data.isNotEmpty) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map && decoded['error'] is String) {
            bodyMessage = decoded['error'] as String;
          }
        } catch (_) {
          // Not JSON; ignore.
        }
      }
    }
    final status = response?.statusCode;
    final summary = bodyMessage != null
        ? '$bodyMessage (HTTP ${status ?? '?'})'
        : 'HTTP ${status ?? '?'} ${response?.statusMessage ?? err.message ?? ''}'
            .trim();
    final wrapped = UserError('Modrinth request failed for $reqUri: $summary');
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: response,
        type: err.type,
        error: wrapped,
        stackTrace: err.stackTrace,
        message: wrapped.message,
      ),
    );
  }
}
