import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'project_overrides.mapper.dart';

@MappableClass()
class ProjectOverrides with ProjectOverridesMappable {
  final Map<String, ModEntry> entries;

  const ProjectOverrides({this.entries = const {}});
}
