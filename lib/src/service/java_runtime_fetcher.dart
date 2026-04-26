import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../util/host_platform.dart';
import '../util/mc_version.dart';
import 'cache.dart';
import 'console.dart';
import 'downloader.dart';

/// Fetches and caches an Eclipse Temurin JDK matching a feature version
/// (e.g. 21). The download source is the Adoptium API; the extracted JDK
/// lives under `<cache>/runtimes/temurin/<feature>/<os>-<arch>/`.
///
/// Idempotent: if the target dir already has a sentinel marker and a
/// resolvable `bin/java[.exe]`, the cached path is returned without
/// any HTTP. Concurrent gitrinth invocations serialize on a per-feature
/// file lock so two terminals racing don't double-extract.
class JavaRuntimeFetcher {
  static const String vendor = 'temurin';

  final GitrinthCache _cache;
  final Downloader _downloader;
  final Console _console;
  final Map<String, String> _environment;
  final String _metadataUrlTemplate;

  JavaRuntimeFetcher({
    required GitrinthCache cache,
    required Downloader downloader,
    Console? console,
    Map<String, String>? environment,
    String? metadataUrlTemplate,
  }) : _cache = cache,
       _downloader = downloader,
       _console = console ?? const Console(),
       _environment = environment ?? Platform.environment,
       _metadataUrlTemplate =
           metadataUrlTemplate ??
           (environment ??
               Platform.environment)['GITRINTH_JAVA_METADATA_URL'] ??
           'https://api.adoptium.net/v3/assets/feature_releases/'
               '{feature}/ga?architecture={arch}&heap_size=normal'
               '&image_type=jdk&jvm_impl=hotspot&os={os}'
               '&page=0&page_size=1&project=jdk'
               '&sort_method=DEFAULT&sort_order=DESC&vendor=eclipse';

  /// Returns the JDK feature version required by [mcVersion]. Defaults
  /// to 25 (highest known) on unparseable input, after a [Console.warn].
  ///
  /// Boundaries (sourced from Mojang's launcher_meta + MC release notes):
  /// `< 1.17`→8, `1.17`→16, `1.18`→17, `1.20.5`→21, `26.1`→25. MC 26.0
  /// is still on Java 21; the year-based versioning scheme means major
  /// engine bumps land in point releases.
  static int requiredFeatureFor(String mcVersion, {Console? console}) {
    try {
      final v = parseMcVersion(mcVersion);
      if (v < parseMcVersion('1.17')) return 8;
      if (v < parseMcVersion('1.18')) return 16;
      if (v < parseMcVersion('1.20.5')) return 17;
      if (v < parseMcVersion('26.1')) return 21;
      return 25;
    } on FormatException {
      console?.warn(
        'mc-version "$mcVersion" is not a valid Minecraft version; '
        'defaulting to JDK 25 (highest known).',
      );
      return 25;
    }
  }

  HostPlatform _platform() => detectHostPlatform(environment: _environment);

  /// Returns absolute path to a `java[.exe]` binary for [feature].
  /// Idempotent. Triggers a download + extraction on first use; cached
  /// thereafter.
  Future<File> ensureRuntime(int feature) async {
    final platform = _platform();
    final osKey = platform.os;
    final archKey = platform.arch;
    final dir = Directory(
      _cache.javaRuntimeDir(
        vendor: vendor,
        feature: feature,
        osKey: osKey,
        archKey: archKey,
      ),
    );

    // Half-state cleanup: dir exists but no sentinel inside (crashed
    // prior run). Don't trust the contents — start fresh.
    if (dir.existsSync() && !_hasSentinel(dir)) {
      dir.deleteSync(recursive: true);
    }

    if (dir.existsSync() && _hasSentinel(dir)) {
      final java = _findJavaBinary(dir, osKey);
      if (java != null) return java;
      // Sentinel without binary (truncated install) — start over.
      dir.deleteSync(recursive: true);
    }

    Directory(_cache.runtimesRoot).createSync(recursive: true);
    final lockFile = File(
      p.join(_cache.runtimesRoot, '.lock-temurin-$feature'),
    );
    final lockHandle = lockFile.openSync(mode: FileMode.write);
    lockHandle.lockSync(FileLock.exclusive);
    try {
      // Re-check after acquiring lock — another process may have just
      // finished installing the same feature.
      if (dir.existsSync() && _hasSentinel(dir)) {
        final cached = _findJavaBinary(dir, osKey);
        if (cached != null) return cached;
        dir.deleteSync(recursive: true);
      }

      _console.io(
        'Downloading Temurin $feature (~190 MB) to ${dir.path}; '
        'one-time per JDK feature version.',
      );

      final metaUrl = _metadataUrlTemplate
          .replaceAll('{feature}', feature.toString())
          .replaceAll('{os}', osKey)
          .replaceAll('{arch}', archKey);
      final meta = await _fetchMetadata(metaUrl);

      final ext = osKey == 'windows' ? '.zip' : '.tar.gz';
      _cache.ensureRoot();
      final tmpArchivePath = p.join(
        _cache.tmpRoot,
        'jdk-temurin-$feature-$osKey-$archKey-'
        '${DateTime.now().microsecondsSinceEpoch}$ext',
      );
      final File archiveFile;
      try {
        archiveFile = await _downloader.downloadTo(
          url: meta.url,
          destinationPath: tmpArchivePath,
        );
      } on GitrinthException {
        rethrow;
      } on DioException catch (e) {
        final inner = e.error;
        if (inner is GitrinthException) throw inner;
        throw UserError(
          'failed to download Temurin $feature from ${meta.url}: '
          '${e.message ?? e.toString()}',
        );
      }

      try {
        await GitrinthCache.verifyFileSha256(archiveFile, meta.sha256);
      } on UserError {
        try {
          archiveFile.deleteSync();
        } catch (_) {}
        rethrow;
      }

      final extractTmp = Directory(
        p.join(
          _cache.tmpRoot,
          'extract-temurin-$feature-$osKey-$archKey-'
          '${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);
      try {
        _extractArchive(archiveFile, extractTmp);
      } catch (e) {
        try {
          extractTmp.deleteSync(recursive: true);
        } catch (_) {}
        try {
          archiveFile.deleteSync();
        } catch (_) {}
        if (e is GitrinthException) rethrow;
        throw UserError('failed to extract Temurin archive: $e');
      }

      Directory(p.dirname(dir.path)).createSync(recursive: true);
      try {
        extractTmp.renameSync(dir.path);
      } on FileSystemException catch (e) {
        try {
          extractTmp.deleteSync(recursive: true);
        } catch (_) {}
        if (Platform.isWindows && e.osError?.errorCode == 5) {
          throw UserError(
            'a JDK at ${dir.path} is in use by another gitrinth process; '
            'close it and retry.',
          );
        }
        throw UserError('failed to install Temurin runtime: ${e.message}');
      }

      // Only chmod when the host can actually run `chmod` (i.e. POSIX).
      // Cross-OS extraction (e.g. Windows host extracting a mac archive
      // for testing) skips chmod since `chmod` isn't available; the
      // production code path always has matching osKey + host OS.
      if (osKey != 'windows' && !Platform.isWindows) {
        _chmodPosixBinaries(dir);
      }

      final java = _findJavaBinary(dir, osKey);
      if (java == null) {
        throw const UserError(
          'extracted Temurin archive but could not find bin/java inside; '
          'archive layout may have changed.',
        );
      }

      _writeSentinel(
        dir: dir,
        feature: feature,
        fullVersion: meta.fullVersion,
        osKey: osKey,
        archKey: archKey,
        sourceUrl: meta.url,
        sha256: meta.sha256,
      );

      try {
        archiveFile.deleteSync();
      } catch (_) {}

      _console.io('Installed Temurin ${meta.fullVersion} to ${dir.path}.');
      return java;
    } finally {
      try {
        lockHandle.unlockSync();
      } catch (_) {}
      lockHandle.closeSync();
    }
  }

  /// Returns the path to a cached JDK for [feature] without triggering
  /// a download. Returns null if the JDK isn't cached or is incomplete.
  /// Used by the resolver to short-circuit ahead of system-PATH probing.
  File? cachedRuntime(int feature) {
    final platform = _platform();
    final dir = Directory(
      _cache.javaRuntimeDir(
        vendor: vendor,
        feature: feature,
        osKey: platform.os,
        archKey: platform.arch,
      ),
    );
    if (!dir.existsSync() || !_hasSentinel(dir)) return null;
    return _findJavaBinary(dir, platform.os);
  }

  Future<_AdoptiumMetadata> _fetchMetadata(String url) async {
    try {
      final resp = await _downloader.dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = resp.data;
      final parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is! List || parsed.isEmpty) {
        throw UserError(
          'Adoptium metadata at $url returned an empty list; '
          'no Temurin build available for this os/arch?',
        );
      }
      final release = parsed.first;
      if (release is! Map) {
        throw UserError('Adoptium metadata at $url has unexpected shape.');
      }
      final binaries = release['binaries'];
      if (binaries is! List || binaries.isEmpty) {
        throw UserError('Adoptium release at $url has no binaries.');
      }
      final binary = binaries.first;
      final pkg = binary is Map ? binary['package'] : null;
      if (pkg is! Map) {
        throw UserError('Adoptium binary at $url has no package metadata.');
      }
      final link = pkg['link'];
      final checksum = pkg['checksum'];
      if (link is! String || checksum is! String) {
        throw UserError('Adoptium package at $url missing link or checksum.');
      }
      String fullVersion;
      final versionData = release['version_data'];
      if (versionData is Map) {
        final semver = versionData['semver'] ?? versionData['openjdk_version'];
        fullVersion = semver is String
            ? semver
            : (release['release_name'] as String? ?? 'unknown');
      } else {
        fullVersion = release['release_name'] as String? ?? 'unknown';
      }
      return _AdoptiumMetadata(
        url: link,
        sha256: checksum,
        fullVersion: fullVersion,
      );
    } on GitrinthException {
      rethrow;
    } on DioException catch (e) {
      final inner = e.error;
      if (inner is GitrinthException) throw inner;
      throw UserError(
        'failed to fetch Temurin metadata from $url: '
        '${e.message ?? e.toString()}',
      );
    } on FormatException catch (e) {
      throw UserError('Adoptium metadata at $url was not valid JSON: $e');
    }
  }

  void _extractArchive(File archive, Directory outputDir) {
    final lower = archive.path.toLowerCase();
    if (lower.endsWith('.zip')) {
      final input = InputFileStream(archive.path);
      try {
        final arch = ZipDecoder().decodeStream(input);
        _writeEntriesToDisk(arch, outputDir);
      } finally {
        input.closeSync();
      }
    } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
      // Decompress .gz to a temp .tar so the tar decoder can stream the
      // result; avoids holding the full uncompressed tar in memory.
      final tarTmp = File(
        p.join(
          _cache.tmpRoot,
          'tmp-tar-${DateTime.now().microsecondsSinceEpoch}.tar',
        ),
      );
      final gzIn = InputFileStream(archive.path);
      final tarOut = OutputFileStream(tarTmp.path);
      try {
        GZipDecoder().decodeStream(gzIn, tarOut);
      } finally {
        tarOut.closeSync();
        gzIn.closeSync();
      }
      try {
        final tarIn = InputFileStream(tarTmp.path);
        try {
          final arch = TarDecoder().decodeStream(tarIn);
          _writeEntriesToDisk(arch, outputDir);
        } finally {
          tarIn.closeSync();
        }
      } finally {
        try {
          tarTmp.deleteSync();
        } catch (_) {}
      }
    } else {
      throw UserError('unrecognized JDK archive format: ${archive.path}');
    }
  }

  /// Manually iterates [arch] and writes entries to [outputDir]. Unlike
  /// `package:archive`'s `extractArchiveToDisk`, write failures are
  /// surfaced rather than silently swallowed — the partial-extraction
  /// bug those swallowed errors mask is precisely what was producing
  /// "extracted Temurin archive but could not find bin/java inside".
  void _writeEntriesToDisk(Archive arch, Directory outputDir) {
    final outRoot = p.normalize(p.absolute(outputDir.path));
    for (final entry in arch) {
      final dest = p.normalize(p.join(outRoot, entry.name));
      // Path traversal guard: archive entries naming `../foo` or
      // absolute paths must not escape outputDir.
      if (dest != outRoot && !p.isWithin(outRoot, dest)) continue;

      if (entry.isSymbolicLink) {
        Directory(p.dirname(dest)).createSync(recursive: true);
        final link = Link(dest);
        if (link.existsSync()) link.deleteSync();
        link.createSync(p.normalize(entry.symbolicLink ?? ''));
        continue;
      }
      if (entry.isDirectory) {
        Directory(dest).createSync(recursive: true);
        continue;
      }
      Directory(p.dirname(dest)).createSync(recursive: true);
      final out = OutputFileStream(dest);
      try {
        entry.writeContent(out);
      } catch (e) {
        try {
          out.closeSync();
        } catch (_) {}
        throw UserError('failed extracting ${entry.name} from JDK archive: $e');
      }
      out.closeSync();
    }
  }

  void _chmodPosixBinaries(Directory dir) {
    void chmodFile(File f) {
      try {
        Process.runSync('chmod', ['+x', f.path]);
      } catch (_) {
        // Non-fatal; if chmod isn't available the user will see a
        // clearer error from the spawn step.
      }
    }

    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final parent = p.basename(p.dirname(entity.path));
      if (parent == 'bin' || name == 'jspawnhelper') {
        chmodFile(entity);
      }
    }
  }

  bool _hasSentinel(Directory dir) {
    if (!dir.existsSync()) return false;
    for (final entity in dir.listSync()) {
      if (entity is File &&
          p.basename(entity.path).startsWith('.gitrinth-installed-temurin-')) {
        return true;
      }
    }
    return false;
  }

  /// Locates `java[.exe]` under [dir]. Adoptium archives wrap a single
  /// top-level dir (e.g. `jdk-21.0.5+11/`); on macOS the binary lives
  /// at `Contents/Home/bin/java`. Tries both layouts under each child.
  File? _findJavaBinary(Directory dir, String osKey) {
    if (!dir.existsSync()) return null;
    final binaryName = osKey == 'windows' ? 'java.exe' : 'java';
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final direct = File(p.join(entity.path, 'bin', binaryName));
      if (direct.existsSync()) return direct;
      final macos = File(
        p.join(entity.path, 'Contents', 'Home', 'bin', binaryName),
      );
      if (macos.existsSync()) return macos;
    }
    return null;
  }

  void _writeSentinel({
    required Directory dir,
    required int feature,
    required String fullVersion,
    required String osKey,
    required String archKey,
    required String sourceUrl,
    required String sha256,
  }) {
    final marker = File(
      p.join(dir.path, '.gitrinth-installed-temurin-$fullVersion'),
    );
    marker.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'vendor': vendor,
        'feature': feature,
        'fullVersion': fullVersion,
        'os': osKey,
        'arch': archKey,
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'source': sourceUrl,
        'sha256': sha256,
      }),
    );
  }
}

class _AdoptiumMetadata {
  final String url;
  final String sha256;
  final String fullVersion;

  const _AdoptiumMetadata({
    required this.url,
    required this.sha256,
    required this.fullVersion,
  });
}
