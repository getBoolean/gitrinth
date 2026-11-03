import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/server_distribution.dart';
import '../service/artifact_locator.dart';
import '../service/cache.dart';
import '../service/file_digest.dart';
import '../service/modrinth/modrinth_url.dart';
import '../service/pack_archive_writer.dart';
import 'build_assembler.dart';

/// Packages selected server artifacts; installing the runtime is a separate step.
Future<void> writeServerDistribution(
  File output, {
  required ModsYaml yaml,
  required ModsLock lock,
  required GitrinthCache cache,
  required String projectDir,
  LoaderRegistry registry = LoaderRegistry.builtins,
  String modrinthHost = defaultModrinthBaseUrl,
  bool publishable = false,
}) async {
  if (registry[lock.loader.mods] == null) {
    throw ValidationError(
      'Loader ${lock.loader.mods.name} has no metadata capability snapshot for a server distribution.',
    );
  }
  final pluginLoader = lock.loader.plugins;
  if (pluginLoader != null && registry[pluginLoader] == null) {
    throw ValidationError(
      'Plugin loader ${pluginLoader.name} has no metadata capability snapshot for a server distribution.',
    );
  }
  final locator = ArtifactLocator(
    cache: cache,
    projectDir: projectDir,
    defaultModrinthHost: modrinthHost,
  );
  final sources = <String, File>{};
  void include(String path, File source) {
    if (!isSafeServerDistributionPath(path)) {
      throw ValidationError('Unsafe server distribution path: $path');
    }
    if (isPrivateServerDistributionPath(path)) return;
    if (sources.keys.any(
      (existing) => existing.toLowerCase() == path.toLowerCase(),
    )) {
      throw ValidationError('Duplicate server distribution path: $path');
    }
    if (!source.existsSync()) {
      throw UserError(
        'Server distribution source is missing: ${source.path}. Run `gitrinth get` first.',
      );
    }
    sources[path] = source;
  }

  for (final section in Section.values) {
    for (final entry in lock.sectionFor(section).values) {
      final subdir = buildSubdirFor(section, BuildEnv.server, entry);
      if (subdir == null) continue;
      final cf = entry.curseforge;
      if (cf != null && !cf.allowModDistribution) {
        throw ValidationError(
          'CurseForge project ${cf.projectId}, file ${cf.fileId} (${entry.slug}) disallows redistribution; it cannot be bundled in a server distribution.',
        );
      }
      if (publishable &&
          (cf == null ||
              yaml.sectionEntries(section)[entry.slug]?.allowHashMismatch ==
                  true)) {
        throw ValidationError(
          '--publishable refused for CurseForge server distribution: ${entry.slug} requires loose overrides or allow_hash_mismatch.',
        );
      }
      include(
        p.posix.join(subdir, destFilenameFor(entry)),
        File(locator.preferred(entry)),
      );
    }
  }
  for (final entry in lock.files.values) {
    if (!entry.server.includes) continue;
    if (isPrivateServerDistributionPath(
      p.posix.joinAll(p.split(entry.sourcePath)),
    )) {
      continue;
    }
    include(entry.destination, File(locator.path(entry.sourcePath)));
  }
  if (sources.isEmpty) {
    throw const ValidationError(
      'No physical server files were selected for the server distribution.',
    );
  }
  final files = <ServerDistributionFile>[];
  for (final entry in sources.entries) {
    files.add(
      ServerDistributionFile(
        path: entry.key,
        sha256: await fileDigest(entry.value, sha256),
      ),
    );
  }
  final marker = ServerDistributionManifest(
    slug: yaml.slug,
    version: yaml.version,
    minecraft: lock.mcVersion,
    loaderId: lock.loader.mods.name,
    loaderVersion: lock.loader.hasModRuntime
        ? lock.loader.modLoaderVersion
        : null,
    pluginLoaderId: pluginLoader?.name,
    pluginLoaderVersion: lock.loader.pluginLoaderVersion,
    files: files,
  );
  output.parent.createSync(recursive: true);
  writeArchive(
    output,
    manifestName: serverDistributionManifestName,
    manifest: utf8.encode(
      const JsonEncoder.withIndent('  ').convert(marker.toMap()),
    ),
    entries: sources.entries.map(
      (entry) => (path: entry.key, source: entry.value),
    ),
  );
}
