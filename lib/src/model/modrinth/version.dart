import 'package:dart_mappable/dart_mappable.dart';

import 'dependency.dart';
import 'version_file.dart';

part 'version.mapper.dart';

@MappableClass()
class Version with VersionMappable {
  final String id;
  @MappableField(key: 'project_id')
  final String projectId;
  @MappableField(key: 'version_number')
  final String versionNumber;
  final List<VersionFile> files;
  final List<Dependency> dependencies;
  final List<String> loaders;
  @MappableField(key: 'game_versions')
  final List<String> gameVersions;
  @MappableField(key: 'date_published')
  final String? datePublished;
  @MappableField(key: 'version_type')
  final String? versionType;

  const Version({
    required this.id,
    required this.projectId,
    required this.versionNumber,
    required this.files,
    required this.dependencies,
    required this.loaders,
    required this.gameVersions,
    this.datePublished,
    this.versionType,
  });

  VersionFile? get primaryFile {
    if (files.isEmpty) return null;
    return files.firstWhere((f) => f.primary, orElse: () => files.first);
  }
}
