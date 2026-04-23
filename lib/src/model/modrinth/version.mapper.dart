// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'version.dart';

class VersionMapper extends ClassMapperBase<Version> {
  VersionMapper._();

  static VersionMapper? _instance;
  static VersionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VersionMapper._());
      VersionFileMapper.ensureInitialized();
      DependencyMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Version';

  static String _$id(Version v) => v.id;
  static const Field<Version, String> _f$id = Field('id', _$id);
  static String _$projectId(Version v) => v.projectId;
  static const Field<Version, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    key: r'project_id',
  );
  static String _$versionNumber(Version v) => v.versionNumber;
  static const Field<Version, String> _f$versionNumber = Field(
    'versionNumber',
    _$versionNumber,
    key: r'version_number',
  );
  static List<VersionFile> _$files(Version v) => v.files;
  static const Field<Version, List<VersionFile>> _f$files = Field(
    'files',
    _$files,
  );
  static List<Dependency> _$dependencies(Version v) => v.dependencies;
  static const Field<Version, List<Dependency>> _f$dependencies = Field(
    'dependencies',
    _$dependencies,
  );
  static List<String> _$loaders(Version v) => v.loaders;
  static const Field<Version, List<String>> _f$loaders = Field(
    'loaders',
    _$loaders,
  );
  static List<String> _$gameVersions(Version v) => v.gameVersions;
  static const Field<Version, List<String>> _f$gameVersions = Field(
    'gameVersions',
    _$gameVersions,
    key: r'game_versions',
  );
  static String? _$datePublished(Version v) => v.datePublished;
  static const Field<Version, String> _f$datePublished = Field(
    'datePublished',
    _$datePublished,
    key: r'date_published',
    opt: true,
  );

  @override
  final MappableFields<Version> fields = const {
    #id: _f$id,
    #projectId: _f$projectId,
    #versionNumber: _f$versionNumber,
    #files: _f$files,
    #dependencies: _f$dependencies,
    #loaders: _f$loaders,
    #gameVersions: _f$gameVersions,
    #datePublished: _f$datePublished,
  };

  static Version _instantiate(DecodingData data) {
    return Version(
      id: data.dec(_f$id),
      projectId: data.dec(_f$projectId),
      versionNumber: data.dec(_f$versionNumber),
      files: data.dec(_f$files),
      dependencies: data.dec(_f$dependencies),
      loaders: data.dec(_f$loaders),
      gameVersions: data.dec(_f$gameVersions),
      datePublished: data.dec(_f$datePublished),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Version fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Version>(map);
  }

  static Version fromJson(String json) {
    return ensureInitialized().decodeJson<Version>(json);
  }
}

mixin VersionMappable {
  String toJson() {
    return VersionMapper.ensureInitialized().encodeJson<Version>(
      this as Version,
    );
  }

  Map<String, dynamic> toMap() {
    return VersionMapper.ensureInitialized().encodeMap<Version>(
      this as Version,
    );
  }

  VersionCopyWith<Version, Version, Version> get copyWith =>
      _VersionCopyWithImpl<Version, Version>(
        this as Version,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return VersionMapper.ensureInitialized().stringifyValue(this as Version);
  }

  @override
  bool operator ==(Object other) {
    return VersionMapper.ensureInitialized().equalsValue(
      this as Version,
      other,
    );
  }

  @override
  int get hashCode {
    return VersionMapper.ensureInitialized().hashValue(this as Version);
  }
}

extension VersionValueCopy<$R, $Out> on ObjectCopyWith<$R, Version, $Out> {
  VersionCopyWith<$R, Version, $Out> get $asVersion =>
      $base.as((v, t, t2) => _VersionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class VersionCopyWith<$R, $In extends Version, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    VersionFile,
    VersionFileCopyWith<$R, VersionFile, VersionFile>
  >
  get files;
  ListCopyWith<$R, Dependency, DependencyCopyWith<$R, Dependency, Dependency>>
  get dependencies;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get loaders;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get gameVersions;
  $R call({
    String? id,
    String? projectId,
    String? versionNumber,
    List<VersionFile>? files,
    List<Dependency>? dependencies,
    List<String>? loaders,
    List<String>? gameVersions,
    String? datePublished,
  });
  VersionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _VersionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Version, $Out>
    implements VersionCopyWith<$R, Version, $Out> {
  _VersionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Version> $mapper =
      VersionMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    VersionFile,
    VersionFileCopyWith<$R, VersionFile, VersionFile>
  >
  get files => ListCopyWith(
    $value.files,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(files: v),
  );
  @override
  ListCopyWith<$R, Dependency, DependencyCopyWith<$R, Dependency, Dependency>>
  get dependencies => ListCopyWith(
    $value.dependencies,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(dependencies: v),
  );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get loaders =>
      ListCopyWith(
        $value.loaders,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(loaders: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get gameVersions => ListCopyWith(
    $value.gameVersions,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(gameVersions: v),
  );
  @override
  $R call({
    String? id,
    String? projectId,
    String? versionNumber,
    List<VersionFile>? files,
    List<Dependency>? dependencies,
    List<String>? loaders,
    List<String>? gameVersions,
    Object? datePublished = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (projectId != null) #projectId: projectId,
      if (versionNumber != null) #versionNumber: versionNumber,
      if (files != null) #files: files,
      if (dependencies != null) #dependencies: dependencies,
      if (loaders != null) #loaders: loaders,
      if (gameVersions != null) #gameVersions: gameVersions,
      if (datePublished != $none) #datePublished: datePublished,
    }),
  );
  @override
  Version $make(CopyWithData data) => Version(
    id: data.get(#id, or: $value.id),
    projectId: data.get(#projectId, or: $value.projectId),
    versionNumber: data.get(#versionNumber, or: $value.versionNumber),
    files: data.get(#files, or: $value.files),
    dependencies: data.get(#dependencies, or: $value.dependencies),
    loaders: data.get(#loaders, or: $value.loaders),
    gameVersions: data.get(#gameVersions, or: $value.gameVersions),
    datePublished: data.get(#datePublished, or: $value.datePublished),
  );

  @override
  VersionCopyWith<$R2, Version, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _VersionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

