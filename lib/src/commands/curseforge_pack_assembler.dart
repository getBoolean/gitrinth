import 'dart:convert';
import 'dart:io';

import '../cli/exceptions.dart';
import '../model/curseforge/cf_constants.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/cache.dart';
import '../service/modrinth/modrinth_url.dart';
import '../service/pack_archive_writer.dart';
import 'pack_assembler.dart';

/// CurseForge's manifest/overrides format has one override root. Separate
/// client/server archives preserve side filtering without inventing CF fields.
Map<String, dynamic> buildCurseForgeManifest({
  required ModsYaml yaml,
  required ModsLock lock,
  required PackTarget target,
  required bool publishable,
}) {
  final files = <Map<String, dynamic>>[];
  final offenders = <String>[];
  for (final section in Section.values) {
    for (final entry in lock.sectionFor(section).values) {
      final include = switch (target) {
        PackTarget.client => entry.client.includes,
        PackTarget.server => entry.server.includes,
        PackTarget.combined => entry.client.includes || entry.server.includes,
      };
      if (!include) continue;
      final cf = entry.curseforge;
      final eligible =
          section != Section.plugins ||
          (lock.loader.plugins != null &&
              pluginLoaderEligibleForCurseforge(lock.loader.plugins!));
      if (cf == null ||
          !eligible ||
          yaml.sectionEntries(section)[entry.slug]?.allowHashMismatch == true) {
        offenders.add(entry.slug);
      }
      if (cf != null && eligible) {
        files.add({
          'projectID': cf.projectId,
          'fileID': cf.fileId,
          'required': true,
        });
      }
    }
  }
  if (publishable && offenders.isNotEmpty) {
    throw ValidationError(
      '--publishable refused for CurseForge: '
      '${offenders.join(', ')} require loose overrides or allow_hash_mismatch.',
    );
  }
  final version = lock.loader.modLoaderVersion;
  if (lock.loader.hasModRuntime &&
      (version == null || version == 'stable' || version == 'latest')) {
    throw const ValidationError(
      'mods.lock has no concrete loader version. Re-run `gitrinth get`.',
    );
  }
  return {
    'minecraft': {
      'version': lock.mcVersion,
      'modLoaders': [
        if (lock.loader.hasModRuntime)
          {
            'id':
                '${switch (lock.loader.mods) {
                  ModLoader.fabric => 'fabric',
                  ModLoader.neoforge => 'neoforge',
                  ModLoader.forge => 'forge',
                  ModLoader.vanilla => '',
                }}-$version',
            'primary': true,
          },
      ],
    },
    'manifestType': 'minecraftModpack',
    'manifestVersion': 1,
    'name': yaml.name,
    'author': '',
    'version': yaml.version,
    'files': files,
    'overrides': 'overrides',
  };
}

void writePackArchive(
  File output, {
  required String manifestName,
  required Map<String, dynamic> manifest,
  required List<OverridePlan> overrides,
}) {
  final json = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  for (final entry in overrides) {
    final source = File(entry.sourcePath);
    if (!source.existsSync()) {
      throw UserError(
        'override source for "${entry.slug}" missing on disk: ${entry.sourcePath}. Re-run `gitrinth get`.',
      );
    }
  }
  output.parent.createSync(recursive: true);
  writeArchive(
    output,
    manifestName: manifestName,
    manifest: json,
    entries: overrides.map(
      (entry) => (path: entry.zipPath, source: File(entry.sourcePath)),
    ),
  );
}

OverridesPlan curseForgeOverrides({
  required ModsLock lock,
  required GitrinthCache cache,
  required String projectDir,
  required PackTarget target,
  String modrinthHost = defaultModrinthBaseUrl,
}) => collectOverrides(
  lock: lock,
  cache: cache,
  projectDir: projectDir,
  target: target,
  platform: SourceKind.curseforge,
  modrinthHost: modrinthHost,
);
