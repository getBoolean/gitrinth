// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'mods_lock.dart';

class LockedSourceKindMapper extends EnumMapper<LockedSourceKind> {
  LockedSourceKindMapper._();

  static LockedSourceKindMapper? _instance;
  static LockedSourceKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LockedSourceKindMapper._());
    }
    return _instance!;
  }

  static LockedSourceKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  LockedSourceKind decode(dynamic value) {
    switch (value) {
      case r'modrinth':
        return LockedSourceKind.modrinth;
      case r'url':
        return LockedSourceKind.url;
      case r'path':
        return LockedSourceKind.path;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(LockedSourceKind self) {
    switch (self) {
      case LockedSourceKind.modrinth:
        return r'modrinth';
      case LockedSourceKind.url:
        return r'url';
      case LockedSourceKind.path:
        return r'path';
    }
  }
}

extension LockedSourceKindMapperExtension on LockedSourceKind {
  String toValue() {
    LockedSourceKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<LockedSourceKind>(this) as String;
  }
}

class LockedFileMapper extends ClassMapperBase<LockedFile> {
  LockedFileMapper._();

  static LockedFileMapper? _instance;
  static LockedFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LockedFileMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'LockedFile';

  static String _$name(LockedFile v) => v.name;
  static const Field<LockedFile, String> _f$name = Field('name', _$name);
  static String? _$url(LockedFile v) => v.url;
  static const Field<LockedFile, String> _f$url = Field(
    'url',
    _$url,
    opt: true,
  );
  static String? _$sha512(LockedFile v) => v.sha512;
  static const Field<LockedFile, String> _f$sha512 = Field(
    'sha512',
    _$sha512,
    opt: true,
  );
  static int? _$size(LockedFile v) => v.size;
  static const Field<LockedFile, int> _f$size = Field(
    'size',
    _$size,
    opt: true,
  );

  @override
  final MappableFields<LockedFile> fields = const {
    #name: _f$name,
    #url: _f$url,
    #sha512: _f$sha512,
    #size: _f$size,
  };

  static LockedFile _instantiate(DecodingData data) {
    return LockedFile(
      name: data.dec(_f$name),
      url: data.dec(_f$url),
      sha512: data.dec(_f$sha512),
      size: data.dec(_f$size),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LockedFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LockedFile>(map);
  }

  static LockedFile fromJson(String json) {
    return ensureInitialized().decodeJson<LockedFile>(json);
  }
}

mixin LockedFileMappable {
  String toJson() {
    return LockedFileMapper.ensureInitialized().encodeJson<LockedFile>(
      this as LockedFile,
    );
  }

  Map<String, dynamic> toMap() {
    return LockedFileMapper.ensureInitialized().encodeMap<LockedFile>(
      this as LockedFile,
    );
  }

  LockedFileCopyWith<LockedFile, LockedFile, LockedFile> get copyWith =>
      _LockedFileCopyWithImpl<LockedFile, LockedFile>(
        this as LockedFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LockedFileMapper.ensureInitialized().stringifyValue(
      this as LockedFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return LockedFileMapper.ensureInitialized().equalsValue(
      this as LockedFile,
      other,
    );
  }

  @override
  int get hashCode {
    return LockedFileMapper.ensureInitialized().hashValue(this as LockedFile);
  }
}

extension LockedFileValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LockedFile, $Out> {
  LockedFileCopyWith<$R, LockedFile, $Out> get $asLockedFile =>
      $base.as((v, t, t2) => _LockedFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LockedFileCopyWith<$R, $In extends LockedFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? name, String? url, String? sha512, int? size});
  LockedFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LockedFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LockedFile, $Out>
    implements LockedFileCopyWith<$R, LockedFile, $Out> {
  _LockedFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LockedFile> $mapper =
      LockedFileMapper.ensureInitialized();
  @override
  $R call({
    String? name,
    Object? url = $none,
    Object? sha512 = $none,
    Object? size = $none,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (url != $none) #url: url,
      if (sha512 != $none) #sha512: sha512,
      if (size != $none) #size: size,
    }),
  );
  @override
  LockedFile $make(CopyWithData data) => LockedFile(
    name: data.get(#name, or: $value.name),
    url: data.get(#url, or: $value.url),
    sha512: data.get(#sha512, or: $value.sha512),
    size: data.get(#size, or: $value.size),
  );

  @override
  LockedFileCopyWith<$R2, LockedFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LockedFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LockedEntryMapper extends ClassMapperBase<LockedEntry> {
  LockedEntryMapper._();

  static LockedEntryMapper? _instance;
  static LockedEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LockedEntryMapper._());
      LockedSourceKindMapper.ensureInitialized();
      LockedFileMapper.ensureInitialized();
      EnvironmentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LockedEntry';

  static String _$slug(LockedEntry v) => v.slug;
  static const Field<LockedEntry, String> _f$slug = Field('slug', _$slug);
  static LockedSourceKind _$sourceKind(LockedEntry v) => v.sourceKind;
  static const Field<LockedEntry, LockedSourceKind> _f$sourceKind = Field(
    'sourceKind',
    _$sourceKind,
  );
  static String? _$version(LockedEntry v) => v.version;
  static const Field<LockedEntry, String> _f$version = Field(
    'version',
    _$version,
    opt: true,
  );
  static String? _$projectId(LockedEntry v) => v.projectId;
  static const Field<LockedEntry, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    opt: true,
  );
  static String? _$versionId(LockedEntry v) => v.versionId;
  static const Field<LockedEntry, String> _f$versionId = Field(
    'versionId',
    _$versionId,
    opt: true,
  );
  static LockedFile? _$file(LockedEntry v) => v.file;
  static const Field<LockedEntry, LockedFile> _f$file = Field(
    'file',
    _$file,
    opt: true,
  );
  static String? _$path(LockedEntry v) => v.path;
  static const Field<LockedEntry, String> _f$path = Field(
    'path',
    _$path,
    opt: true,
  );
  static Environment _$env(LockedEntry v) => v.env;
  static const Field<LockedEntry, Environment> _f$env = Field(
    'env',
    _$env,
    opt: true,
    def: Environment.both,
  );
  static bool _$auto(LockedEntry v) => v.auto;
  static const Field<LockedEntry, bool> _f$auto = Field(
    'auto',
    _$auto,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<LockedEntry> fields = const {
    #slug: _f$slug,
    #sourceKind: _f$sourceKind,
    #version: _f$version,
    #projectId: _f$projectId,
    #versionId: _f$versionId,
    #file: _f$file,
    #path: _f$path,
    #env: _f$env,
    #auto: _f$auto,
  };

  static LockedEntry _instantiate(DecodingData data) {
    return LockedEntry(
      slug: data.dec(_f$slug),
      sourceKind: data.dec(_f$sourceKind),
      version: data.dec(_f$version),
      projectId: data.dec(_f$projectId),
      versionId: data.dec(_f$versionId),
      file: data.dec(_f$file),
      path: data.dec(_f$path),
      env: data.dec(_f$env),
      auto: data.dec(_f$auto),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LockedEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LockedEntry>(map);
  }

  static LockedEntry fromJson(String json) {
    return ensureInitialized().decodeJson<LockedEntry>(json);
  }
}

mixin LockedEntryMappable {
  String toJson() {
    return LockedEntryMapper.ensureInitialized().encodeJson<LockedEntry>(
      this as LockedEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return LockedEntryMapper.ensureInitialized().encodeMap<LockedEntry>(
      this as LockedEntry,
    );
  }

  LockedEntryCopyWith<LockedEntry, LockedEntry, LockedEntry> get copyWith =>
      _LockedEntryCopyWithImpl<LockedEntry, LockedEntry>(
        this as LockedEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LockedEntryMapper.ensureInitialized().stringifyValue(
      this as LockedEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return LockedEntryMapper.ensureInitialized().equalsValue(
      this as LockedEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return LockedEntryMapper.ensureInitialized().hashValue(this as LockedEntry);
  }
}

extension LockedEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LockedEntry, $Out> {
  LockedEntryCopyWith<$R, LockedEntry, $Out> get $asLockedEntry =>
      $base.as((v, t, t2) => _LockedEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LockedEntryCopyWith<$R, $In extends LockedEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  LockedFileCopyWith<$R, LockedFile, LockedFile>? get file;
  $R call({
    String? slug,
    LockedSourceKind? sourceKind,
    String? version,
    String? projectId,
    String? versionId,
    LockedFile? file,
    String? path,
    Environment? env,
    bool? auto,
  });
  LockedEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LockedEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LockedEntry, $Out>
    implements LockedEntryCopyWith<$R, LockedEntry, $Out> {
  _LockedEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LockedEntry> $mapper =
      LockedEntryMapper.ensureInitialized();
  @override
  LockedFileCopyWith<$R, LockedFile, LockedFile>? get file =>
      $value.file?.copyWith.$chain((v) => call(file: v));
  @override
  $R call({
    String? slug,
    LockedSourceKind? sourceKind,
    Object? version = $none,
    Object? projectId = $none,
    Object? versionId = $none,
    Object? file = $none,
    Object? path = $none,
    Environment? env,
    bool? auto,
  }) => $apply(
    FieldCopyWithData({
      if (slug != null) #slug: slug,
      if (sourceKind != null) #sourceKind: sourceKind,
      if (version != $none) #version: version,
      if (projectId != $none) #projectId: projectId,
      if (versionId != $none) #versionId: versionId,
      if (file != $none) #file: file,
      if (path != $none) #path: path,
      if (env != null) #env: env,
      if (auto != null) #auto: auto,
    }),
  );
  @override
  LockedEntry $make(CopyWithData data) => LockedEntry(
    slug: data.get(#slug, or: $value.slug),
    sourceKind: data.get(#sourceKind, or: $value.sourceKind),
    version: data.get(#version, or: $value.version),
    projectId: data.get(#projectId, or: $value.projectId),
    versionId: data.get(#versionId, or: $value.versionId),
    file: data.get(#file, or: $value.file),
    path: data.get(#path, or: $value.path),
    env: data.get(#env, or: $value.env),
    auto: data.get(#auto, or: $value.auto),
  );

  @override
  LockedEntryCopyWith<$R2, LockedEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LockedEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModsLockMapper extends ClassMapperBase<ModsLock> {
  ModsLockMapper._();

  static ModsLockMapper? _instance;
  static ModsLockMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModsLockMapper._());
      LoaderMapper.ensureInitialized();
      LockedEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModsLock';

  static String _$gitrinthVersion(ModsLock v) => v.gitrinthVersion;
  static const Field<ModsLock, String> _f$gitrinthVersion = Field(
    'gitrinthVersion',
    _$gitrinthVersion,
  );
  static Loader _$loader(ModsLock v) => v.loader;
  static const Field<ModsLock, Loader> _f$loader = Field('loader', _$loader);
  static String _$mcVersion(ModsLock v) => v.mcVersion;
  static const Field<ModsLock, String> _f$mcVersion = Field(
    'mcVersion',
    _$mcVersion,
  );
  static Map<String, LockedEntry> _$mods(ModsLock v) => v.mods;
  static const Field<ModsLock, Map<String, LockedEntry>> _f$mods = Field(
    'mods',
    _$mods,
    opt: true,
    def: const {},
  );
  static Map<String, LockedEntry> _$resourcePacks(ModsLock v) =>
      v.resourcePacks;
  static const Field<ModsLock, Map<String, LockedEntry>> _f$resourcePacks =
      Field('resourcePacks', _$resourcePacks, opt: true, def: const {});
  static Map<String, LockedEntry> _$dataPacks(ModsLock v) => v.dataPacks;
  static const Field<ModsLock, Map<String, LockedEntry>> _f$dataPacks = Field(
    'dataPacks',
    _$dataPacks,
    opt: true,
    def: const {},
  );
  static Map<String, LockedEntry> _$shaders(ModsLock v) => v.shaders;
  static const Field<ModsLock, Map<String, LockedEntry>> _f$shaders = Field(
    'shaders',
    _$shaders,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<ModsLock> fields = const {
    #gitrinthVersion: _f$gitrinthVersion,
    #loader: _f$loader,
    #mcVersion: _f$mcVersion,
    #mods: _f$mods,
    #resourcePacks: _f$resourcePacks,
    #dataPacks: _f$dataPacks,
    #shaders: _f$shaders,
  };

  static ModsLock _instantiate(DecodingData data) {
    return ModsLock(
      gitrinthVersion: data.dec(_f$gitrinthVersion),
      loader: data.dec(_f$loader),
      mcVersion: data.dec(_f$mcVersion),
      mods: data.dec(_f$mods),
      resourcePacks: data.dec(_f$resourcePacks),
      dataPacks: data.dec(_f$dataPacks),
      shaders: data.dec(_f$shaders),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModsLock fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModsLock>(map);
  }

  static ModsLock fromJson(String json) {
    return ensureInitialized().decodeJson<ModsLock>(json);
  }
}

mixin ModsLockMappable {
  String toJson() {
    return ModsLockMapper.ensureInitialized().encodeJson<ModsLock>(
      this as ModsLock,
    );
  }

  Map<String, dynamic> toMap() {
    return ModsLockMapper.ensureInitialized().encodeMap<ModsLock>(
      this as ModsLock,
    );
  }

  ModsLockCopyWith<ModsLock, ModsLock, ModsLock> get copyWith =>
      _ModsLockCopyWithImpl<ModsLock, ModsLock>(
        this as ModsLock,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModsLockMapper.ensureInitialized().stringifyValue(this as ModsLock);
  }

  @override
  bool operator ==(Object other) {
    return ModsLockMapper.ensureInitialized().equalsValue(
      this as ModsLock,
      other,
    );
  }

  @override
  int get hashCode {
    return ModsLockMapper.ensureInitialized().hashValue(this as ModsLock);
  }
}

extension ModsLockValueCopy<$R, $Out> on ObjectCopyWith<$R, ModsLock, $Out> {
  ModsLockCopyWith<$R, ModsLock, $Out> get $asModsLock =>
      $base.as((v, t, t2) => _ModsLockCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModsLockCopyWith<$R, $In extends ModsLock, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get mods;
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get resourcePacks;
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get dataPacks;
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get shaders;
  $R call({
    String? gitrinthVersion,
    Loader? loader,
    String? mcVersion,
    Map<String, LockedEntry>? mods,
    Map<String, LockedEntry>? resourcePacks,
    Map<String, LockedEntry>? dataPacks,
    Map<String, LockedEntry>? shaders,
  });
  ModsLockCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModsLockCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModsLock, $Out>
    implements ModsLockCopyWith<$R, ModsLock, $Out> {
  _ModsLockCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModsLock> $mapper =
      ModsLockMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get mods => MapCopyWith(
    $value.mods,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(mods: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get resourcePacks => MapCopyWith(
    $value.resourcePacks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(resourcePacks: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get dataPacks => MapCopyWith(
    $value.dataPacks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(dataPacks: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    LockedEntry,
    LockedEntryCopyWith<$R, LockedEntry, LockedEntry>
  >
  get shaders => MapCopyWith(
    $value.shaders,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(shaders: v),
  );
  @override
  $R call({
    String? gitrinthVersion,
    Loader? loader,
    String? mcVersion,
    Map<String, LockedEntry>? mods,
    Map<String, LockedEntry>? resourcePacks,
    Map<String, LockedEntry>? dataPacks,
    Map<String, LockedEntry>? shaders,
  }) => $apply(
    FieldCopyWithData({
      if (gitrinthVersion != null) #gitrinthVersion: gitrinthVersion,
      if (loader != null) #loader: loader,
      if (mcVersion != null) #mcVersion: mcVersion,
      if (mods != null) #mods: mods,
      if (resourcePacks != null) #resourcePacks: resourcePacks,
      if (dataPacks != null) #dataPacks: dataPacks,
      if (shaders != null) #shaders: shaders,
    }),
  );
  @override
  ModsLock $make(CopyWithData data) => ModsLock(
    gitrinthVersion: data.get(#gitrinthVersion, or: $value.gitrinthVersion),
    loader: data.get(#loader, or: $value.loader),
    mcVersion: data.get(#mcVersion, or: $value.mcVersion),
    mods: data.get(#mods, or: $value.mods),
    resourcePacks: data.get(#resourcePacks, or: $value.resourcePacks),
    dataPacks: data.get(#dataPacks, or: $value.dataPacks),
    shaders: data.get(#shaders, or: $value.shaders),
  );

  @override
  ModsLockCopyWith<$R2, ModsLock, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModsLockCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

