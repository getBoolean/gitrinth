// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'cf_mod.dart';

class ModMapper extends ClassMapperBase<Mod> {
  ModMapper._();

  static ModMapper? _instance;
  static ModMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModMapper._());
      ModFileMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Mod';

  static int _$id(Mod v) => v.id;
  static const Field<Mod, int> _f$id = Field('id', _$id);
  static int _$gameId(Mod v) => v.gameId;
  static const Field<Mod, int> _f$gameId = Field('gameId', _$gameId);
  static String _$name(Mod v) => v.name;
  static const Field<Mod, String> _f$name = Field('name', _$name);
  static String _$slug(Mod v) => v.slug;
  static const Field<Mod, String> _f$slug = Field('slug', _$slug);
  static String? _$summary(Mod v) => v.summary;
  static const Field<Mod, String> _f$summary = Field(
    'summary',
    _$summary,
    opt: true,
  );
  static int _$classId(Mod v) => v.classId;
  static const Field<Mod, int> _f$classId = Field('classId', _$classId);
  static List<ModFile> _$latestFiles(Mod v) => v.latestFiles;
  static const Field<Mod, List<ModFile>> _f$latestFiles = Field(
    'latestFiles',
    _$latestFiles,
    opt: true,
    def: const [],
  );
  static bool _$allowModDistribution(Mod v) => v.allowModDistribution;
  static const Field<Mod, bool> _f$allowModDistribution = Field(
    'allowModDistribution',
    _$allowModDistribution,
    opt: true,
    def: true,
  );

  @override
  final MappableFields<Mod> fields = const {
    #id: _f$id,
    #gameId: _f$gameId,
    #name: _f$name,
    #slug: _f$slug,
    #summary: _f$summary,
    #classId: _f$classId,
    #latestFiles: _f$latestFiles,
    #allowModDistribution: _f$allowModDistribution,
  };

  static Mod _instantiate(DecodingData data) {
    return Mod(
      id: data.dec(_f$id),
      gameId: data.dec(_f$gameId),
      name: data.dec(_f$name),
      slug: data.dec(_f$slug),
      summary: data.dec(_f$summary),
      classId: data.dec(_f$classId),
      latestFiles: data.dec(_f$latestFiles),
      allowModDistribution: data.dec(_f$allowModDistribution),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Mod fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Mod>(map);
  }

  static Mod fromJson(String json) {
    return ensureInitialized().decodeJson<Mod>(json);
  }
}

mixin ModMappable {
  String toJson() {
    return ModMapper.ensureInitialized().encodeJson<Mod>(this as Mod);
  }

  Map<String, dynamic> toMap() {
    return ModMapper.ensureInitialized().encodeMap<Mod>(this as Mod);
  }

  ModCopyWith<Mod, Mod, Mod> get copyWith =>
      _ModCopyWithImpl<Mod, Mod>(this as Mod, $identity, $identity);
  @override
  String toString() {
    return ModMapper.ensureInitialized().stringifyValue(this as Mod);
  }

  @override
  bool operator ==(Object other) {
    return ModMapper.ensureInitialized().equalsValue(this as Mod, other);
  }

  @override
  int get hashCode {
    return ModMapper.ensureInitialized().hashValue(this as Mod);
  }
}

extension ModValueCopy<$R, $Out> on ObjectCopyWith<$R, Mod, $Out> {
  ModCopyWith<$R, Mod, $Out> get $asMod =>
      $base.as((v, t, t2) => _ModCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModCopyWith<$R, $In extends Mod, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, ModFile, ModFileCopyWith<$R, ModFile, ModFile>>
  get latestFiles;
  $R call({
    int? id,
    int? gameId,
    String? name,
    String? slug,
    String? summary,
    int? classId,
    List<ModFile>? latestFiles,
    bool? allowModDistribution,
  });
  ModCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModCopyWithImpl<$R, $Out> extends ClassCopyWithBase<$R, Mod, $Out>
    implements ModCopyWith<$R, Mod, $Out> {
  _ModCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Mod> $mapper = ModMapper.ensureInitialized();
  @override
  ListCopyWith<$R, ModFile, ModFileCopyWith<$R, ModFile, ModFile>>
  get latestFiles => ListCopyWith(
    $value.latestFiles,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(latestFiles: v),
  );
  @override
  $R call({
    int? id,
    int? gameId,
    String? name,
    String? slug,
    Object? summary = $none,
    int? classId,
    List<ModFile>? latestFiles,
    bool? allowModDistribution,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (gameId != null) #gameId: gameId,
      if (name != null) #name: name,
      if (slug != null) #slug: slug,
      if (summary != $none) #summary: summary,
      if (classId != null) #classId: classId,
      if (latestFiles != null) #latestFiles: latestFiles,
      if (allowModDistribution != null)
        #allowModDistribution: allowModDistribution,
    }),
  );
  @override
  Mod $make(CopyWithData data) => Mod(
    id: data.get(#id, or: $value.id),
    gameId: data.get(#gameId, or: $value.gameId),
    name: data.get(#name, or: $value.name),
    slug: data.get(#slug, or: $value.slug),
    summary: data.get(#summary, or: $value.summary),
    classId: data.get(#classId, or: $value.classId),
    latestFiles: data.get(#latestFiles, or: $value.latestFiles),
    allowModDistribution: data.get(
      #allowModDistribution,
      or: $value.allowModDistribution,
    ),
  );

  @override
  ModCopyWith<$R2, Mod, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ModCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

