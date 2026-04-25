// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'build_state.dart';

class LedgerEnvMapper extends EnumMapper<LedgerEnv> {
  LedgerEnvMapper._();

  static LedgerEnvMapper? _instance;
  static LedgerEnvMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LedgerEnvMapper._());
    }
    return _instance!;
  }

  static LedgerEnv fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  LedgerEnv decode(dynamic value) {
    switch (value) {
      case r'client':
        return LedgerEnv.client;
      case r'server':
        return LedgerEnv.server;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(LedgerEnv self) {
    switch (self) {
      case LedgerEnv.client:
        return r'client';
      case LedgerEnv.server:
        return r'server';
    }
  }
}

extension LedgerEnvMapperExtension on LedgerEnv {
  String toValue() {
    LedgerEnvMapper.ensureInitialized();
    return MapperContainer.globals.toValue<LedgerEnv>(this) as String;
  }
}

class LedgerSourceMapper extends ClassMapperBase<LedgerSource> {
  LedgerSourceMapper._();

  static LedgerSourceMapper? _instance;
  static LedgerSourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LedgerSourceMapper._());
      LedgerModSourceMapper.ensureInitialized();
      LedgerFileSourceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LedgerSource';

  @override
  final MappableFields<LedgerSource> fields = const {};

  static LedgerSource _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'LedgerSource',
      'kind',
      '${data.value['kind']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LedgerSource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LedgerSource>(map);
  }

  static LedgerSource fromJson(String json) {
    return ensureInitialized().decodeJson<LedgerSource>(json);
  }
}

mixin LedgerSourceMappable {
  String toJson();
  Map<String, dynamic> toMap();
  LedgerSourceCopyWith<LedgerSource, LedgerSource, LedgerSource> get copyWith;
}

abstract class LedgerSourceCopyWith<$R, $In extends LedgerSource, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call();
  LedgerSourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class LedgerModSourceMapper extends SubClassMapperBase<LedgerModSource> {
  LedgerModSourceMapper._();

  static LedgerModSourceMapper? _instance;
  static LedgerModSourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LedgerModSourceMapper._());
      LedgerSourceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'LedgerModSource';

  static String _$section(LedgerModSource v) => v.section;
  static const Field<LedgerModSource, String> _f$section = Field(
    'section',
    _$section,
  );
  static String _$slug(LedgerModSource v) => v.slug;
  static const Field<LedgerModSource, String> _f$slug = Field('slug', _$slug);
  static String? _$sha512(LedgerModSource v) => v.sha512;
  static const Field<LedgerModSource, String> _f$sha512 = Field(
    'sha512',
    _$sha512,
    opt: true,
  );

  @override
  final MappableFields<LedgerModSource> fields = const {
    #section: _f$section,
    #slug: _f$slug,
    #sha512: _f$sha512,
  };

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'mod-entry';
  @override
  late final ClassMapperBase superMapper =
      LedgerSourceMapper.ensureInitialized();

  static LedgerModSource _instantiate(DecodingData data) {
    return LedgerModSource(
      section: data.dec(_f$section),
      slug: data.dec(_f$slug),
      sha512: data.dec(_f$sha512),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LedgerModSource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LedgerModSource>(map);
  }

  static LedgerModSource fromJson(String json) {
    return ensureInitialized().decodeJson<LedgerModSource>(json);
  }
}

mixin LedgerModSourceMappable {
  String toJson() {
    return LedgerModSourceMapper.ensureInitialized()
        .encodeJson<LedgerModSource>(this as LedgerModSource);
  }

  Map<String, dynamic> toMap() {
    return LedgerModSourceMapper.ensureInitialized().encodeMap<LedgerModSource>(
      this as LedgerModSource,
    );
  }

  LedgerModSourceCopyWith<LedgerModSource, LedgerModSource, LedgerModSource>
  get copyWith =>
      _LedgerModSourceCopyWithImpl<LedgerModSource, LedgerModSource>(
        this as LedgerModSource,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LedgerModSourceMapper.ensureInitialized().stringifyValue(
      this as LedgerModSource,
    );
  }

  @override
  bool operator ==(Object other) {
    return LedgerModSourceMapper.ensureInitialized().equalsValue(
      this as LedgerModSource,
      other,
    );
  }

  @override
  int get hashCode {
    return LedgerModSourceMapper.ensureInitialized().hashValue(
      this as LedgerModSource,
    );
  }
}

extension LedgerModSourceValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LedgerModSource, $Out> {
  LedgerModSourceCopyWith<$R, LedgerModSource, $Out> get $asLedgerModSource =>
      $base.as((v, t, t2) => _LedgerModSourceCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LedgerModSourceCopyWith<$R, $In extends LedgerModSource, $Out>
    implements LedgerSourceCopyWith<$R, $In, $Out> {
  @override
  $R call({String? section, String? slug, String? sha512});
  LedgerModSourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LedgerModSourceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LedgerModSource, $Out>
    implements LedgerModSourceCopyWith<$R, LedgerModSource, $Out> {
  _LedgerModSourceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LedgerModSource> $mapper =
      LedgerModSourceMapper.ensureInitialized();
  @override
  $R call({String? section, String? slug, Object? sha512 = $none}) => $apply(
    FieldCopyWithData({
      if (section != null) #section: section,
      if (slug != null) #slug: slug,
      if (sha512 != $none) #sha512: sha512,
    }),
  );
  @override
  LedgerModSource $make(CopyWithData data) => LedgerModSource(
    section: data.get(#section, or: $value.section),
    slug: data.get(#slug, or: $value.slug),
    sha512: data.get(#sha512, or: $value.sha512),
  );

  @override
  LedgerModSourceCopyWith<$R2, LedgerModSource, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LedgerModSourceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LedgerFileSourceMapper extends SubClassMapperBase<LedgerFileSource> {
  LedgerFileSourceMapper._();

  static LedgerFileSourceMapper? _instance;
  static LedgerFileSourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LedgerFileSourceMapper._());
      LedgerSourceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'LedgerFileSource';

  static String _$key(LedgerFileSource v) => v.key;
  static const Field<LedgerFileSource, String> _f$key = Field('key', _$key);
  static bool _$preserve(LedgerFileSource v) => v.preserve;
  static const Field<LedgerFileSource, bool> _f$preserve = Field(
    'preserve',
    _$preserve,
  );
  static String _$sourcePath(LedgerFileSource v) => v.sourcePath;
  static const Field<LedgerFileSource, String> _f$sourcePath = Field(
    'sourcePath',
    _$sourcePath,
  );
  static String? _$sha512(LedgerFileSource v) => v.sha512;
  static const Field<LedgerFileSource, String> _f$sha512 = Field(
    'sha512',
    _$sha512,
    opt: true,
  );

  @override
  final MappableFields<LedgerFileSource> fields = const {
    #key: _f$key,
    #preserve: _f$preserve,
    #sourcePath: _f$sourcePath,
    #sha512: _f$sha512,
  };

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'file-entry';
  @override
  late final ClassMapperBase superMapper =
      LedgerSourceMapper.ensureInitialized();

  static LedgerFileSource _instantiate(DecodingData data) {
    return LedgerFileSource(
      key: data.dec(_f$key),
      preserve: data.dec(_f$preserve),
      sourcePath: data.dec(_f$sourcePath),
      sha512: data.dec(_f$sha512),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LedgerFileSource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LedgerFileSource>(map);
  }

  static LedgerFileSource fromJson(String json) {
    return ensureInitialized().decodeJson<LedgerFileSource>(json);
  }
}

mixin LedgerFileSourceMappable {
  String toJson() {
    return LedgerFileSourceMapper.ensureInitialized()
        .encodeJson<LedgerFileSource>(this as LedgerFileSource);
  }

  Map<String, dynamic> toMap() {
    return LedgerFileSourceMapper.ensureInitialized()
        .encodeMap<LedgerFileSource>(this as LedgerFileSource);
  }

  LedgerFileSourceCopyWith<LedgerFileSource, LedgerFileSource, LedgerFileSource>
  get copyWith =>
      _LedgerFileSourceCopyWithImpl<LedgerFileSource, LedgerFileSource>(
        this as LedgerFileSource,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LedgerFileSourceMapper.ensureInitialized().stringifyValue(
      this as LedgerFileSource,
    );
  }

  @override
  bool operator ==(Object other) {
    return LedgerFileSourceMapper.ensureInitialized().equalsValue(
      this as LedgerFileSource,
      other,
    );
  }

  @override
  int get hashCode {
    return LedgerFileSourceMapper.ensureInitialized().hashValue(
      this as LedgerFileSource,
    );
  }
}

extension LedgerFileSourceValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LedgerFileSource, $Out> {
  LedgerFileSourceCopyWith<$R, LedgerFileSource, $Out>
  get $asLedgerFileSource =>
      $base.as((v, t, t2) => _LedgerFileSourceCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LedgerFileSourceCopyWith<$R, $In extends LedgerFileSource, $Out>
    implements LedgerSourceCopyWith<$R, $In, $Out> {
  @override
  $R call({String? key, bool? preserve, String? sourcePath, String? sha512});
  LedgerFileSourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LedgerFileSourceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LedgerFileSource, $Out>
    implements LedgerFileSourceCopyWith<$R, LedgerFileSource, $Out> {
  _LedgerFileSourceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LedgerFileSource> $mapper =
      LedgerFileSourceMapper.ensureInitialized();
  @override
  $R call({
    String? key,
    bool? preserve,
    String? sourcePath,
    Object? sha512 = $none,
  }) => $apply(
    FieldCopyWithData({
      if (key != null) #key: key,
      if (preserve != null) #preserve: preserve,
      if (sourcePath != null) #sourcePath: sourcePath,
      if (sha512 != $none) #sha512: sha512,
    }),
  );
  @override
  LedgerFileSource $make(CopyWithData data) => LedgerFileSource(
    key: data.get(#key, or: $value.key),
    preserve: data.get(#preserve, or: $value.preserve),
    sourcePath: data.get(#sourcePath, or: $value.sourcePath),
    sha512: data.get(#sha512, or: $value.sha512),
  );

  @override
  LedgerFileSourceCopyWith<$R2, LedgerFileSource, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LedgerFileSourceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class BuildLedgerMapper extends ClassMapperBase<BuildLedger> {
  BuildLedgerMapper._();

  static BuildLedgerMapper? _instance;
  static BuildLedgerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BuildLedgerMapper._());
      LedgerEnvMapper.ensureInitialized();
      LedgerSourceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'BuildLedger';

  static String _$gitrinthVersion(BuildLedger v) => v.gitrinthVersion;
  static const Field<BuildLedger, String> _f$gitrinthVersion = Field(
    'gitrinthVersion',
    _$gitrinthVersion,
  );
  static LedgerEnv _$env(BuildLedger v) => v.env;
  static const Field<BuildLedger, LedgerEnv> _f$env = Field('env', _$env);
  static String _$generatedAt(BuildLedger v) => v.generatedAt;
  static const Field<BuildLedger, String> _f$generatedAt = Field(
    'generatedAt',
    _$generatedAt,
  );
  static Map<String, LedgerSource> _$files(BuildLedger v) => v.files;
  static const Field<BuildLedger, Map<String, LedgerSource>> _f$files = Field(
    'files',
    _$files,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<BuildLedger> fields = const {
    #gitrinthVersion: _f$gitrinthVersion,
    #env: _f$env,
    #generatedAt: _f$generatedAt,
    #files: _f$files,
  };

  static BuildLedger _instantiate(DecodingData data) {
    return BuildLedger(
      gitrinthVersion: data.dec(_f$gitrinthVersion),
      env: data.dec(_f$env),
      generatedAt: data.dec(_f$generatedAt),
      files: data.dec(_f$files),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BuildLedger fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BuildLedger>(map);
  }

  static BuildLedger fromJson(String json) {
    return ensureInitialized().decodeJson<BuildLedger>(json);
  }
}

mixin BuildLedgerMappable {
  String toJson() {
    return BuildLedgerMapper.ensureInitialized().encodeJson<BuildLedger>(
      this as BuildLedger,
    );
  }

  Map<String, dynamic> toMap() {
    return BuildLedgerMapper.ensureInitialized().encodeMap<BuildLedger>(
      this as BuildLedger,
    );
  }

  BuildLedgerCopyWith<BuildLedger, BuildLedger, BuildLedger> get copyWith =>
      _BuildLedgerCopyWithImpl<BuildLedger, BuildLedger>(
        this as BuildLedger,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return BuildLedgerMapper.ensureInitialized().stringifyValue(
      this as BuildLedger,
    );
  }

  @override
  bool operator ==(Object other) {
    return BuildLedgerMapper.ensureInitialized().equalsValue(
      this as BuildLedger,
      other,
    );
  }

  @override
  int get hashCode {
    return BuildLedgerMapper.ensureInitialized().hashValue(this as BuildLedger);
  }
}

extension BuildLedgerValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BuildLedger, $Out> {
  BuildLedgerCopyWith<$R, BuildLedger, $Out> get $asBuildLedger =>
      $base.as((v, t, t2) => _BuildLedgerCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BuildLedgerCopyWith<$R, $In extends BuildLedger, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    LedgerSource,
    LedgerSourceCopyWith<$R, LedgerSource, LedgerSource>
  >
  get files;
  $R call({
    String? gitrinthVersion,
    LedgerEnv? env,
    String? generatedAt,
    Map<String, LedgerSource>? files,
  });
  BuildLedgerCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _BuildLedgerCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BuildLedger, $Out>
    implements BuildLedgerCopyWith<$R, BuildLedger, $Out> {
  _BuildLedgerCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BuildLedger> $mapper =
      BuildLedgerMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    LedgerSource,
    LedgerSourceCopyWith<$R, LedgerSource, LedgerSource>
  >
  get files => MapCopyWith(
    $value.files,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(files: v),
  );
  @override
  $R call({
    String? gitrinthVersion,
    LedgerEnv? env,
    String? generatedAt,
    Map<String, LedgerSource>? files,
  }) => $apply(
    FieldCopyWithData({
      if (gitrinthVersion != null) #gitrinthVersion: gitrinthVersion,
      if (env != null) #env: env,
      if (generatedAt != null) #generatedAt: generatedAt,
      if (files != null) #files: files,
    }),
  );
  @override
  BuildLedger $make(CopyWithData data) => BuildLedger(
    gitrinthVersion: data.get(#gitrinthVersion, or: $value.gitrinthVersion),
    env: data.get(#env, or: $value.env),
    generatedAt: data.get(#generatedAt, or: $value.generatedAt),
    files: data.get(#files, or: $value.files),
  );

  @override
  BuildLedgerCopyWith<$R2, BuildLedger, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BuildLedgerCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

