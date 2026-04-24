// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'game_version.dart';

class GameVersionMapper extends ClassMapperBase<GameVersion> {
  GameVersionMapper._();

  static GameVersionMapper? _instance;
  static GameVersionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GameVersionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'GameVersion';

  static String _$version(GameVersion v) => v.version;
  static const Field<GameVersion, String> _f$version = Field(
    'version',
    _$version,
  );
  static String _$versionType(GameVersion v) => v.versionType;
  static const Field<GameVersion, String> _f$versionType = Field(
    'versionType',
    _$versionType,
    key: r'version_type',
  );
  static String _$date(GameVersion v) => v.date;
  static const Field<GameVersion, String> _f$date = Field('date', _$date);
  static bool _$major(GameVersion v) => v.major;
  static const Field<GameVersion, bool> _f$major = Field('major', _$major);

  @override
  final MappableFields<GameVersion> fields = const {
    #version: _f$version,
    #versionType: _f$versionType,
    #date: _f$date,
    #major: _f$major,
  };

  static GameVersion _instantiate(DecodingData data) {
    return GameVersion(
      version: data.dec(_f$version),
      versionType: data.dec(_f$versionType),
      date: data.dec(_f$date),
      major: data.dec(_f$major),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GameVersion fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GameVersion>(map);
  }

  static GameVersion fromJson(String json) {
    return ensureInitialized().decodeJson<GameVersion>(json);
  }
}

mixin GameVersionMappable {
  String toJson() {
    return GameVersionMapper.ensureInitialized().encodeJson<GameVersion>(
      this as GameVersion,
    );
  }

  Map<String, dynamic> toMap() {
    return GameVersionMapper.ensureInitialized().encodeMap<GameVersion>(
      this as GameVersion,
    );
  }

  GameVersionCopyWith<GameVersion, GameVersion, GameVersion> get copyWith =>
      _GameVersionCopyWithImpl<GameVersion, GameVersion>(
        this as GameVersion,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GameVersionMapper.ensureInitialized().stringifyValue(
      this as GameVersion,
    );
  }

  @override
  bool operator ==(Object other) {
    return GameVersionMapper.ensureInitialized().equalsValue(
      this as GameVersion,
      other,
    );
  }

  @override
  int get hashCode {
    return GameVersionMapper.ensureInitialized().hashValue(this as GameVersion);
  }
}

extension GameVersionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GameVersion, $Out> {
  GameVersionCopyWith<$R, GameVersion, $Out> get $asGameVersion =>
      $base.as((v, t, t2) => _GameVersionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GameVersionCopyWith<$R, $In extends GameVersion, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? version, String? versionType, String? date, bool? major});
  GameVersionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _GameVersionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GameVersion, $Out>
    implements GameVersionCopyWith<$R, GameVersion, $Out> {
  _GameVersionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GameVersion> $mapper =
      GameVersionMapper.ensureInitialized();
  @override
  $R call({String? version, String? versionType, String? date, bool? major}) =>
      $apply(
        FieldCopyWithData({
          if (version != null) #version: version,
          if (versionType != null) #versionType: versionType,
          if (date != null) #date: date,
          if (major != null) #major: major,
        }),
      );
  @override
  GameVersion $make(CopyWithData data) => GameVersion(
    version: data.get(#version, or: $value.version),
    versionType: data.get(#versionType, or: $value.versionType),
    date: data.get(#date, or: $value.date),
    major: data.get(#major, or: $value.major),
  );

  @override
  GameVersionCopyWith<$R2, GameVersion, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GameVersionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

