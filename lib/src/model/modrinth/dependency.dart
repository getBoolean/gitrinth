import 'package:dart_mappable/dart_mappable.dart';

part 'dependency.mapper.dart';

@MappableEnum()
enum DependencyType { required, optional, embedded, incompatible }

@MappableClass()
class Dependency with DependencyMappable {
  @MappableField(key: 'project_id')
  final String? projectId;
  @MappableField(key: 'version_id')
  final String? versionId;
  @MappableField(key: 'dependency_type')
  final DependencyType dependencyType;

  const Dependency({
    this.projectId,
    this.versionId,
    required this.dependencyType,
  });
}
