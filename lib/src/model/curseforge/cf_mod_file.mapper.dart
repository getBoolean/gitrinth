// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'cf_mod_file.dart';

class ModFileMapper extends ClassMapperBase<ModFile> {
  ModFileMapper._();

  static ModFileMapper? _instance;
  static ModFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModFileMapper._());
      FileHashMapper.ensureInitialized();
      FileRelationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModFile';

  static int _$id(ModFile v) => v.id;
  static const Field<ModFile, int> _f$id = Field('id', _$id);
  static int _$modId(ModFile v) => v.modId;
  static const Field<ModFile, int> _f$modId = Field('modId', _$modId);
  static String _$displayName(ModFile v) => v.displayName;
  static const Field<ModFile, String> _f$displayName = Field(
    'displayName',
    _$displayName,
  );
  static String _$fileName(ModFile v) => v.fileName;
  static const Field<ModFile, String> _f$fileName = Field(
    'fileName',
    _$fileName,
  );
  static int _$releaseType(ModFile v) => v.releaseType;
  static const Field<ModFile, int> _f$releaseType = Field(
    'releaseType',
    _$releaseType,
  );
  static String _$fileDate(ModFile v) => v.fileDate;
  static const Field<ModFile, String> _f$fileDate = Field(
    'fileDate',
    _$fileDate,
  );
  static List<String> _$gameVersions(ModFile v) => v.gameVersions;
  static const Field<ModFile, List<String>> _f$gameVersions = Field(
    'gameVersions',
    _$gameVersions,
  );
  static List<FileHash> _$hashes(ModFile v) => v.hashes;
  static const Field<ModFile, List<FileHash>> _f$hashes = Field(
    'hashes',
    _$hashes,
  );
  static List<FileRelation> _$dependencies(ModFile v) => v.dependencies;
  static const Field<ModFile, List<FileRelation>> _f$dependencies = Field(
    'dependencies',
    _$dependencies,
  );
  static String? _$downloadUrl(ModFile v) => v.downloadUrl;
  static const Field<ModFile, String> _f$downloadUrl = Field(
    'downloadUrl',
    _$downloadUrl,
    opt: true,
  );

  @override
  final MappableFields<ModFile> fields = const {
    #id: _f$id,
    #modId: _f$modId,
    #displayName: _f$displayName,
    #fileName: _f$fileName,
    #releaseType: _f$releaseType,
    #fileDate: _f$fileDate,
    #gameVersions: _f$gameVersions,
    #hashes: _f$hashes,
    #dependencies: _f$dependencies,
    #downloadUrl: _f$downloadUrl,
  };

  static ModFile _instantiate(DecodingData data) {
    return ModFile(
      id: data.dec(_f$id),
      modId: data.dec(_f$modId),
      displayName: data.dec(_f$displayName),
      fileName: data.dec(_f$fileName),
      releaseType: data.dec(_f$releaseType),
      fileDate: data.dec(_f$fileDate),
      gameVersions: data.dec(_f$gameVersions),
      hashes: data.dec(_f$hashes),
      dependencies: data.dec(_f$dependencies),
      downloadUrl: data.dec(_f$downloadUrl),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModFile>(map);
  }

  static ModFile fromJson(String json) {
    return ensureInitialized().decodeJson<ModFile>(json);
  }
}

mixin ModFileMappable {
  String toJson() {
    return ModFileMapper.ensureInitialized().encodeJson<ModFile>(
      this as ModFile,
    );
  }

  Map<String, dynamic> toMap() {
    return ModFileMapper.ensureInitialized().encodeMap<ModFile>(
      this as ModFile,
    );
  }

  ModFileCopyWith<ModFile, ModFile, ModFile> get copyWith =>
      _ModFileCopyWithImpl<ModFile, ModFile>(
        this as ModFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModFileMapper.ensureInitialized().stringifyValue(this as ModFile);
  }

  @override
  bool operator ==(Object other) {
    return ModFileMapper.ensureInitialized().equalsValue(
      this as ModFile,
      other,
    );
  }

  @override
  int get hashCode {
    return ModFileMapper.ensureInitialized().hashValue(this as ModFile);
  }
}

extension ModFileValueCopy<$R, $Out> on ObjectCopyWith<$R, ModFile, $Out> {
  ModFileCopyWith<$R, ModFile, $Out> get $asModFile =>
      $base.as((v, t, t2) => _ModFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModFileCopyWith<$R, $In extends ModFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get gameVersions;
  ListCopyWith<$R, FileHash, FileHashCopyWith<$R, FileHash, FileHash>>
  get hashes;
  ListCopyWith<
    $R,
    FileRelation,
    FileRelationCopyWith<$R, FileRelation, FileRelation>
  >
  get dependencies;
  $R call({
    int? id,
    int? modId,
    String? displayName,
    String? fileName,
    int? releaseType,
    String? fileDate,
    List<String>? gameVersions,
    List<FileHash>? hashes,
    List<FileRelation>? dependencies,
    String? downloadUrl,
  });
  ModFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModFile, $Out>
    implements ModFileCopyWith<$R, ModFile, $Out> {
  _ModFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModFile> $mapper =
      ModFileMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get gameVersions => ListCopyWith(
    $value.gameVersions,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(gameVersions: v),
  );
  @override
  ListCopyWith<$R, FileHash, FileHashCopyWith<$R, FileHash, FileHash>>
  get hashes => ListCopyWith(
    $value.hashes,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(hashes: v),
  );
  @override
  ListCopyWith<
    $R,
    FileRelation,
    FileRelationCopyWith<$R, FileRelation, FileRelation>
  >
  get dependencies => ListCopyWith(
    $value.dependencies,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(dependencies: v),
  );
  @override
  $R call({
    int? id,
    int? modId,
    String? displayName,
    String? fileName,
    int? releaseType,
    String? fileDate,
    List<String>? gameVersions,
    List<FileHash>? hashes,
    List<FileRelation>? dependencies,
    Object? downloadUrl = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (modId != null) #modId: modId,
      if (displayName != null) #displayName: displayName,
      if (fileName != null) #fileName: fileName,
      if (releaseType != null) #releaseType: releaseType,
      if (fileDate != null) #fileDate: fileDate,
      if (gameVersions != null) #gameVersions: gameVersions,
      if (hashes != null) #hashes: hashes,
      if (dependencies != null) #dependencies: dependencies,
      if (downloadUrl != $none) #downloadUrl: downloadUrl,
    }),
  );
  @override
  ModFile $make(CopyWithData data) => ModFile(
    id: data.get(#id, or: $value.id),
    modId: data.get(#modId, or: $value.modId),
    displayName: data.get(#displayName, or: $value.displayName),
    fileName: data.get(#fileName, or: $value.fileName),
    releaseType: data.get(#releaseType, or: $value.releaseType),
    fileDate: data.get(#fileDate, or: $value.fileDate),
    gameVersions: data.get(#gameVersions, or: $value.gameVersions),
    hashes: data.get(#hashes, or: $value.hashes),
    dependencies: data.get(#dependencies, or: $value.dependencies),
    downloadUrl: data.get(#downloadUrl, or: $value.downloadUrl),
  );

  @override
  ModFileCopyWith<$R2, ModFile, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ModFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

