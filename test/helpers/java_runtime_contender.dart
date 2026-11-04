import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/java_runtime_fetcher.dart';
import 'package:gitrinth/src/util/host_platform.dart';

Future<void> main(List<String> args) async {
  debugHostPlatformOverride = const HostPlatform(os: 'windows', arch: 'x64');
  final cache = GitrinthCache(root: args.single);
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        handler.reject(
          DioException(
            requestOptions: request,
            error: StateError(
              'A locked contender must not access the network.',
            ),
          ),
        );
      },
    ),
  );
  try {
    await JavaRuntimeFetcher(
      cache: cache,
      downloader: Downloader(dio: dio, cache: cache),
    ).ensureRuntime(21);
    throw StateError('The incomplete runtime is owned by another process.');
  } on FileSystemException catch (error) {
    stdout.writeln(
      jsonEncode({'status': 'lock-refused', 'message': error.message}),
    );
  } finally {
    dio.close(force: true);
  }
}
