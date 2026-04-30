// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'cf_file_relation.dart';

class RelationTypeMapper extends EnumMapper<RelationType> {
  RelationTypeMapper._();

  static RelationTypeMapper? _instance;
  static RelationTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RelationTypeMapper._());
    }
    return _instance!;
  }

  static RelationType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RelationType decode(dynamic value) {
    switch (value) {
      case r'embeddedLibrary':
        return RelationType.embeddedLibrary;
      case r'optionalDependency':
        return RelationType.optionalDependency;
      case r'requiredDependency':
        return RelationType.requiredDependency;
      case r'tool':
        return RelationType.tool;
      case r'incompatible':
        return RelationType.incompatible;
      case r'include':
        return RelationType.include;
      case r'unknown':
        return RelationType.unknown;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RelationType self) {
    switch (self) {
      case RelationType.embeddedLibrary:
        return r'embeddedLibrary';
      case RelationType.optionalDependency:
        return r'optionalDependency';
      case RelationType.requiredDependency:
        return r'requiredDependency';
      case RelationType.tool:
        return r'tool';
      case RelationType.incompatible:
        return r'incompatible';
      case RelationType.include:
        return r'include';
      case RelationType.unknown:
        return r'unknown';
    }
  }
}

extension RelationTypeMapperExtension on RelationType {
  String toValue() {
    RelationTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RelationType>(this) as String;
  }
}

class FileRelationMapper extends ClassMapperBase<FileRelation> {
  FileRelationMapper._();

  static FileRelationMapper? _instance;
  static FileRelationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FileRelationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FileRelation';

  static int _$modId(FileRelation v) => v.modId;
  static const Field<FileRelation, int> _f$modId = Field('modId', _$modId);
  static int _$relationTypeCode(FileRelation v) => v.relationTypeCode;
  static const Field<FileRelation, int> _f$relationTypeCode = Field(
    'relationTypeCode',
    _$relationTypeCode,
    key: r'relationType',
  );

  @override
  final MappableFields<FileRelation> fields = const {
    #modId: _f$modId,
    #relationTypeCode: _f$relationTypeCode,
  };

  static FileRelation _instantiate(DecodingData data) {
    return FileRelation(
      modId: data.dec(_f$modId),
      relationTypeCode: data.dec(_f$relationTypeCode),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FileRelation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FileRelation>(map);
  }

  static FileRelation fromJson(String json) {
    return ensureInitialized().decodeJson<FileRelation>(json);
  }
}

mixin FileRelationMappable {
  String toJson() {
    return FileRelationMapper.ensureInitialized().encodeJson<FileRelation>(
      this as FileRelation,
    );
  }

  Map<String, dynamic> toMap() {
    return FileRelationMapper.ensureInitialized().encodeMap<FileRelation>(
      this as FileRelation,
    );
  }

  FileRelationCopyWith<FileRelation, FileRelation, FileRelation> get copyWith =>
      _FileRelationCopyWithImpl<FileRelation, FileRelation>(
        this as FileRelation,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FileRelationMapper.ensureInitialized().stringifyValue(
      this as FileRelation,
    );
  }

  @override
  bool operator ==(Object other) {
    return FileRelationMapper.ensureInitialized().equalsValue(
      this as FileRelation,
      other,
    );
  }

  @override
  int get hashCode {
    return FileRelationMapper.ensureInitialized().hashValue(
      this as FileRelation,
    );
  }
}

extension FileRelationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FileRelation, $Out> {
  FileRelationCopyWith<$R, FileRelation, $Out> get $asFileRelation =>
      $base.as((v, t, t2) => _FileRelationCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FileRelationCopyWith<$R, $In extends FileRelation, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? modId, int? relationTypeCode});
  FileRelationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FileRelationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FileRelation, $Out>
    implements FileRelationCopyWith<$R, FileRelation, $Out> {
  _FileRelationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FileRelation> $mapper =
      FileRelationMapper.ensureInitialized();
  @override
  $R call({int? modId, int? relationTypeCode}) => $apply(
    FieldCopyWithData({
      if (modId != null) #modId: modId,
      if (relationTypeCode != null) #relationTypeCode: relationTypeCode,
    }),
  );
  @override
  FileRelation $make(CopyWithData data) => FileRelation(
    modId: data.get(#modId, or: $value.modId),
    relationTypeCode: data.get(#relationTypeCode, or: $value.relationTypeCode),
  );

  @override
  FileRelationCopyWith<$R2, FileRelation, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FileRelationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

