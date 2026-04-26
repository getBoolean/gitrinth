import 'package:dio/dio.dart';

import '../cli/exceptions.dart';

class OfflineGuardInterceptor extends Interceptor {
  final bool Function() isOffline;

  OfflineGuardInterceptor(this.isOffline);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!isOffline()) {
      handler.next(options);
      return;
    }
    final wrapped = UserError(
      'cannot reach ${options.uri} while offline. '
      'Try again without --offline.',
    );
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: wrapped,
        message: wrapped.message,
      ),
    );
  }
}
