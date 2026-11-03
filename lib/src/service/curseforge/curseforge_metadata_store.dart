import 'dart:convert';
import 'dart:io';

import '../../cli/exceptions.dart';
import '../../model/curseforge/cf_mod_file.dart';
import '../../util/atomic_file_writer.dart';
import '../cache.dart';

/// Persists the selected file's provider metadata without changing mods.lock.
class CurseForgeMetadataStore {
  final GitrinthCache cache;
  const CurseForgeMetadataStore(this.cache);

  void write(ModFile file) {
    cache.curseforgePath(
      projectId: file.modId,
      fileId: file.id,
      filename: file.fileName,
    );
    final path = cache.curseforgeMetadataPath(
      projectId: file.modId,
      fileId: file.id,
    );
    try {
      atomicReplaceString(
        path,
        jsonEncode({
          'schemaVersion': 1,
          'projectId': file.modId,
          'fileId': file.id,
          'file': file.toMap(),
        }),
      );
    } on Object catch (e) {
      throw ValidationError(
        'Cannot persist CurseForge metadata for project ${file.modId}, file ${file.id} at $path: $e. mods.lock was not replaced.',
      );
    }
  }

  ModFile read({
    required int projectId,
    required int fileId,
    String? expectedSha1,
  }) {
    final path = cache.curseforgeMetadataPath(
      projectId: projectId,
      fileId: fileId,
    );
    try {
      final raw = jsonDecode(File(path).readAsStringSync());
      if (raw is! Map<String, dynamic> ||
          raw['schemaVersion'] != 1 ||
          raw['projectId'] != projectId ||
          raw['fileId'] != fileId ||
          raw['file'] is! Map<String, dynamic>) {
        throw const FormatException('invalid metadata envelope or identity');
      }
      final data = raw['file'] as Map<String, dynamic>;
      if (data['dependencies'] is! List ||
          data['isAvailable'] is! bool ||
          data['hashes'] is! List) {
        throw const FormatException('missing selected-file validation fields');
      }
      final file = ModFileMapper.fromMap(data);
      if (file.id != fileId ||
          file.modId != projectId ||
          !file.isAvailable ||
          (expectedSha1 != null &&
              file.sha1Hash != expectedSha1.toLowerCase())) {
        throw const FormatException(
          'selected-file identity, availability, or hash mismatch',
        );
      }
      return file;
    } on Object catch (e) {
      throw ValidationError(
        'Cannot validate offline CurseForge project $projectId, file $fileId from $path: $e. Run `gitrinth get` online once to refresh selected-file metadata.',
      );
    }
  }
}
