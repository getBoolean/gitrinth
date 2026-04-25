import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/java_runtime_fetcher.dart';
import 'package:gitrinth/src/service/offline_guard_interceptor.dart';
import 'package:gitrinth/src/util/host_platform.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fake_modrinth.dart';

/// Builds a tiny ZIP that mimics an Adoptium JDK layout with
/// `<top>/bin/<binary>` so the fetcher's binary discovery has something
/// to find.
Uint8List buildFakeJdkZip({
  required String top,
  required String binaryName,
  String binaryContents = 'FAKE-JAVA',
}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        '$top/bin/$binaryName',
        binaryContents.length,
        binaryContents.codeUnits,
      ),
    )
    ..addFile(
      ArchiveFile('$top/release', 0, const <int>[]),
    );
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

/// Same idea as [buildFakeJdkZip] but for macOS layout: the binary lives
/// under `<top>/Contents/Home/bin/java`.
Uint8List buildFakeMacJdkTarGz({
  required String top,
  String binaryContents = 'FAKE-JAVA-MAC',
}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        '$top/Contents/Home/bin/java',
        binaryContents.length,
        binaryContents.codeUnits,
      ),
    );
  final tar = TarEncoder().encode(archive);
  final gz = GZipEncoder().encode(tar);
  return Uint8List.fromList(gz);
}

void main() {
  group('JavaRuntimeFetcher', () {
    group('requiredFeatureFor', () {
      final cases = <String, int>{
        '1.16.5': 8,
        '1.17': 16,
        '1.17.1': 16,
        '1.18': 17,
        '1.18.2': 17,
        '1.20.4': 17,
        '1.20.5': 21,
        '1.21': 21,
        '1.21.1': 21,
        '1.21.5': 21,
        '26.0': 21,
        '26.0.1': 21,
        '26.1': 25,
        '26.5': 25,
        '27.0': 25,
      };
      for (final entry in cases.entries) {
        test('${entry.key} -> JDK ${entry.value}', () {
          expect(
            JavaRuntimeFetcher.requiredFeatureFor(entry.key),
            entry.value,
          );
        });
      }

      test('malformed input defaults to highest known (25)', () {
        expect(
          JavaRuntimeFetcher.requiredFeatureFor('not-a-version'),
          25,
        );
      });
    });

    group('ensureRuntime', () {
      late FakeModrinth fake;
      late Directory tempCacheRoot;
      late GitrinthCache cache;
      late Dio dio;
      late Downloader downloader;
      bool offline = false;

      setUp(() async {
        fake = FakeModrinth();
        await fake.start();
        tempCacheRoot = Directory.systemTemp.createTempSync('gitrinth_jrf_');
        cache = GitrinthCache(root: tempCacheRoot.path);
        cache.ensureRoot();
        offline = false;
        dio = Dio()..interceptors.add(OfflineGuardInterceptor(() => offline));
        downloader = Downloader(dio: dio, cache: cache);
        // Default test platform: Windows x64. Tests that need a different
        // platform set debugHostPlatformOverride at the top of the test.
        debugHostPlatformOverride = const HostPlatform(
          os: 'windows',
          arch: 'x64',
        );
      });

      tearDown(() async {
        debugHostPlatformOverride = null;
        dio.close(force: true);
        await fake.stop();
        if (tempCacheRoot.existsSync()) {
          tempCacheRoot.deleteSync(recursive: true);
        }
      });

      void registerFeature({
        required int feature,
        required String os,
        required String arch,
        required String fullVersion,
        required Uint8List bytes,
        String? linkOverride,
      }) {
        final key = '$feature-$os-$arch';
        final binaryKey = '$feature-$os-$arch'
            '${os == 'windows' ? '.zip' : '.tar.gz'}';
        fake.adoptiumBinaryBytes[binaryKey] = bytes;
        final link = linkOverride ?? '${fake.adoptiumBinaryUrlPrefix}$binaryKey';
        fake.adoptiumMetadata[key] = [
          {
            'release_name': 'jdk-$fullVersion',
            'version_data': {
              'semver': fullVersion,
              'openjdk_version': fullVersion,
            },
            'binaries': [
              {
                'os': os,
                'architecture': arch,
                'image_type': 'jdk',
                'package': {
                  'link': link,
                  'checksum': sha256.convert(bytes).toString(),
                  'name': 'OpenJDK${feature}U-jdk_${arch}_$os.zip',
                  'size': bytes.length,
                },
              },
            ],
          },
        ];
      }

      test(
        'happy path: empty cache -> downloads, extracts, caches, returns '
        'bin/java',
        () async {
          final zipBytes = buildFakeJdkZip(
            top: 'jdk-21.0.5+11',
            binaryName: 'java.exe',
          );
          registerFeature(
            feature: 21,
            os: 'windows',
            arch: 'x64',
            fullVersion: '21.0.5+11',
            bytes: zipBytes,
          );
          final fetcher = JavaRuntimeFetcher(
            cache: cache,
            downloader: downloader,
            metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,


          );

          final java = await fetcher.ensureRuntime(21);

          final expectedDir = p.join(
            tempCacheRoot.path,
            'runtimes',
            'temurin',
            '21',
            'windows-x64',
          );
          expect(java.existsSync(), isTrue);
          expect(p.isWithin(expectedDir, java.path), isTrue);
          expect(java.path, endsWith('java.exe'));
          final marker = File(
            p.join(expectedDir, '.gitrinth-installed-temurin-21.0.5+11'),
          );
          expect(marker.existsSync(), isTrue);
        },
      );

      test('idempotence: second call performs zero HTTP', () async {
        final zipBytes = buildFakeJdkZip(
          top: 'jdk-21-fake',
          binaryName: 'java.exe',
        );
        registerFeature(
          feature: 21,
          os: 'windows',
          arch: 'x64',
          fullVersion: '21.0.0+1',
          bytes: zipBytes,
        );
        final fetcher = JavaRuntimeFetcher(
          cache: cache,
          downloader: downloader,
          metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,


        );

        final first = await fetcher.ensureRuntime(21);
        final metadataKey = '/adoptium/v3/assets/feature_releases/21/ga';
        final binaryKey = '/adoptium-binary/21-windows-x64.zip';
        final hitsAfterFirst =
            (fake.requestCounts[metadataKey] ?? 0) +
            (fake.requestCounts[binaryKey] ?? 0);
        expect(hitsAfterFirst, greaterThan(0));

        final second = await fetcher.ensureRuntime(21);
        final hitsAfterSecond =
            (fake.requestCounts[metadataKey] ?? 0) +
            (fake.requestCounts[binaryKey] ?? 0);
        expect(hitsAfterSecond, hitsAfterFirst,
            reason: 'second call must be cache-only, no new HTTP');
        expect(first.path, second.path);
      });

      test(
        'sentinel-without-binary recovery: re-downloads cleanly',
        () async {
          // Pre-write a sentinel into the target dir without a java binary.
          final dir = Directory(
            p.join(
              tempCacheRoot.path,
              'runtimes',
              'temurin',
              '21',
              'windows-x64',
            ),
          )..createSync(recursive: true);
          File(p.join(dir.path, '.gitrinth-installed-temurin-21.0.0+1'))
              .writeAsStringSync('{}');

          final zipBytes = buildFakeJdkZip(
            top: 'jdk-21-fresh',
            binaryName: 'java.exe',
          );
          registerFeature(
            feature: 21,
            os: 'windows',
            arch: 'x64',
            fullVersion: '21.0.5+11',
            bytes: zipBytes,
          );
          final fetcher = JavaRuntimeFetcher(
            cache: cache,
            downloader: downloader,
            metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,


          );

          final java = await fetcher.ensureRuntime(21);
          expect(java.existsSync(), isTrue);
          // The stale sentinel was removed and a new one matches the
          // fresh fullVersion suffix.
          expect(
            File(
              p.join(dir.path, '.gitrinth-installed-temurin-21.0.5+11'),
            ).existsSync(),
            isTrue,
          );
          expect(
            File(
              p.join(dir.path, '.gitrinth-installed-temurin-21.0.0+1'),
            ).existsSync(),
            isFalse,
          );
        },
      );

      test('macOS layout: locates Contents/Home/bin/java', () async {
        debugHostPlatformOverride = const HostPlatform(
          os: 'mac',
          arch: 'aarch64',
        );
        final tarBytes = buildFakeMacJdkTarGz(top: 'jdk-21.0.5+11');
        registerFeature(
          feature: 21,
          os: 'mac',
          arch: 'aarch64',
          fullVersion: '21.0.5+11',
          bytes: tarBytes,
        );
        final fetcher = JavaRuntimeFetcher(
          cache: cache,
          downloader: downloader,
          metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,
        );

        final java = await fetcher.ensureRuntime(21);
        expect(java.existsSync(), isTrue);
        expect(java.path, contains('Contents'));
        expect(java.path, contains('Home'));
        expect(java.path, endsWith(p.join('bin', 'java')));
      });

      test('sha256 mismatch -> UserError, no sentinel written', () async {
        final realBytes = buildFakeJdkZip(
          top: 'jdk-21',
          binaryName: 'java.exe',
        );
        // Register metadata pointing at the real binary but with a
        // checksum for OTHER bytes.
        final binaryKey = '21-windows-x64.zip';
        fake.adoptiumBinaryBytes[binaryKey] = realBytes;
        fake.adoptiumMetadata['21-windows-x64'] = [
          {
            'release_name': 'jdk-21.0.0+1',
            'version_data': {'semver': '21.0.0+1'},
            'binaries': [
              {
                'package': {
                  'link': '${fake.adoptiumBinaryUrlPrefix}$binaryKey',
                  'checksum': sha256
                      .convert(Uint8List.fromList([1, 2, 3]))
                      .toString(),
                },
              },
            ],
          },
        ];
        final fetcher = JavaRuntimeFetcher(
          cache: cache,
          downloader: downloader,
          metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,


        );

        await expectLater(
          fetcher.ensureRuntime(21),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('checksum mismatch'),
            ),
          ),
        );
        final dir = Directory(
          p.join(tempCacheRoot.path, 'runtimes', 'temurin', '21'),
        );
        // Either dir doesn't exist (early failure) or it has no sentinel.
        if (dir.existsSync()) {
          for (final entity in dir.listSync(recursive: true)) {
            if (entity is File &&
                p
                    .basename(entity.path)
                    .startsWith('.gitrinth-installed-temurin-')) {
              fail('sentinel was written despite checksum failure');
            }
          }
        }
      });

      test('offline + nothing cached -> UserError from offline guard',
          () async {
        offline = true;
        final fetcher = JavaRuntimeFetcher(
          cache: cache,
          downloader: downloader,
          metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,


        );
        await expectLater(
          fetcher.ensureRuntime(21),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              contains('offline'),
            ),
          ),
        );
      });

      test('cachedRuntime returns null when nothing cached', () {
        final fetcher = JavaRuntimeFetcher(
          cache: cache,
          downloader: downloader,
          metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,


        );
        expect(fetcher.cachedRuntime(21), isNull);
      });

      test('cachedRuntime returns binary path after ensureRuntime', () async {
        final zipBytes = buildFakeJdkZip(
          top: 'jdk-21-fake',
          binaryName: 'java.exe',
        );
        registerFeature(
          feature: 21,
          os: 'windows',
          arch: 'x64',
          fullVersion: '21.0.0+1',
          bytes: zipBytes,
        );
        final fetcher = JavaRuntimeFetcher(
          cache: cache,
          downloader: downloader,
          metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,


        );
        await fetcher.ensureRuntime(21);
        final cached = fetcher.cachedRuntime(21);
        expect(cached, isNotNull);
        expect(cached!.existsSync(), isTrue);
      });
    });
  });
}
