// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'result.dart';

class ResolvedEntryMapper extends ClassMapperBase<ResolvedEntry> {
  ResolvedEntryMapper._();

  static ResolvedEntryMapper? _instance;
  static ResolvedEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ResolvedEntryMapper._());
      SectionMapper.ensureInitialized();
      SideEnvMapper.ensureInitialized();
      LockedDependencyKindMapper.ensureInitialized();
      modrinth.VersionMapper.ensureInitialized();
      VersionFileMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ResolvedEntry';

  static String _$slug(ResolvedEntry v) => v.slug;
  static const Field<ResolvedEntry, String> _f$slug = Field('slug', _$slug);
  static Section _$section(ResolvedEntry v) => v.section;
  static const Field<ResolvedEntry, Section> _f$section = Field(
    'section',
    _$section,
  );
  static SideEnv _$client(ResolvedEntry v) => v.client;
  static const Field<ResolvedEntry, SideEnv> _f$client = Field(
    'client',
    _$client,
  );
  static SideEnv _$server(ResolvedEntry v) => v.server;
  static const Field<ResolvedEntry, SideEnv> _f$server = Field(
    'server',
    _$server,
  );
  static LockedDependencyKind _$dependency(ResolvedEntry v) => v.dependency;
  static const Field<ResolvedEntry, LockedDependencyKind> _f$dependency = Field(
    'dependency',
    _$dependency,
  );
  static modrinth.Version _$version(ResolvedEntry v) => v.version;
  static const Field<ResolvedEntry, modrinth.Version> _f$version = Field(
    'version',
    _$version,
  );
  static VersionFile _$file(ResolvedEntry v) => v.file;
  static const Field<ResolvedEntry, VersionFile> _f$file = Field(
    'file',
    _$file,
  );

  @override
  final MappableFields<ResolvedEntry> fields = const {
    #slug: _f$slug,
    #section: _f$section,
    #client: _f$client,
    #server: _f$server,
    #dependency: _f$dependency,
    #version: _f$version,
    #file: _f$file,
  };

  static ResolvedEntry _instantiate(DecodingData data) {
    return ResolvedEntry(
      slug: data.dec(_f$slug),
      section: data.dec(_f$section),
      client: data.dec(_f$client),
      server: data.dec(_f$server),
      dependency: data.dec(_f$dependency),
      version: data.dec(_f$version),
      file: data.dec(_f$file),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ResolvedEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResolvedEntry>(map);
  }

  static ResolvedEntry fromJson(String json) {
    return ensureInitialized().decodeJson<ResolvedEntry>(json);
  }
}

mixin ResolvedEntryMappable {
  String toJson() {
    return ResolvedEntryMapper.ensureInitialized().encodeJson<ResolvedEntry>(
      this as ResolvedEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return ResolvedEntryMapper.ensureInitialized().encodeMap<ResolvedEntry>(
      this as ResolvedEntry,
    );
  }

  ResolvedEntryCopyWith<ResolvedEntry, ResolvedEntry, ResolvedEntry>
  get copyWith => _ResolvedEntryCopyWithImpl<ResolvedEntry, ResolvedEntry>(
    this as ResolvedEntry,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return ResolvedEntryMapper.ensureInitialized().stringifyValue(
      this as ResolvedEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return ResolvedEntryMapper.ensureInitialized().equalsValue(
      this as ResolvedEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return ResolvedEntryMapper.ensureInitialized().hashValue(
      this as ResolvedEntry,
    );
  }
}

extension ResolvedEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ResolvedEntry, $Out> {
  ResolvedEntryCopyWith<$R, ResolvedEntry, $Out> get $asResolvedEntry =>
      $base.as((v, t, t2) => _ResolvedEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ResolvedEntryCopyWith<$R, $In extends ResolvedEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  modrinth.VersionCopyWith<$R, modrinth.Version, modrinth.Version> get version;
  VersionFileCopyWith<$R, VersionFile, VersionFile> get file;
  $R call({
    String? slug,
    Section? section,
    SideEnv? client,
    SideEnv? server,
    LockedDependencyKind? dependency,
    modrinth.Version? version,
    VersionFile? file,
  });
  ResolvedEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ResolvedEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ResolvedEntry, $Out>
    implements ResolvedEntryCopyWith<$R, ResolvedEntry, $Out> {
  _ResolvedEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ResolvedEntry> $mapper =
      ResolvedEntryMapper.ensureInitialized();
  @override
  modrinth.VersionCopyWith<$R, modrinth.Version, modrinth.Version>
  get version => $value.version.copyWith.$chain((v) => call(version: v));
  @override
  VersionFileCopyWith<$R, VersionFile, VersionFile> get file =>
      $value.file.copyWith.$chain((v) => call(file: v));
  @override
  $R call({
    String? slug,
    Section? section,
    SideEnv? client,
    SideEnv? server,
    LockedDependencyKind? dependency,
    modrinth.Version? version,
    VersionFile? file,
  }) => $apply(
    FieldCopyWithData({
      if (slug != null) #slug: slug,
      if (section != null) #section: section,
      if (client != null) #client: client,
      if (server != null) #server: server,
      if (dependency != null) #dependency: dependency,
      if (version != null) #version: version,
      if (file != null) #file: file,
    }),
  );
  @override
  ResolvedEntry $make(CopyWithData data) => ResolvedEntry(
    slug: data.get(#slug, or: $value.slug),
    section: data.get(#section, or: $value.section),
    client: data.get(#client, or: $value.client),
    server: data.get(#server, or: $value.server),
    dependency: data.get(#dependency, or: $value.dependency),
    version: data.get(#version, or: $value.version),
    file: data.get(#file, or: $value.file),
  );

  @override
  ResolvedEntryCopyWith<$R2, ResolvedEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ResolvedEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ResolutionResultMapper extends ClassMapperBase<ResolutionResult> {
  ResolutionResultMapper._();

  static ResolutionResultMapper? _instance;
  static ResolutionResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ResolutionResultMapper._());
      ResolvedEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ResolutionResult';

  static List<ResolvedEntry> _$entries(ResolutionResult v) => v.entries;
  static const Field<ResolutionResult, List<ResolvedEntry>> _f$entries = Field(
    'entries',
    _$entries,
  );

  @override
  final MappableFields<ResolutionResult> fields = const {#entries: _f$entries};

  static ResolutionResult _instantiate(DecodingData data) {
    return ResolutionResult(data.dec(_f$entries));
  }

  @override
  final Function instantiate = _instantiate;

  static ResolutionResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResolutionResult>(map);
  }

  static ResolutionResult fromJson(String json) {
    return ensureInitialized().decodeJson<ResolutionResult>(json);
  }
}

mixin ResolutionResultMappable {
  String toJson() {
    return ResolutionResultMapper.ensureInitialized()
        .encodeJson<ResolutionResult>(this as ResolutionResult);
  }

  Map<String, dynamic> toMap() {
    return ResolutionResultMapper.ensureInitialized()
        .encodeMap<ResolutionResult>(this as ResolutionResult);
  }

  ResolutionResultCopyWith<ResolutionResult, ResolutionResult, ResolutionResult>
  get copyWith =>
      _ResolutionResultCopyWithImpl<ResolutionResult, ResolutionResult>(
        this as ResolutionResult,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ResolutionResultMapper.ensureInitialized().stringifyValue(
      this as ResolutionResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return ResolutionResultMapper.ensureInitialized().equalsValue(
      this as ResolutionResult,
      other,
    );
  }

  @override
  int get hashCode {
    return ResolutionResultMapper.ensureInitialized().hashValue(
      this as ResolutionResult,
    );
  }
}

extension ResolutionResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ResolutionResult, $Out> {
  ResolutionResultCopyWith<$R, ResolutionResult, $Out>
  get $asResolutionResult =>
      $base.as((v, t, t2) => _ResolutionResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ResolutionResultCopyWith<$R, $In extends ResolutionResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    ResolvedEntry,
    ResolvedEntryCopyWith<$R, ResolvedEntry, ResolvedEntry>
  >
  get entries;
  $R call({List<ResolvedEntry>? entries});
  ResolutionResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ResolutionResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ResolutionResult, $Out>
    implements ResolutionResultCopyWith<$R, ResolutionResult, $Out> {
  _ResolutionResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ResolutionResult> $mapper =
      ResolutionResultMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    ResolvedEntry,
    ResolvedEntryCopyWith<$R, ResolvedEntry, ResolvedEntry>
  >
  get entries => ListCopyWith(
    $value.entries,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(entries: v),
  );
  @override
  $R call({List<ResolvedEntry>? entries}) =>
      $apply(FieldCopyWithData({if (entries != null) #entries: entries}));
  @override
  ResolutionResult $make(CopyWithData data) =>
      ResolutionResult(data.get(#entries, or: $value.entries));

  @override
  ResolutionResultCopyWith<$R2, ResolutionResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ResolutionResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

