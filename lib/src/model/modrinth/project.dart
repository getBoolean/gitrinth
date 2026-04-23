import 'package:dart_mappable/dart_mappable.dart';

part 'project.mapper.dart';

@MappableClass()
class Project with ProjectMappable {
  final String id;
  final String slug;
  final String title;
  @MappableField(key: 'project_type')
  final String projectType;

  const Project({
    required this.id,
    required this.slug,
    required this.title,
    required this.projectType,
  });
}
