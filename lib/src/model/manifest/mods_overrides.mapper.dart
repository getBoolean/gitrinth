// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'mods_overrides.dart';

class ModsOverridesMapper extends ClassMapperBase<ModsOverrides> {
  ModsOverridesMapper._();

  static ModsOverridesMapper? _instance;
  static ModsOverridesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModsOverridesMapper._());
      ModEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModsOverrides';

  static Map<String, ModEntry> _$overrides(ModsOverrides v) => v.overrides;
  static const Field<ModsOverrides, Map<String, ModEntry>> _f$overrides = Field(
    'overrides',
    _$overrides,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<ModsOverrides> fields = const {#overrides: _f$overrides};

  static ModsOverrides _instantiate(DecodingData data) {
    return ModsOverrides(overrides: data.dec(_f$overrides));
  }

  @override
  final Function instantiate = _instantiate;

  static ModsOverrides fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModsOverrides>(map);
  }

  static ModsOverrides fromJson(String json) {
    return ensureInitialized().decodeJson<ModsOverrides>(json);
  }
}

mixin ModsOverridesMappable {
  String toJson() {
    return ModsOverridesMapper.ensureInitialized().encodeJson<ModsOverrides>(
      this as ModsOverrides,
    );
  }

  Map<String, dynamic> toMap() {
    return ModsOverridesMapper.ensureInitialized().encodeMap<ModsOverrides>(
      this as ModsOverrides,
    );
  }

  ModsOverridesCopyWith<ModsOverrides, ModsOverrides, ModsOverrides>
  get copyWith => _ModsOverridesCopyWithImpl<ModsOverrides, ModsOverrides>(
    this as ModsOverrides,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return ModsOverridesMapper.ensureInitialized().stringifyValue(
      this as ModsOverrides,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModsOverridesMapper.ensureInitialized().equalsValue(
      this as ModsOverrides,
      other,
    );
  }

  @override
  int get hashCode {
    return ModsOverridesMapper.ensureInitialized().hashValue(
      this as ModsOverrides,
    );
  }
}

extension ModsOverridesValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModsOverrides, $Out> {
  ModsOverridesCopyWith<$R, ModsOverrides, $Out> get $asModsOverrides =>
      $base.as((v, t, t2) => _ModsOverridesCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModsOverridesCopyWith<$R, $In extends ModsOverrides, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get overrides;
  $R call({Map<String, ModEntry>? overrides});
  ModsOverridesCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModsOverridesCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModsOverrides, $Out>
    implements ModsOverridesCopyWith<$R, ModsOverrides, $Out> {
  _ModsOverridesCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModsOverrides> $mapper =
      ModsOverridesMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get overrides => MapCopyWith(
    $value.overrides,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(overrides: v),
  );
  @override
  $R call({Map<String, ModEntry>? overrides}) =>
      $apply(FieldCopyWithData({if (overrides != null) #overrides: overrides}));
  @override
  ModsOverrides $make(CopyWithData data) =>
      ModsOverrides(overrides: data.get(#overrides, or: $value.overrides));

  @override
  ModsOverridesCopyWith<$R2, ModsOverrides, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModsOverridesCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

