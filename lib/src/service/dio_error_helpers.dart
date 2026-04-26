import 'package:dio/dio.dart';

import '../cli/exceptions.dart';

/// Returns a new [DioException] that carries [wrapped] as its `error` and
/// `message` while preserving the original request, response, type, and
/// stack trace. Use from `Interceptor.onError` / `onRequest` paths that
/// translate raw HTTP failures into typed [GitrinthException]s.
DioException wrapDioError(DioException source, GitrinthException wrapped) {
  return DioException(
    requestOptions: source.requestOptions,
    response: source.response,
    type: source.type,
    error: wrapped,
    stackTrace: source.stackTrace,
    message: wrapped.message,
  );
}

/// Standard catch-block for download paths: `GitrinthException` already
/// produced by an interceptor passes through; otherwise wrap as a
/// [UserError] with [context] as the leading description.
///
/// Throws and never returns.
Never unwrapOrThrow(DioException source, {required String context}) {
  final inner = source.error;
  if (inner is GitrinthException) throw inner;
  throw UserError('$context: ${source.message ?? source.toString()}');
}
