import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/offline_guard_interceptor.dart';
import 'package:test/test.dart';

void main() {
  group('OfflineGuardInterceptor', () {
    test('rejects with UserError when isOffline() returns true', () async {
      final dio = Dio()..interceptors.add(OfflineGuardInterceptor(() => true));

      try {
        await dio.get<dynamic>('https://api.modrinth.com/v2/tag/game_version');
        fail('expected DioException');
      } on DioException catch (e) {
        expect(e.error, isA<UserError>());
        final wrapped = e.error as UserError;
        expect(wrapped.message, contains('while offline'));
        expect(wrapped.message, contains('Try again without --offline'));
        expect(wrapped.message, contains('api.modrinth.com'));
      }
    });

    test('passes through when isOffline() returns false', () async {
      final dio = Dio()..interceptors.add(OfflineGuardInterceptor(() => false));

      // Unroutable host so the request fails with a real network error,
      // not the offline guard. A non-cancel DioExceptionType proves the
      // guard let it through.
      try {
        await dio.get<dynamic>(
          'http://127.0.0.1:1/never-routed',
          options: Options(receiveTimeout: const Duration(milliseconds: 200)),
        );
        fail('expected DioException');
      } on DioException catch (e) {
        expect(e.type, isNot(DioExceptionType.cancel));
      }
    });
  });
}
