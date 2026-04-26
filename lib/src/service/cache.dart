import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/version.dart' as modrinth;
import 'console.dart';

class GitrinthCache {
  final String root;
  final Console _console;

  GitrinthCache({required this.root, Console? console})
    : _console = console ?? const Console();

  String get modrinthRoot => p.normalize(p.join(root, 'modrinth'));
  String get urlRoot => p.normalize(p.join(root, 'url'));
  String get tmpRoot => p.normalize(p.join(root, 'tmp'));
  String get loadersRoot => p.normalize(p.join(root, 'loaders'));
  String get launchersRoot => p.normalize(p.join(root, 'launchers'));
  String get runtimesRoot => p.normalize(p.join(root, 'runtimes'));

  /// Path to a `_unverified` staging file under [urlRoot] for a
  /// url:-sourced artifact whose sha512 isn't yet known. Used by
  /// `gitrinth get` / `build` to land the download before promoting it
  /// to the sha-keyed canonical path via [urlPath].
  String unverifiedUrlPath(String slug, String filename) =>
      p.normalize(p.join(urlRoot, '_unverified', slug, filename));

  /// Path of the file lock used to serialize concurrent downloads of the
  /// Temurin JDK for a given [feature] version.
  String javaRuntimeLockPath(String feature) =>
      p.normalize(p.join(runtimesRoot, '.lock-temurin-$feature'));

  /// Root directory of an extracted JDK feature for the current host.
  /// Inside lives the vendor's archive top-level directory (e.g.
  /// `jdk-21.0.5+11/`) plus a sentinel marker file.
  String javaRuntimeDir({
    required String vendor,
    required int feature,
    required String osKey,
    required String archKey,
  }) {
    return p.join(runtimesRoot, vendor, feature.toString(), '$osKey-$archKey');
  }

  /// Per-pack launcher work directory used by `gitrinth launch client`.
  /// Holds the loader install (`versions/`, `libraries/`, `assets/`),
  /// `launcher_profiles.json`, and Minecraft's user-state files (`saves/`,
  /// `screenshots/`, `options.txt`, ...). Survives `gitrinth clean` so worlds
  /// and tweaked options aren't wiped when build artifacts are.
  String launcherWorkDir({required String slug}) {
    if (slug.isEmpty) {
      throw const ValidationError(
        'launcher work dir requires a non-empty slug',
      );
    }
    return p.join(launchersRoot, slug);
  }

  /// Path where a loader binary (server installer JAR, vanilla server.jar,
  /// fabric-server-launch.jar, etc.) lives. Keyed by `(loader, mcVersion,
  /// loaderVersion)` so the same modpack rebuilt twice never re-downloads.
  String loaderArtifactPath({
    required Loader loader,
    required String mcVersion,
    required String loaderVersion,
    required String filename,
  }) {
    return p.join(loadersRoot, loader.name, mcVersion, loaderVersion, filename);
  }

  /// Path where a Modrinth-sourced artifact should live.
  String modrinthPath({
    required String projectId,
    required String versionId,
    required String filename,
  }) {
    return p.join(modrinthRoot, projectId, versionId, filename);
  }

  /// Path where the resolved Modrinth `Version`'s metadata (mainly its
  /// `dependencies` array) is persisted alongside the artifact. Mirrors
  /// dart pub's "graph in cache, not lock" architecture — this file is
  /// the source of truth for `gitrinth upgrade --unlock-transitive`'s
  /// transitive-closure walk.
  String modrinthVersionMetadataPath({
    required String projectId,
    required String versionId,
  }) {
    return p.join(modrinthRoot, projectId, versionId, 'version.json');
  }

  /// Walks `<modrinthRoot>/<projectId>/*/version.json` and yields each
  /// successfully-parsed [modrinth.Version]. Malformed sidecars are skipped
  /// with a stderr warning so a single corrupt file doesn't abort an
  /// `--offline` resolve.
  Iterable<modrinth.Version> listCachedVersions(String projectId) sync* {
    final dir = Directory(p.join(modrinthRoot, projectId));
    if (!dir.existsSync()) return;
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final sidecar = File(p.join(entry.path, 'version.json'));
      if (!sidecar.existsSync()) continue;
      try {
        final raw = jsonDecode(sidecar.readAsStringSync());
        if (raw is! Map<String, dynamic>) continue;
        yield modrinth.VersionMapper.fromMap(raw);
      } on Object catch (e) {
        _console.warn('cache: skipping malformed ${sidecar.path}: $e');
      }
    }
  }

  /// Path where a url:-sourced artifact should live, keyed by sha512.
  String urlPath({required String sha512, required String filename}) {
    final lower = sha512.toLowerCase();
    if (lower.length < 2) {
      throw ValidationError(
        'sha512 "$sha512" is too short; expected the full hex digest.',
      );
    }
    final prefix = lower.substring(0, 2);
    return p.join(urlRoot, prefix, lower, filename);
  }

  void ensureRoot() {
    Directory(root).createSync(recursive: true);
    Directory(tmpRoot).createSync(recursive: true);
  }

  /// Verifies [bytes] against [expectedSha512] (case-insensitive). Throws
  /// [UserError] on mismatch.
  static void verifySha512(List<int> bytes, String expectedSha512) {
    final actual = sha512.convert(bytes).toString();
    if (actual.toLowerCase() != expectedSha512.toLowerCase()) {
      throw UserError(
        'checksum mismatch: expected $expectedSha512, got $actual',
      );
    }
  }

  /// Verifies the contents of [file] against [expectedSha512].
  static Future<void> verifyFileSha512(File file, String expectedSha512) async {
    final bytes = await file.readAsBytes();
    verifySha512(Uint8List.fromList(bytes), expectedSha512);
  }

  /// Verifies [bytes] against [expectedSha256] (case-insensitive). Throws
  /// [UserError] on mismatch.
  static void verifySha256(List<int> bytes, String expectedSha256) {
    final actual = sha256.convert(bytes).toString();
    if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
      throw UserError(
        'checksum mismatch: expected $expectedSha256, got $actual',
      );
    }
  }

  /// Verifies the contents of [file] against [expectedSha256].
  static Future<void> verifyFileSha256(File file, String expectedSha256) async {
    final bytes = await file.readAsBytes();
    verifySha256(Uint8List.fromList(bytes), expectedSha256);
  }
}
