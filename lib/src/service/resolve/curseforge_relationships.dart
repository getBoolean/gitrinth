import '../../cli/exceptions.dart';
import '../../model/curseforge/cf_file_relation.dart';
import '../../model/curseforge/cf_mod_file.dart';
import '../source_identity.dart';
import 'curseforge_resolver.dart';
import 'hash_scan.dart';

/// Select the same final files as lock construction, after hash matching settles.
Map<LocalEntryKey, ModFile> selectedCurseforgeFiles(
  CfResolution resolution,
  Map<LocalEntryKey, HashOutcome> hashOutcomes,
) {
  final selected = <LocalEntryKey, ModFile>{};
  for (final entry in resolution.resolved.entries) {
    final file = switch (hashOutcomes[entry.key]) {
      HashMatched(:final curseforgeFile) => curseforgeFile,
      HashAcceptedMismatch(:final curseforgeFile) => curseforgeFile,
      _ => entry.value.file,
    };
    if (file.modId != entry.value.project.id) {
      throw ValidationError(
        'CurseForge file ${file.id} belongs to project ${file.modId}, not selected project ${entry.value.project.id} for ${entry.key.localKey}.',
      );
    }
    selected[entry.key] = file;
  }
  return selected;
}

/// Validate by numeric provider identity so local aliases cannot hide edges.
void validateCurseforgeRelationships(
  Map<LocalEntryKey, ModFile> files, {
  Set<String> overriddenSlugs = const {},
}) {
  final aliases = <int, List<LocalEntryKey>>{};
  final overriddenProjects = <int>{};
  for (final entry in files.entries) {
    (aliases[entry.value.modId] ??= []).add(entry.key);
    if (overriddenSlugs.contains(entry.key.localKey)) {
      overriddenProjects.add(entry.value.modId);
    }
  }
  String describe(int projectId) {
    final nodes = aliases[projectId] ?? const <LocalEntryKey>[];
    final names =
        nodes.map((node) => '${node.section.name}/${node.localKey}').toList()
          ..sort();
    final ids = nodes.map((node) => files[node]?.id).nonNulls.toSet().toList()
      ..sort();
    return '${names.join(', ')} (project $projectId, files ${ids.join(', ')})';
  }

  final conflicts = <String, String>{};
  for (final file in files.values) {
    if (!file.isAvailable) {
      throw ValidationError(
        'Selected CurseForge project ${file.modId}, file ${file.id} is unavailable. Run `gitrinth get` online to refresh it.',
      );
    }
    if (overriddenProjects.contains(file.modId)) continue;
    for (final relation in file.dependencies) {
      final other = relation.modId;
      if (relation.relationType != RelationType.incompatible ||
          !aliases.containsKey(other) ||
          overriddenProjects.contains(other)) {
        continue;
      }
      final pair = [file.modId, other]..sort();
      conflicts['${pair.first}:${pair.last}'] =
          '${describe(pair.first)} is incompatible with ${describe(pair.last)}.';
    }
  }
  if (conflicts.isNotEmpty) {
    final keys = conflicts.keys.toList()..sort();
    throw ValidationError(
      [
        'Selected CurseForge files cannot coexist:',
        for (final key in keys) '  ${conflicts[key]}',
        'Choose an explicit compatible pin in mods.yaml and run `gitrinth get` again.',
      ].join('\n'),
    );
  }
}
