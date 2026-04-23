// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'dependency.dart';

class DependencyTypeMapper extends EnumMapper<DependencyType> {
  DependencyTypeMapper._();

  static DependencyTypeMapper? _instance;
  static DependencyTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DependencyTypeMapper._());
    }
    return _instance!;
  }

  static DependencyType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  DependencyType decode(dynamic value) {
    switch (value) {
      case r'required':
        return DependencyType.required;
      case r'optional':
        return DependencyType.optional;
      case r'embedded':
        return DependencyType.embedded;
      case r'incompatible':
        return DependencyType.incompatible;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(DependencyType self) {
    switch (self) {
      case DependencyType.required:
        return r'required';
      case DependencyType.optional:
        return r'optional';
      case DependencyType.embedded:
        return r'embedded';
      case DependencyType.incompatible:
        return r'incompatible';
    }
  }
}

extension DependencyTypeMapperExtension on DependencyType {
  String toValue() {
    DependencyTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<DependencyType>(this) as String;
  }
}

class DependencyMapper extends ClassMapperBase<Dependency> {
  DependencyMapper._();

  static DependencyMapper? _instance;
  static DependencyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DependencyMapper._());
      DependencyTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Dependency';

  static String? _$projectId(Dependency v) => v.projectId;
  static const Field<Dependency, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    key: r'project_id',
    opt: true,
  );
  static String? _$versionId(Dependency v) => v.versionId;
  static const Field<Dependency, String> _f$versionId = Field(
    'versionId',
    _$versionId,
    key: r'version_id',
    opt: true,
  );
  static DependencyType _$dependencyType(Dependency v) => v.dependencyType;
  static const Field<Dependency, DependencyType> _f$dependencyType = Field(
    'dependencyType',
    _$dependencyType,
    key: r'dependency_type',
  );

  @override
  final MappableFields<Dependency> fields = const {
    #projectId: _f$projectId,
    #versionId: _f$versionId,
    #dependencyType: _f$dependencyType,
  };

  static Dependency _instantiate(DecodingData data) {
    return Dependency(
      projectId: data.dec(_f$projectId),
      versionId: data.dec(_f$versionId),
      dependencyType: data.dec(_f$dependencyType),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Dependency fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Dependency>(map);
  }

  static Dependency fromJson(String json) {
    return ensureInitialized().decodeJson<Dependency>(json);
  }
}

mixin DependencyMappable {
  String toJson() {
    return DependencyMapper.ensureInitialized().encodeJson<Dependency>(
      this as Dependency,
    );
  }

  Map<String, dynamic> toMap() {
    return DependencyMapper.ensureInitialized().encodeMap<Dependency>(
      this as Dependency,
    );
  }

  DependencyCopyWith<Dependency, Dependency, Dependency> get copyWith =>
      _DependencyCopyWithImpl<Dependency, Dependency>(
        this as Dependency,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return DependencyMapper.ensureInitialized().stringifyValue(
      this as Dependency,
    );
  }

  @override
  bool operator ==(Object other) {
    return DependencyMapper.ensureInitialized().equalsValue(
      this as Dependency,
      other,
    );
  }

  @override
  int get hashCode {
    return DependencyMapper.ensureInitialized().hashValue(this as Dependency);
  }
}

extension DependencyValueCopy<$R, $Out>
    on ObjectCopyWith<$R, Dependency, $Out> {
  DependencyCopyWith<$R, Dependency, $Out> get $asDependency =>
      $base.as((v, t, t2) => _DependencyCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class DependencyCopyWith<$R, $In extends Dependency, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? projectId,
    String? versionId,
    DependencyType? dependencyType,
  });
  DependencyCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _DependencyCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Dependency, $Out>
    implements DependencyCopyWith<$R, Dependency, $Out> {
  _DependencyCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Dependency> $mapper =
      DependencyMapper.ensureInitialized();
  @override
  $R call({
    Object? projectId = $none,
    Object? versionId = $none,
    DependencyType? dependencyType,
  }) => $apply(
    FieldCopyWithData({
      if (projectId != $none) #projectId: projectId,
      if (versionId != $none) #versionId: versionId,
      if (dependencyType != null) #dependencyType: dependencyType,
    }),
  );
  @override
  Dependency $make(CopyWithData data) => Dependency(
    projectId: data.get(#projectId, or: $value.projectId),
    versionId: data.get(#versionId, or: $value.versionId),
    dependencyType: data.get(#dependencyType, or: $value.dependencyType),
  );

  @override
  DependencyCopyWith<$R2, Dependency, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _DependencyCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

