import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/downloader.dart';
import 'package:gitrinth/src/service/java_runtime_fetcher.dart';
import 'package:gitrinth/src/service/java_runtime_resolver.dart';
import 'package:gitrinth/src/service/offline_guard_interceptor.dart';
import 'package:gitrinth/src/util/host_platform.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fake_modrinth.dart';
import 'java_runtime_fetcher_test.dart' show buildFakeJdkZip;

/// Builds a [JavaProber] that returns canned major versions keyed by
/// the absolute path passed in. Returns null for any unrecognized path
/// (mimics the real prober when `java -version` fails or output is
/// unparseable).
JavaProber stubProber(Map<String, int?> table) {
  return (String path) async => table[path];
}

void main() {
  group('JavaRuntimeResolver', () {
    late Directory tempRoot;
    late Directory cacheRoot;
    late Directory pathDir;
    late File path21Java;
    late File path17Java;
    late GitrinthCache cache;
    late FakeModrinth fake;
    late Dio dio;
    late Downloader downloader;
    late JavaRuntimeFetcher fetcher;
    bool offline = false;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('gitrinth_jrr_');
      cacheRoot = Directory(p.join(tempRoot.path, 'cache'))..createSync();
      cache = GitrinthCache(root: cacheRoot.path);
      cache.ensureRoot();

      // Two stub `java` binaries representing different installed JDKs.
      // The prober map decides what version they "are."
      pathDir = Directory(p.join(tempRoot.path, 'fakebin'))..createSync();
      path21Java = File(p.join(pathDir.path, 'java21.exe'))
        ..writeAsStringSync('STUB');
      path17Java = File(p.join(pathDir.path, 'java17.exe'))
        ..writeAsStringSync('STUB');

      fake = FakeModrinth();
      await fake.start();
      offline = false;
      dio = Dio()..interceptors.add(OfflineGuardInterceptor(() => offline));
      downloader = Downloader(dio: dio, cache: cache);
      fetcher = JavaRuntimeFetcher(
        cache: cache,
        downloader: downloader,
        metadataUrlTemplate: fake.adoptiumMetadataUrlTemplate,
      );
      // Default test platform: Windows x64. Tests that need Linux or
      // macOS set debugHostPlatformOverride at the top of the test.
      debugHostPlatformOverride = const HostPlatform(
        os: 'windows',
        arch: 'x64',
      );
    });

    tearDown(() async {
      debugHostPlatformOverride = null;
      dio.close(force: true);
      await fake.stop();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('--java <jdk21 binary> on a JDK 21 modpack returns it', () async {
      final resolver = JavaRuntimeResolver(
        fetcher: fetcher,
        environment: const {},
        probe: stubProber({path21Java.path: 21}),

      );
      final result = await resolver.resolve(
        mcVersion: '1.21.1',
        explicitPath: path21Java.path,
      );
      expect(result.path, path21Java.path);
    });

    test(
      '--java <jdk17 binary> on a JDK 21 modpack -> hard-fail UserError',
      () async {
        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: const {},
          probe: stubProber({path17Java.path: 17}),

        );
        await expectLater(
          resolver.resolve(
            mcVersion: '1.21.1',
            explicitPath: path17Java.path,
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              allOf(contains('JDK 17'), contains('JDK >= 21')),
            ),
          ),
        );
      },
    );

    test('--java <jdk home dir> resolves to bin/java[.exe]', () async {
      final jdkHome = Directory(p.join(tempRoot.path, 'fakejdk21'))
        ..createSync();
      Directory(p.join(jdkHome.path, 'bin')).createSync();
      final binary = File(p.join(jdkHome.path, 'bin', 'java.exe'))
        ..writeAsStringSync('STUB');

      final resolver = JavaRuntimeResolver(
        fetcher: fetcher,
        environment: const {},
        probe: stubProber({binary.path: 21}),

      );
      final result = await resolver.resolve(
        mcVersion: '1.21.1',
        explicitPath: jdkHome.path,
      );
      expect(result.path, binary.path);
    });

    test('--java to nonexistent path -> UserError "no such file"',
        () async {
      final resolver = JavaRuntimeResolver(
        fetcher: fetcher,
        environment: const {},
        probe: stubProber(const {}),

      );
      await expectLater(
        resolver.resolve(
          mcVersion: '1.21.1',
          explicitPath: p.join(tempRoot.path, 'no-such-thing.exe'),
        ),
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            contains('no such file'),
          ),
        ),
      );
    });

    test(
      'JAVA_HOME pointing at JDK 21 is used when the modpack needs JDK 21',
      () async {
        final jdkHome = Directory(p.join(tempRoot.path, 'jh21'))..createSync();
        Directory(p.join(jdkHome.path, 'bin')).createSync();
        final binary = File(p.join(jdkHome.path, 'bin', 'java.exe'))
          ..writeAsStringSync('STUB');
        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: {'JAVA_HOME': jdkHome.path},
          probe: stubProber({binary.path: 21}),

        );
        final result = await resolver.resolve(mcVersion: '1.21.1');
        expect(result.path, binary.path);
      },
    );

    test(
      'JAVA_HOME mismatch with managed allowed: soft-falls through to '
      'auto-fetch (so a stale system JAVA_HOME does not block the user)',
      () async {
        final jdkHome = Directory(p.join(tempRoot.path, 'jh17a'))
          ..createSync();
        Directory(p.join(jdkHome.path, 'bin')).createSync();
        final binary = File(p.join(jdkHome.path, 'bin', 'java.exe'))
          ..writeAsStringSync('STUB');

        final zipBytes = buildFakeJdkZip(
          top: 'jdk-21-fake',
          binaryName: 'java.exe',
        );
        fake.adoptiumBinaryBytes['21-windows-x64.zip'] = zipBytes;
        fake.adoptiumMetadata['21-windows-x64'] = [
          {
            'release_name': 'jdk-21.0.5+11',
            'version_data': {'semver': '21.0.5+11'},
            'binaries': [
              {
                'package': {
                  'link': '${fake.adoptiumBinaryUrlPrefix}21-windows-x64.zip',
                  'checksum': sha256.convert(zipBytes).toString(),
                },
              },
            ],
          },
        ];

        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: {'JAVA_HOME': jdkHome.path},
          probe: stubProber({binary.path: 17}),
        );
        final result = await resolver.resolve(mcVersion: '1.21.1');
        expect(result.path, contains('runtimes'));
        expect(result.path, contains(p.join('temurin', '21')));
      },
    );

    test(
      'JAVA_HOME mismatch + --no-managed-java + nothing else satisfies -> '
      'UserError mentions JAVA_HOME and the version mismatch',
      () async {
        final jdkHome = Directory(p.join(tempRoot.path, 'jh17b'))
          ..createSync();
        Directory(p.join(jdkHome.path, 'bin')).createSync();
        final binary = File(p.join(jdkHome.path, 'bin', 'java.exe'))
          ..writeAsStringSync('STUB');
        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: {'JAVA_HOME': jdkHome.path, 'PATH': ''},
          probe: stubProber({binary.path: 17}),
        );
        await expectLater(
          resolver.resolve(mcVersion: '1.21.1', allowManaged: false),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('--no-managed-java'),
                contains('JAVA_HOME'),
                contains('JDK 17'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'cached gitrinth Temurin is used ahead of PATH when JAVA_HOME is unset',
      () async {
        // Pre-populate the cache via the real fetcher with a fake JDK.
        final zipBytes = buildFakeJdkZip(
          top: 'jdk-21-fake',
          binaryName: 'java.exe',
        );
        fake.adoptiumBinaryBytes['21-windows-x64.zip'] = zipBytes;
        fake.adoptiumMetadata['21-windows-x64'] = [
          {
            'release_name': 'jdk-21.0.5+11',
            'version_data': {'semver': '21.0.5+11'},
            'binaries': [
              {
                'package': {
                  'link': '${fake.adoptiumBinaryUrlPrefix}21-windows-x64.zip',
                  'checksum': sha256.convert(zipBytes).toString(),
                },
              },
            ],
          },
        ];
        await fetcher.ensureRuntime(21);

        var pathProbed = false;
        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: {'PATH': pathDir.path},
          probe: (path) async {
            pathProbed = true;
            return 17; // would mismatch if reached
          },

        );
        final result = await resolver.resolve(mcVersion: '1.21.1');
        expect(result.path, contains('runtimes'));
        expect(result.path, contains(p.join('temurin', '21')));
        expect(
          pathProbed,
          isFalse,
          reason: 'cached Temurin should preempt PATH probing',
        );
      },
    );

    test('PATH java is used when JAVA_HOME unset and version matches',
        () async {
      final resolver = JavaRuntimeResolver(
        fetcher: fetcher,
        environment: {'PATH': ''},
        probe: stubProber({path21Java.path: 21}),

      );
      // Stage a `java.exe` (not java21.exe) on the synthetic PATH.
      final pathDir2 = Directory(p.join(tempRoot.path, 'pathreal'))
        ..createSync();
      final realJava = File(p.join(pathDir2.path, 'java.exe'))
        ..writeAsStringSync('STUB');
      final r2 = JavaRuntimeResolver(
        fetcher: fetcher,
        environment: {'PATH': pathDir2.path},
        probe: stubProber({realJava.path: 21}),

      );
      final result = await r2.resolve(mcVersion: '1.21.1');
      expect(result.path, realJava.path);
      // Reference unused locals so analyzer is happy.
      expect(resolver, isNotNull);
    });

    test(
      'PATH java with wrong version + online -> falls through to fetcher',
      () async {
        final pathDir2 = Directory(p.join(tempRoot.path, 'path17'))
          ..createSync();
        final java17 = File(p.join(pathDir2.path, 'java.exe'))
          ..writeAsStringSync('STUB');

        final zipBytes = buildFakeJdkZip(
          top: 'jdk-21-fake',
          binaryName: 'java.exe',
        );
        fake.adoptiumBinaryBytes['21-windows-x64.zip'] = zipBytes;
        fake.adoptiumMetadata['21-windows-x64'] = [
          {
            'release_name': 'jdk-21.0.5+11',
            'version_data': {'semver': '21.0.5+11'},
            'binaries': [
              {
                'package': {
                  'link': '${fake.adoptiumBinaryUrlPrefix}21-windows-x64.zip',
                  'checksum': sha256.convert(zipBytes).toString(),
                },
              },
            ],
          },
        ];

        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: {'PATH': pathDir2.path},
          probe: stubProber({java17.path: 17}),

        );
        final result = await resolver.resolve(mcVersion: '1.21.1');
        expect(result.path, contains('runtimes'));
      },
    );

    test('--offline + nothing satisfies -> UserError mentions --offline',
        () async {
      offline = true;
      final pathDir2 = Directory(p.join(tempRoot.path, 'path17b'))..createSync();
      final java17 = File(p.join(pathDir2.path, 'java.exe'))
        ..writeAsStringSync('STUB');
      final resolver = JavaRuntimeResolver(
        fetcher: fetcher,
        environment: {'PATH': pathDir2.path},
        probe: stubProber({java17.path: 17}),

      );
      await expectLater(
        resolver.resolve(mcVersion: '1.21.1', offline: true),
        throwsA(
          isA<UserError>().having(
            (e) => e.message,
            'message',
            contains('--offline'),
          ),
        ),
      );
    });

    test(
      '--no-managed-java + nothing satisfies -> UserError mentions --java',
      () async {
        final pathDir2 = Directory(p.join(tempRoot.path, 'path17c'))
          ..createSync();
        final java17 = File(p.join(pathDir2.path, 'java.exe'))
          ..writeAsStringSync('STUB');
        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: {'PATH': pathDir2.path},
          probe: stubProber({java17.path: 17}),

        );
        await expectLater(
          resolver.resolve(
            mcVersion: '1.21.1',
            allowManaged: false,
          ),
          throwsA(
            isA<UserError>().having(
              (e) => e.message,
              'message',
              allOf(contains('--no-managed-java'), contains('--java')),
            ),
          ),
        );
      },
    );

    test(
      'POSIX (linux): PATH separator is `:` and binary name is `java`',
      () async {
        debugHostPlatformOverride = const HostPlatform(
          os: 'linux',
          arch: 'x64',
        );
        final dir1 = Directory(p.join(tempRoot.path, 'lin1'))..createSync();
        final dir2 = Directory(p.join(tempRoot.path, 'lin2'))..createSync();
        final java = File(p.join(dir2.path, 'java'))..writeAsStringSync('STUB');
        final resolver = JavaRuntimeResolver(
          fetcher: fetcher,
          environment: {'PATH': '${dir1.path}:${dir2.path}'},
          probe: stubProber({java.path: 21}),
        );
        final result = await resolver.resolve(mcVersion: '1.21.1');
        expect(result.path, java.path);
      },
      // Real temp paths on Windows contain `C:`, which collides with the
      // `:` PATH separator. On macOS, the resolver's macOS-bundle probe
      // would short-circuit before the linux split runs. Restrict to a
      // real Linux runner where the behavior is exercised naturally.
      testOn: 'linux',
    );

    test('probeMajorVersion result is cached per path', () async {
      var probes = 0;
      final resolver = JavaRuntimeResolver(
        fetcher: fetcher,
        environment: const {},
        probe: (path) async {
          probes++;
          return 21;
        },

      );
      await resolver.probeMajorVersion(path21Java.path);
      await resolver.probeMajorVersion(path21Java.path);
      await resolver.probeMajorVersion(path21Java.path);
      expect(probes, 1);
    });
  });
}
