import 'package:dart_mappable/dart_mappable.dart';

part 'project.mapper.dart';

@MappableClass()
class Project with ProjectMappable {
  final String id;
  final String slug;
  final String title;
  @MappableField(key: 'project_type')
  final String projectType;
  @MappableField(key: 'loaders')
  final List<String> loaders;

  const Project({
    required this.id,
    required this.slug,
    required this.title,
    required this.projectType,
    this.loaders = const [],
  });
}
