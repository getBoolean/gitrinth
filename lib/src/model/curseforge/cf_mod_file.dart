import 'package:dart_mappable/dart_mappable.dart';

import 'cf_file_hash.dart';
import 'cf_file_relation.dart';

part 'cf_mod_file.mapper.dart';

/// One file attached to a CurseForge mod project.
@MappableClass()
class ModFile with ModFileMappable {
  final int id;
  final int modId;
  final String displayName;
  final String fileName;

  /// CurseForge release type. 1=release, 2=beta, 3=alpha. Filtered
  /// against `cfReleaseTypesFor(channel)` in the resolver.
  final int releaseType;

  /// ISO-8601 publish date string. Stored as-is so callers can sort
  /// lexicographically (ISO-8601 sorts equivalently to chronological
  /// order).
  final String fileDate;

  /// Loose tags CurseForge attaches to the file — Minecraft versions
  /// (e.g. `"1.21.1"`) and loader markers (`"Forge"`, `"Fabric"`).
  /// Filtering happens client-side because the API's `gameVersion`
  /// query parameter only accepts a single value.
  final List<String> gameVersions;

  final List<FileHash> hashes;

  /// Dependency relations declared by the file. Mapped from the JSON
  /// `dependencies` array.
  final List<FileRelation> dependencies;

  /// CDN download URL. `null` when the project's author has set
  /// `allowModDistribution: false` on CurseForge — Part 4 surfaces a
  /// "manual download required" error in that case rather than
  /// attempting to fetch.
  final String? downloadUrl;

  const ModFile({
    required this.id,
    required this.modId,
    required this.displayName,
    required this.fileName,
    required this.releaseType,
    required this.fileDate,
    required this.gameVersions,
    required this.hashes,
    required this.dependencies,
    this.downloadUrl,
  });

  /// First sha1 hash on the file, lowercased. `null` when the file
  /// reports no sha1 entry (CF historically also includes md5; sha1 is
  /// the cross-platform anchor for hash verification).
  String? get sha1Hash {
    for (final h in hashes) {
      if (h.algo == HashAlgo.sha1) return h.value.toLowerCase();
    }
    return null;
  }

  /// Subset of [dependencies] whose relation type is
  /// [RelationType.requiredDependency]. Drives transitive-dep
  /// resolution in Part 6.
  Iterable<FileRelation> get requiredDependencies => dependencies.where(
    (d) => d.relationType == RelationType.requiredDependency,
  );
}
