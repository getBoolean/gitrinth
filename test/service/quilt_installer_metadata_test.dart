import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/loader_binary_fetcher.dart';
import 'package:gitrinth/src/service/offline_guard_interceptor.dart';
import 'package:test/test.dart';

class _Adapter implements HttpClientAdapter {
  final Object metadata;
  final List<int> bytes;
  int calls = 0;
  _Adapter(this.metadata, this.bytes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (options.uri.host == 'meta.quiltmc.org') {
      return ResponseBody.fromString(
        jsonEncode(metadata),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory root;
  late GitrinthCache cache;
  late Dio dio;
  late LoaderBinaryFetcher fetcher;
  late String destination;
  final bytes = utf8.encode('quilt installer');
  const url =
      'https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/1.0.0/quilt-installer-1.0.0.jar';
  Map<String, Object> metadata() => {
    'version': '1.0.0',
    'url': url,
    'hashes': {'sha512': sha512.convert(bytes).toString()},
  };
  Future<File> fetch() => fetcher.fetchServerArtifact(
    loader: LoaderId.quilt,
    mcVersion: '1.21.1',
    modLoaderVersion: '0.30.2',
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('quilt_metadata_');
    cache = GitrinthCache(root: root.path);
    dio = Dio();
    fetcher = LoaderBinaryFetcher(
      cache: cache,
      downloader: Downloader(dio: dio, cache: cache),
      environment: {},
    );
    destination = cache.loaderArtifactPath(
      loader: LoaderId.quilt,
      mcVersion: '1.21.1',
      modLoaderVersion: '0.30.2',
      filename: 'quilt-installer.jar',
    );
  });
  tearDown(() {
    dio.close(force: true);
    root.deleteSync(recursive: true);
  });

  test('corrupt offline metadata makes no transport calls', () async {
    File('$destination.metadata.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{');
    final adapter = _Adapter([metadata()], bytes);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(OfflineGuardInterceptor(() => true));
    await expectLater(
      fetch(),
      throwsA(
        isA<UserError>().having(
          (e) => e.message,
          'message',
          contains('offline'),
        ),
      ),
    );
    expect(adapter.calls, 0);
    expect(File('$destination.metadata.json').readAsStringSync(), '{');
  });

  for (final invalid in ['url', 'missing hash', 'malformed hash']) {
    test(
      'rejects provider metadata with $invalid before artifact transport',
      () async {
        final value = metadata();
        if (invalid == 'url') {
          value['url'] = 'https://example.com/installer.jar';
        }
        if (invalid == 'missing hash') value.remove('hashes');
        if (invalid == 'malformed hash') value['hashes'] = {'sha512': 'bad'};
        final adapter = _Adapter([value], bytes);
        dio.httpClientAdapter = adapter;
        await expectLater(fetch(), throwsA(isA<ValidationError>()));
        expect(adapter.calls, 1);
        expect(File(destination).existsSync(), isFalse);
        expect(File('$destination.metadata.json').existsSync(), isFalse);
      },
    );
  }

  test('mismatching artifact never persists installer or metadata', () async {
    dio.httpClientAdapter = _Adapter([metadata()], utf8.encode('tampered'));
    await expectLater(fetch(), throwsA(isA<UserError>()));
    expect(File(destination).existsSync(), isFalse);
    expect(File('$destination.metadata.json').existsSync(), isFalse);
  });

  test('verified download persists reusable metadata and bytes', () async {
    final adapter = _Adapter([metadata()], bytes);
    dio.httpClientAdapter = adapter;
    expect((await fetch()).readAsBytesSync(), bytes);
    expect(adapter.calls, 2);
    expect(
      jsonDecode(File('$destination.metadata.json').readAsStringSync()),
      metadata(),
    );
  });
}
