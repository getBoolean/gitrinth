import 'package:dart_mappable/dart_mappable.dart';

part 'cf_file_relation.mapper.dart';

/// CurseForge `FileRelationType`. Wire codes:
///   1 = embeddedLibrary
///   2 = optionalDependency
///   3 = requiredDependency
///   4 = tool
///   5 = incompatible
///   6 = include
@MappableEnum()
enum RelationType {
  embeddedLibrary,
  optionalDependency,
  requiredDependency,
  tool,
  incompatible,
  include,
  unknown,
}

/// One entry in CurseForge's `ModFile.dependencies` list.
@MappableClass()
class FileRelation with FileRelationMappable {
  final int modId;

  /// Raw integer code from the API. Use [relationType] for the decoded
  /// enum.
  @MappableField(key: 'relationType')
  final int relationTypeCode;

  const FileRelation({required this.modId, required this.relationTypeCode});

  RelationType get relationType => switch (relationTypeCode) {
    1 => RelationType.embeddedLibrary,
    2 => RelationType.optionalDependency,
    3 => RelationType.requiredDependency,
    4 => RelationType.tool,
    5 => RelationType.incompatible,
    6 => RelationType.include,
    _ => RelationType.unknown,
  };
}
