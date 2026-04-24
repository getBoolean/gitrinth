// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'mrpack_index.dart';

class MrpackIndexMapper extends ClassMapperBase<MrpackIndex> {
  MrpackIndexMapper._();

  static MrpackIndexMapper? _instance;
  static MrpackIndexMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MrpackIndexMapper._());
      MrpackFileMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'MrpackIndex';

  static String _$game(MrpackIndex v) => v.game;
  static const Field<MrpackIndex, String> _f$game = Field(
    'game',
    _$game,
    opt: true,
    def: 'minecraft',
  );
  static int _$formatVersion(MrpackIndex v) => v.formatVersion;
  static const Field<MrpackIndex, int> _f$formatVersion = Field(
    'formatVersion',
    _$formatVersion,
    opt: true,
    def: 1,
  );
  static String _$versionId(MrpackIndex v) => v.versionId;
  static const Field<MrpackIndex, String> _f$versionId = Field(
    'versionId',
    _$versionId,
  );
  static String _$name(MrpackIndex v) => v.name;
  static const Field<MrpackIndex, String> _f$name = Field('name', _$name);
  static String _$summary(MrpackIndex v) => v.summary;
  static const Field<MrpackIndex, String> _f$summary = Field(
    'summary',
    _$summary,
  );
  static List<MrpackFile> _$files(MrpackIndex v) => v.files;
  static const Field<MrpackIndex, List<MrpackFile>> _f$files = Field(
    'files',
    _$files,
  );
  static Map<String, String> _$dependencies(MrpackIndex v) => v.dependencies;
  static const Field<MrpackIndex, Map<String, String>> _f$dependencies = Field(
    'dependencies',
    _$dependencies,
  );

  @override
  final MappableFields<MrpackIndex> fields = const {
    #game: _f$game,
    #formatVersion: _f$formatVersion,
    #versionId: _f$versionId,
    #name: _f$name,
    #summary: _f$summary,
    #files: _f$files,
    #dependencies: _f$dependencies,
  };

  static MrpackIndex _instantiate(DecodingData data) {
    return MrpackIndex(
      game: data.dec(_f$game),
      formatVersion: data.dec(_f$formatVersion),
      versionId: data.dec(_f$versionId),
      name: data.dec(_f$name),
      summary: data.dec(_f$summary),
      files: data.dec(_f$files),
      dependencies: data.dec(_f$dependencies),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MrpackIndex fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MrpackIndex>(map);
  }

  static MrpackIndex fromJson(String json) {
    return ensureInitialized().decodeJson<MrpackIndex>(json);
  }
}

mixin MrpackIndexMappable {
  String toJson() {
    return MrpackIndexMapper.ensureInitialized().encodeJson<MrpackIndex>(
      this as MrpackIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return MrpackIndexMapper.ensureInitialized().encodeMap<MrpackIndex>(
      this as MrpackIndex,
    );
  }

  MrpackIndexCopyWith<MrpackIndex, MrpackIndex, MrpackIndex> get copyWith =>
      _MrpackIndexCopyWithImpl<MrpackIndex, MrpackIndex>(
        this as MrpackIndex,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MrpackIndexMapper.ensureInitialized().stringifyValue(
      this as MrpackIndex,
    );
  }

  @override
  bool operator ==(Object other) {
    return MrpackIndexMapper.ensureInitialized().equalsValue(
      this as MrpackIndex,
      other,
    );
  }

  @override
  int get hashCode {
    return MrpackIndexMapper.ensureInitialized().hashValue(this as MrpackIndex);
  }
}

extension MrpackIndexValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MrpackIndex, $Out> {
  MrpackIndexCopyWith<$R, MrpackIndex, $Out> get $asMrpackIndex =>
      $base.as((v, t, t2) => _MrpackIndexCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MrpackIndexCopyWith<$R, $In extends MrpackIndex, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, MrpackFile, MrpackFileCopyWith<$R, MrpackFile, MrpackFile>>
  get files;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get dependencies;
  $R call({
    String? game,
    int? formatVersion,
    String? versionId,
    String? name,
    String? summary,
    List<MrpackFile>? files,
    Map<String, String>? dependencies,
  });
  MrpackIndexCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MrpackIndexCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MrpackIndex, $Out>
    implements MrpackIndexCopyWith<$R, MrpackIndex, $Out> {
  _MrpackIndexCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MrpackIndex> $mapper =
      MrpackIndexMapper.ensureInitialized();
  @override
  ListCopyWith<$R, MrpackFile, MrpackFileCopyWith<$R, MrpackFile, MrpackFile>>
  get files => ListCopyWith(
    $value.files,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(files: v),
  );
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get dependencies => MapCopyWith(
    $value.dependencies,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(dependencies: v),
  );
  @override
  $R call({
    String? game,
    int? formatVersion,
    String? versionId,
    String? name,
    String? summary,
    List<MrpackFile>? files,
    Map<String, String>? dependencies,
  }) => $apply(
    FieldCopyWithData({
      if (game != null) #game: game,
      if (formatVersion != null) #formatVersion: formatVersion,
      if (versionId != null) #versionId: versionId,
      if (name != null) #name: name,
      if (summary != null) #summary: summary,
      if (files != null) #files: files,
      if (dependencies != null) #dependencies: dependencies,
    }),
  );
  @override
  MrpackIndex $make(CopyWithData data) => MrpackIndex(
    game: data.get(#game, or: $value.game),
    formatVersion: data.get(#formatVersion, or: $value.formatVersion),
    versionId: data.get(#versionId, or: $value.versionId),
    name: data.get(#name, or: $value.name),
    summary: data.get(#summary, or: $value.summary),
    files: data.get(#files, or: $value.files),
    dependencies: data.get(#dependencies, or: $value.dependencies),
  );

  @override
  MrpackIndexCopyWith<$R2, MrpackIndex, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MrpackIndexCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class MrpackFileMapper extends ClassMapperBase<MrpackFile> {
  MrpackFileMapper._();

  static MrpackFileMapper? _instance;
  static MrpackFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MrpackFileMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'MrpackFile';

  static String _$path(MrpackFile v) => v.path;
  static const Field<MrpackFile, String> _f$path = Field('path', _$path);
  static Map<String, String> _$hashes(MrpackFile v) => v.hashes;
  static const Field<MrpackFile, Map<String, String>> _f$hashes = Field(
    'hashes',
    _$hashes,
  );
  static Map<String, String> _$env(MrpackFile v) => v.env;
  static const Field<MrpackFile, Map<String, String>> _f$env = Field(
    'env',
    _$env,
  );
  static List<String> _$downloads(MrpackFile v) => v.downloads;
  static const Field<MrpackFile, List<String>> _f$downloads = Field(
    'downloads',
    _$downloads,
  );
  static int _$fileSize(MrpackFile v) => v.fileSize;
  static const Field<MrpackFile, int> _f$fileSize = Field(
    'fileSize',
    _$fileSize,
  );

  @override
  final MappableFields<MrpackFile> fields = const {
    #path: _f$path,
    #hashes: _f$hashes,
    #env: _f$env,
    #downloads: _f$downloads,
    #fileSize: _f$fileSize,
  };

  static MrpackFile _instantiate(DecodingData data) {
    return MrpackFile(
      path: data.dec(_f$path),
      hashes: data.dec(_f$hashes),
      env: data.dec(_f$env),
      downloads: data.dec(_f$downloads),
      fileSize: data.dec(_f$fileSize),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MrpackFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MrpackFile>(map);
  }

  static MrpackFile fromJson(String json) {
    return ensureInitialized().decodeJson<MrpackFile>(json);
  }
}

mixin MrpackFileMappable {
  String toJson() {
    return MrpackFileMapper.ensureInitialized().encodeJson<MrpackFile>(
      this as MrpackFile,
    );
  }

  Map<String, dynamic> toMap() {
    return MrpackFileMapper.ensureInitialized().encodeMap<MrpackFile>(
      this as MrpackFile,
    );
  }

  MrpackFileCopyWith<MrpackFile, MrpackFile, MrpackFile> get copyWith =>
      _MrpackFileCopyWithImpl<MrpackFile, MrpackFile>(
        this as MrpackFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MrpackFileMapper.ensureInitialized().stringifyValue(
      this as MrpackFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return MrpackFileMapper.ensureInitialized().equalsValue(
      this as MrpackFile,
      other,
    );
  }

  @override
  int get hashCode {
    return MrpackFileMapper.ensureInitialized().hashValue(this as MrpackFile);
  }
}

extension MrpackFileValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MrpackFile, $Out> {
  MrpackFileCopyWith<$R, MrpackFile, $Out> get $asMrpackFile =>
      $base.as((v, t, t2) => _MrpackFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MrpackFileCopyWith<$R, $In extends MrpackFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get hashes;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>> get env;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get downloads;
  $R call({
    String? path,
    Map<String, String>? hashes,
    Map<String, String>? env,
    List<String>? downloads,
    int? fileSize,
  });
  MrpackFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MrpackFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MrpackFile, $Out>
    implements MrpackFileCopyWith<$R, MrpackFile, $Out> {
  _MrpackFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MrpackFile> $mapper =
      MrpackFileMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get hashes => MapCopyWith(
    $value.hashes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(hashes: v),
  );
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>> get env =>
      MapCopyWith(
        $value.env,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(env: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get downloads =>
      ListCopyWith(
        $value.downloads,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(downloads: v),
      );
  @override
  $R call({
    String? path,
    Map<String, String>? hashes,
    Map<String, String>? env,
    List<String>? downloads,
    int? fileSize,
  }) => $apply(
    FieldCopyWithData({
      if (path != null) #path: path,
      if (hashes != null) #hashes: hashes,
      if (env != null) #env: env,
      if (downloads != null) #downloads: downloads,
      if (fileSize != null) #fileSize: fileSize,
    }),
  );
  @override
  MrpackFile $make(CopyWithData data) => MrpackFile(
    path: data.get(#path, or: $value.path),
    hashes: data.get(#hashes, or: $value.hashes),
    env: data.get(#env, or: $value.env),
    downloads: data.get(#downloads, or: $value.downloads),
    fileSize: data.get(#fileSize, or: $value.fileSize),
  );

  @override
  MrpackFileCopyWith<$R2, MrpackFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MrpackFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

