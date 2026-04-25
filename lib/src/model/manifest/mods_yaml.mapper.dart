// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'mods_yaml.dart';

class LoaderMapper extends EnumMapper<Loader> {
  LoaderMapper._();

  static LoaderMapper? _instance;
  static LoaderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LoaderMapper._());
    }
    return _instance!;
  }

  static Loader fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  Loader decode(dynamic value) {
    switch (value) {
      case r'forge':
        return Loader.forge;
      case r'fabric':
        return Loader.fabric;
      case r'neoforge':
        return Loader.neoforge;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(Loader self) {
    switch (self) {
      case Loader.forge:
        return r'forge';
      case Loader.fabric:
        return r'fabric';
      case Loader.neoforge:
        return r'neoforge';
    }
  }
}

extension LoaderMapperExtension on Loader {
  String toValue() {
    LoaderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<Loader>(this) as String;
  }
}

class ShaderLoaderMapper extends EnumMapper<ShaderLoader> {
  ShaderLoaderMapper._();

  static ShaderLoaderMapper? _instance;
  static ShaderLoaderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ShaderLoaderMapper._());
    }
    return _instance!;
  }

  static ShaderLoader fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ShaderLoader decode(dynamic value) {
    switch (value) {
      case r'iris':
        return ShaderLoader.iris;
      case r'optifine':
        return ShaderLoader.optifine;
      case r'canvas':
        return ShaderLoader.canvas;
      case r'vanilla':
        return ShaderLoader.vanilla;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ShaderLoader self) {
    switch (self) {
      case ShaderLoader.iris:
        return r'iris';
      case ShaderLoader.optifine:
        return r'optifine';
      case ShaderLoader.canvas:
        return r'canvas';
      case ShaderLoader.vanilla:
        return r'vanilla';
    }
  }
}

extension ShaderLoaderMapperExtension on ShaderLoader {
  String toValue() {
    ShaderLoaderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ShaderLoader>(this) as String;
  }
}

class PluginLoaderMapper extends EnumMapper<PluginLoader> {
  PluginLoaderMapper._();

  static PluginLoaderMapper? _instance;
  static PluginLoaderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PluginLoaderMapper._());
    }
    return _instance!;
  }

  static PluginLoader fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  PluginLoader decode(dynamic value) {
    switch (value) {
      case r'bukkit':
        return PluginLoader.bukkit;
      case r'folia':
        return PluginLoader.folia;
      case r'paper':
        return PluginLoader.paper;
      case r'spigot':
        return PluginLoader.spigot;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(PluginLoader self) {
    switch (self) {
      case PluginLoader.bukkit:
        return r'bukkit';
      case PluginLoader.folia:
        return r'folia';
      case PluginLoader.paper:
        return r'paper';
      case PluginLoader.spigot:
        return r'spigot';
    }
  }
}

extension PluginLoaderMapperExtension on PluginLoader {
  String toValue() {
    PluginLoaderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<PluginLoader>(this) as String;
  }
}

class SideEnvMapper extends EnumMapper<SideEnv> {
  SideEnvMapper._();

  static SideEnvMapper? _instance;
  static SideEnvMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SideEnvMapper._());
    }
    return _instance!;
  }

  static SideEnv fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  SideEnv decode(dynamic value) {
    switch (value) {
      case r'required':
        return SideEnv.required;
      case r'optional':
        return SideEnv.optional;
      case r'unsupported':
        return SideEnv.unsupported;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(SideEnv self) {
    switch (self) {
      case SideEnv.required:
        return r'required';
      case SideEnv.optional:
        return r'optional';
      case SideEnv.unsupported:
        return r'unsupported';
    }
  }
}

extension SideEnvMapperExtension on SideEnv {
  String toValue() {
    SideEnvMapper.ensureInitialized();
    return MapperContainer.globals.toValue<SideEnv>(this) as String;
  }
}

class SectionMapper extends EnumMapper<Section> {
  SectionMapper._();

  static SectionMapper? _instance;
  static SectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SectionMapper._());
    }
    return _instance!;
  }

  static Section fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  Section decode(dynamic value) {
    switch (value) {
      case r'mods':
        return Section.mods;
      case r'resourcePacks':
        return Section.resourcePacks;
      case r'dataPacks':
        return Section.dataPacks;
      case r'shaders':
        return Section.shaders;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(Section self) {
    switch (self) {
      case Section.mods:
        return r'mods';
      case Section.resourcePacks:
        return r'resourcePacks';
      case Section.dataPacks:
        return r'dataPacks';
      case Section.shaders:
        return r'shaders';
    }
  }
}

extension SectionMapperExtension on Section {
  String toValue() {
    SectionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<Section>(this) as String;
  }
}

class ChannelMapper extends EnumMapper<Channel> {
  ChannelMapper._();

  static ChannelMapper? _instance;
  static ChannelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChannelMapper._());
    }
    return _instance!;
  }

  static Channel fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  Channel decode(dynamic value) {
    switch (value) {
      case r'release':
        return Channel.release;
      case r'beta':
        return Channel.beta;
      case r'alpha':
        return Channel.alpha;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(Channel self) {
    switch (self) {
      case Channel.release:
        return r'release';
      case Channel.beta:
        return r'beta';
      case Channel.alpha:
        return r'alpha';
    }
  }
}

extension ChannelMapperExtension on Channel {
  String toValue() {
    ChannelMapper.ensureInitialized();
    return MapperContainer.globals.toValue<Channel>(this) as String;
  }
}

class LoaderConfigMapper extends ClassMapperBase<LoaderConfig> {
  LoaderConfigMapper._();

  static LoaderConfigMapper? _instance;
  static LoaderConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LoaderConfigMapper._());
      LoaderMapper.ensureInitialized();
      ShaderLoaderMapper.ensureInitialized();
      PluginLoaderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LoaderConfig';

  static Loader _$mods(LoaderConfig v) => v.mods;
  static const Field<LoaderConfig, Loader> _f$mods = Field('mods', _$mods);
  static String _$modsVersion(LoaderConfig v) => v.modsVersion;
  static const Field<LoaderConfig, String> _f$modsVersion = Field(
    'modsVersion',
    _$modsVersion,
    opt: true,
    def: 'stable',
  );
  static ShaderLoader? _$shaders(LoaderConfig v) => v.shaders;
  static const Field<LoaderConfig, ShaderLoader> _f$shaders = Field(
    'shaders',
    _$shaders,
    opt: true,
  );
  static PluginLoader? _$plugins(LoaderConfig v) => v.plugins;
  static const Field<LoaderConfig, PluginLoader> _f$plugins = Field(
    'plugins',
    _$plugins,
    opt: true,
  );

  @override
  final MappableFields<LoaderConfig> fields = const {
    #mods: _f$mods,
    #modsVersion: _f$modsVersion,
    #shaders: _f$shaders,
    #plugins: _f$plugins,
  };

  static LoaderConfig _instantiate(DecodingData data) {
    return LoaderConfig(
      mods: data.dec(_f$mods),
      modsVersion: data.dec(_f$modsVersion),
      shaders: data.dec(_f$shaders),
      plugins: data.dec(_f$plugins),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LoaderConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LoaderConfig>(map);
  }

  static LoaderConfig fromJson(String json) {
    return ensureInitialized().decodeJson<LoaderConfig>(json);
  }
}

mixin LoaderConfigMappable {
  String toJson() {
    return LoaderConfigMapper.ensureInitialized().encodeJson<LoaderConfig>(
      this as LoaderConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return LoaderConfigMapper.ensureInitialized().encodeMap<LoaderConfig>(
      this as LoaderConfig,
    );
  }

  LoaderConfigCopyWith<LoaderConfig, LoaderConfig, LoaderConfig> get copyWith =>
      _LoaderConfigCopyWithImpl<LoaderConfig, LoaderConfig>(
        this as LoaderConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LoaderConfigMapper.ensureInitialized().stringifyValue(
      this as LoaderConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return LoaderConfigMapper.ensureInitialized().equalsValue(
      this as LoaderConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return LoaderConfigMapper.ensureInitialized().hashValue(
      this as LoaderConfig,
    );
  }
}

extension LoaderConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LoaderConfig, $Out> {
  LoaderConfigCopyWith<$R, LoaderConfig, $Out> get $asLoaderConfig =>
      $base.as((v, t, t2) => _LoaderConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LoaderConfigCopyWith<$R, $In extends LoaderConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    Loader? mods,
    String? modsVersion,
    ShaderLoader? shaders,
    PluginLoader? plugins,
  });
  LoaderConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LoaderConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LoaderConfig, $Out>
    implements LoaderConfigCopyWith<$R, LoaderConfig, $Out> {
  _LoaderConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LoaderConfig> $mapper =
      LoaderConfigMapper.ensureInitialized();
  @override
  $R call({
    Loader? mods,
    String? modsVersion,
    Object? shaders = $none,
    Object? plugins = $none,
  }) => $apply(
    FieldCopyWithData({
      if (mods != null) #mods: mods,
      if (modsVersion != null) #modsVersion: modsVersion,
      if (shaders != $none) #shaders: shaders,
      if (plugins != $none) #plugins: plugins,
    }),
  );
  @override
  LoaderConfig $make(CopyWithData data) => LoaderConfig(
    mods: data.get(#mods, or: $value.mods),
    modsVersion: data.get(#modsVersion, or: $value.modsVersion),
    shaders: data.get(#shaders, or: $value.shaders),
    plugins: data.get(#plugins, or: $value.plugins),
  );

  @override
  LoaderConfigCopyWith<$R2, LoaderConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LoaderConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class EntrySourceMapper extends ClassMapperBase<EntrySource> {
  EntrySourceMapper._();

  static EntrySourceMapper? _instance;
  static EntrySourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EntrySourceMapper._());
      ModrinthEntrySourceMapper.ensureInitialized();
      UrlEntrySourceMapper.ensureInitialized();
      PathEntrySourceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EntrySource';

  @override
  final MappableFields<EntrySource> fields = const {};

  static EntrySource _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'EntrySource',
      'kind',
      '${data.value['kind']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EntrySource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EntrySource>(map);
  }

  static EntrySource fromJson(String json) {
    return ensureInitialized().decodeJson<EntrySource>(json);
  }
}

mixin EntrySourceMappable {
  String toJson();
  Map<String, dynamic> toMap();
  EntrySourceCopyWith<EntrySource, EntrySource, EntrySource> get copyWith;
}

abstract class EntrySourceCopyWith<$R, $In extends EntrySource, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call();
  EntrySourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class ModrinthEntrySourceMapper
    extends SubClassMapperBase<ModrinthEntrySource> {
  ModrinthEntrySourceMapper._();

  static ModrinthEntrySourceMapper? _instance;
  static ModrinthEntrySourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModrinthEntrySourceMapper._());
      EntrySourceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ModrinthEntrySource';

  @override
  final MappableFields<ModrinthEntrySource> fields = const {};

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'modrinth';
  @override
  late final ClassMapperBase superMapper =
      EntrySourceMapper.ensureInitialized();

  static ModrinthEntrySource _instantiate(DecodingData data) {
    return ModrinthEntrySource();
  }

  @override
  final Function instantiate = _instantiate;

  static ModrinthEntrySource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModrinthEntrySource>(map);
  }

  static ModrinthEntrySource fromJson(String json) {
    return ensureInitialized().decodeJson<ModrinthEntrySource>(json);
  }
}

mixin ModrinthEntrySourceMappable {
  String toJson() {
    return ModrinthEntrySourceMapper.ensureInitialized()
        .encodeJson<ModrinthEntrySource>(this as ModrinthEntrySource);
  }

  Map<String, dynamic> toMap() {
    return ModrinthEntrySourceMapper.ensureInitialized()
        .encodeMap<ModrinthEntrySource>(this as ModrinthEntrySource);
  }

  ModrinthEntrySourceCopyWith<
    ModrinthEntrySource,
    ModrinthEntrySource,
    ModrinthEntrySource
  >
  get copyWith =>
      _ModrinthEntrySourceCopyWithImpl<
        ModrinthEntrySource,
        ModrinthEntrySource
      >(this as ModrinthEntrySource, $identity, $identity);
  @override
  String toString() {
    return ModrinthEntrySourceMapper.ensureInitialized().stringifyValue(
      this as ModrinthEntrySource,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModrinthEntrySourceMapper.ensureInitialized().equalsValue(
      this as ModrinthEntrySource,
      other,
    );
  }

  @override
  int get hashCode {
    return ModrinthEntrySourceMapper.ensureInitialized().hashValue(
      this as ModrinthEntrySource,
    );
  }
}

extension ModrinthEntrySourceValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModrinthEntrySource, $Out> {
  ModrinthEntrySourceCopyWith<$R, ModrinthEntrySource, $Out>
  get $asModrinthEntrySource => $base.as(
    (v, t, t2) => _ModrinthEntrySourceCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ModrinthEntrySourceCopyWith<
  $R,
  $In extends ModrinthEntrySource,
  $Out
>
    implements EntrySourceCopyWith<$R, $In, $Out> {
  @override
  $R call();
  ModrinthEntrySourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ModrinthEntrySourceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModrinthEntrySource, $Out>
    implements ModrinthEntrySourceCopyWith<$R, ModrinthEntrySource, $Out> {
  _ModrinthEntrySourceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModrinthEntrySource> $mapper =
      ModrinthEntrySourceMapper.ensureInitialized();
  @override
  $R call() => $apply(FieldCopyWithData({}));
  @override
  ModrinthEntrySource $make(CopyWithData data) => ModrinthEntrySource();

  @override
  ModrinthEntrySourceCopyWith<$R2, ModrinthEntrySource, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ModrinthEntrySourceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class UrlEntrySourceMapper extends SubClassMapperBase<UrlEntrySource> {
  UrlEntrySourceMapper._();

  static UrlEntrySourceMapper? _instance;
  static UrlEntrySourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = UrlEntrySourceMapper._());
      EntrySourceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'UrlEntrySource';

  static String _$url(UrlEntrySource v) => v.url;
  static const Field<UrlEntrySource, String> _f$url = Field('url', _$url);

  @override
  final MappableFields<UrlEntrySource> fields = const {#url: _f$url};

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'url';
  @override
  late final ClassMapperBase superMapper =
      EntrySourceMapper.ensureInitialized();

  static UrlEntrySource _instantiate(DecodingData data) {
    return UrlEntrySource(url: data.dec(_f$url));
  }

  @override
  final Function instantiate = _instantiate;

  static UrlEntrySource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UrlEntrySource>(map);
  }

  static UrlEntrySource fromJson(String json) {
    return ensureInitialized().decodeJson<UrlEntrySource>(json);
  }
}

mixin UrlEntrySourceMappable {
  String toJson() {
    return UrlEntrySourceMapper.ensureInitialized().encodeJson<UrlEntrySource>(
      this as UrlEntrySource,
    );
  }

  Map<String, dynamic> toMap() {
    return UrlEntrySourceMapper.ensureInitialized().encodeMap<UrlEntrySource>(
      this as UrlEntrySource,
    );
  }

  UrlEntrySourceCopyWith<UrlEntrySource, UrlEntrySource, UrlEntrySource>
  get copyWith => _UrlEntrySourceCopyWithImpl<UrlEntrySource, UrlEntrySource>(
    this as UrlEntrySource,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return UrlEntrySourceMapper.ensureInitialized().stringifyValue(
      this as UrlEntrySource,
    );
  }

  @override
  bool operator ==(Object other) {
    return UrlEntrySourceMapper.ensureInitialized().equalsValue(
      this as UrlEntrySource,
      other,
    );
  }

  @override
  int get hashCode {
    return UrlEntrySourceMapper.ensureInitialized().hashValue(
      this as UrlEntrySource,
    );
  }
}

extension UrlEntrySourceValueCopy<$R, $Out>
    on ObjectCopyWith<$R, UrlEntrySource, $Out> {
  UrlEntrySourceCopyWith<$R, UrlEntrySource, $Out> get $asUrlEntrySource =>
      $base.as((v, t, t2) => _UrlEntrySourceCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class UrlEntrySourceCopyWith<$R, $In extends UrlEntrySource, $Out>
    implements EntrySourceCopyWith<$R, $In, $Out> {
  @override
  $R call({String? url});
  UrlEntrySourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _UrlEntrySourceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, UrlEntrySource, $Out>
    implements UrlEntrySourceCopyWith<$R, UrlEntrySource, $Out> {
  _UrlEntrySourceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<UrlEntrySource> $mapper =
      UrlEntrySourceMapper.ensureInitialized();
  @override
  $R call({String? url}) =>
      $apply(FieldCopyWithData({if (url != null) #url: url}));
  @override
  UrlEntrySource $make(CopyWithData data) =>
      UrlEntrySource(url: data.get(#url, or: $value.url));

  @override
  UrlEntrySourceCopyWith<$R2, UrlEntrySource, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _UrlEntrySourceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class PathEntrySourceMapper extends SubClassMapperBase<PathEntrySource> {
  PathEntrySourceMapper._();

  static PathEntrySourceMapper? _instance;
  static PathEntrySourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PathEntrySourceMapper._());
      EntrySourceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'PathEntrySource';

  static String _$path(PathEntrySource v) => v.path;
  static const Field<PathEntrySource, String> _f$path = Field('path', _$path);

  @override
  final MappableFields<PathEntrySource> fields = const {#path: _f$path};

  @override
  final String discriminatorKey = 'kind';
  @override
  final dynamic discriminatorValue = 'path';
  @override
  late final ClassMapperBase superMapper =
      EntrySourceMapper.ensureInitialized();

  static PathEntrySource _instantiate(DecodingData data) {
    return PathEntrySource(path: data.dec(_f$path));
  }

  @override
  final Function instantiate = _instantiate;

  static PathEntrySource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PathEntrySource>(map);
  }

  static PathEntrySource fromJson(String json) {
    return ensureInitialized().decodeJson<PathEntrySource>(json);
  }
}

mixin PathEntrySourceMappable {
  String toJson() {
    return PathEntrySourceMapper.ensureInitialized()
        .encodeJson<PathEntrySource>(this as PathEntrySource);
  }

  Map<String, dynamic> toMap() {
    return PathEntrySourceMapper.ensureInitialized().encodeMap<PathEntrySource>(
      this as PathEntrySource,
    );
  }

  PathEntrySourceCopyWith<PathEntrySource, PathEntrySource, PathEntrySource>
  get copyWith =>
      _PathEntrySourceCopyWithImpl<PathEntrySource, PathEntrySource>(
        this as PathEntrySource,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PathEntrySourceMapper.ensureInitialized().stringifyValue(
      this as PathEntrySource,
    );
  }

  @override
  bool operator ==(Object other) {
    return PathEntrySourceMapper.ensureInitialized().equalsValue(
      this as PathEntrySource,
      other,
    );
  }

  @override
  int get hashCode {
    return PathEntrySourceMapper.ensureInitialized().hashValue(
      this as PathEntrySource,
    );
  }
}

extension PathEntrySourceValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PathEntrySource, $Out> {
  PathEntrySourceCopyWith<$R, PathEntrySource, $Out> get $asPathEntrySource =>
      $base.as((v, t, t2) => _PathEntrySourceCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PathEntrySourceCopyWith<$R, $In extends PathEntrySource, $Out>
    implements EntrySourceCopyWith<$R, $In, $Out> {
  @override
  $R call({String? path});
  PathEntrySourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PathEntrySourceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PathEntrySource, $Out>
    implements PathEntrySourceCopyWith<$R, PathEntrySource, $Out> {
  _PathEntrySourceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PathEntrySource> $mapper =
      PathEntrySourceMapper.ensureInitialized();
  @override
  $R call({String? path}) =>
      $apply(FieldCopyWithData({if (path != null) #path: path}));
  @override
  PathEntrySource $make(CopyWithData data) =>
      PathEntrySource(path: data.get(#path, or: $value.path));

  @override
  PathEntrySourceCopyWith<$R2, PathEntrySource, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PathEntrySourceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModEntryMapper extends ClassMapperBase<ModEntry> {
  ModEntryMapper._();

  static ModEntryMapper? _instance;
  static ModEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModEntryMapper._());
      ChannelMapper.ensureInitialized();
      SideEnvMapper.ensureInitialized();
      EntrySourceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModEntry';

  static String _$slug(ModEntry v) => v.slug;
  static const Field<ModEntry, String> _f$slug = Field('slug', _$slug);
  static String? _$constraintRaw(ModEntry v) => v.constraintRaw;
  static const Field<ModEntry, String> _f$constraintRaw = Field(
    'constraintRaw',
    _$constraintRaw,
    opt: true,
  );
  static Channel? _$channel(ModEntry v) => v.channel;
  static const Field<ModEntry, Channel> _f$channel = Field(
    'channel',
    _$channel,
    opt: true,
  );
  static SideEnv _$client(ModEntry v) => v.client;
  static const Field<ModEntry, SideEnv> _f$client = Field(
    'client',
    _$client,
    opt: true,
    def: SideEnv.required,
  );
  static SideEnv _$server(ModEntry v) => v.server;
  static const Field<ModEntry, SideEnv> _f$server = Field(
    'server',
    _$server,
    opt: true,
    def: SideEnv.required,
  );
  static EntrySource _$source(ModEntry v) => v.source;
  static const Field<ModEntry, EntrySource> _f$source = Field(
    'source',
    _$source,
    opt: true,
    def: const ModrinthEntrySource(),
  );
  static List<String> _$acceptsMc(ModEntry v) => v.acceptsMc;
  static const Field<ModEntry, List<String>> _f$acceptsMc = Field(
    'acceptsMc',
    _$acceptsMc,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<ModEntry> fields = const {
    #slug: _f$slug,
    #constraintRaw: _f$constraintRaw,
    #channel: _f$channel,
    #client: _f$client,
    #server: _f$server,
    #source: _f$source,
    #acceptsMc: _f$acceptsMc,
  };

  static ModEntry _instantiate(DecodingData data) {
    return ModEntry(
      slug: data.dec(_f$slug),
      constraintRaw: data.dec(_f$constraintRaw),
      channel: data.dec(_f$channel),
      client: data.dec(_f$client),
      server: data.dec(_f$server),
      source: data.dec(_f$source),
      acceptsMc: data.dec(_f$acceptsMc),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModEntry>(map);
  }

  static ModEntry fromJson(String json) {
    return ensureInitialized().decodeJson<ModEntry>(json);
  }
}

mixin ModEntryMappable {
  String toJson() {
    return ModEntryMapper.ensureInitialized().encodeJson<ModEntry>(
      this as ModEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return ModEntryMapper.ensureInitialized().encodeMap<ModEntry>(
      this as ModEntry,
    );
  }

  ModEntryCopyWith<ModEntry, ModEntry, ModEntry> get copyWith =>
      _ModEntryCopyWithImpl<ModEntry, ModEntry>(
        this as ModEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModEntryMapper.ensureInitialized().stringifyValue(this as ModEntry);
  }

  @override
  bool operator ==(Object other) {
    return ModEntryMapper.ensureInitialized().equalsValue(
      this as ModEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return ModEntryMapper.ensureInitialized().hashValue(this as ModEntry);
  }
}

extension ModEntryValueCopy<$R, $Out> on ObjectCopyWith<$R, ModEntry, $Out> {
  ModEntryCopyWith<$R, ModEntry, $Out> get $asModEntry =>
      $base.as((v, t, t2) => _ModEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModEntryCopyWith<$R, $In extends ModEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  EntrySourceCopyWith<$R, EntrySource, EntrySource> get source;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get acceptsMc;
  $R call({
    String? slug,
    String? constraintRaw,
    Channel? channel,
    SideEnv? client,
    SideEnv? server,
    EntrySource? source,
    List<String>? acceptsMc,
  });
  ModEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModEntry, $Out>
    implements ModEntryCopyWith<$R, ModEntry, $Out> {
  _ModEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModEntry> $mapper =
      ModEntryMapper.ensureInitialized();
  @override
  EntrySourceCopyWith<$R, EntrySource, EntrySource> get source =>
      $value.source.copyWith.$chain((v) => call(source: v));
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get acceptsMc =>
      ListCopyWith(
        $value.acceptsMc,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(acceptsMc: v),
      );
  @override
  $R call({
    String? slug,
    Object? constraintRaw = $none,
    Object? channel = $none,
    SideEnv? client,
    SideEnv? server,
    EntrySource? source,
    List<String>? acceptsMc,
  }) => $apply(
    FieldCopyWithData({
      if (slug != null) #slug: slug,
      if (constraintRaw != $none) #constraintRaw: constraintRaw,
      if (channel != $none) #channel: channel,
      if (client != null) #client: client,
      if (server != null) #server: server,
      if (source != null) #source: source,
      if (acceptsMc != null) #acceptsMc: acceptsMc,
    }),
  );
  @override
  ModEntry $make(CopyWithData data) => ModEntry(
    slug: data.get(#slug, or: $value.slug),
    constraintRaw: data.get(#constraintRaw, or: $value.constraintRaw),
    channel: data.get(#channel, or: $value.channel),
    client: data.get(#client, or: $value.client),
    server: data.get(#server, or: $value.server),
    source: data.get(#source, or: $value.source),
    acceptsMc: data.get(#acceptsMc, or: $value.acceptsMc),
  );

  @override
  ModEntryCopyWith<$R2, ModEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModsYamlMapper extends ClassMapperBase<ModsYaml> {
  ModsYamlMapper._();

  static ModsYamlMapper? _instance;
  static ModsYamlMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModsYamlMapper._());
      LoaderConfigMapper.ensureInitialized();
      ModEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModsYaml';

  static String _$slug(ModsYaml v) => v.slug;
  static const Field<ModsYaml, String> _f$slug = Field('slug', _$slug);
  static String _$name(ModsYaml v) => v.name;
  static const Field<ModsYaml, String> _f$name = Field('name', _$name);
  static String _$version(ModsYaml v) => v.version;
  static const Field<ModsYaml, String> _f$version = Field('version', _$version);
  static String _$description(ModsYaml v) => v.description;
  static const Field<ModsYaml, String> _f$description = Field(
    'description',
    _$description,
  );
  static LoaderConfig _$loader(ModsYaml v) => v.loader;
  static const Field<ModsYaml, LoaderConfig> _f$loader = Field(
    'loader',
    _$loader,
  );
  static String _$mcVersion(ModsYaml v) => v.mcVersion;
  static const Field<ModsYaml, String> _f$mcVersion = Field(
    'mcVersion',
    _$mcVersion,
  );
  static Map<String, ModEntry> _$mods(ModsYaml v) => v.mods;
  static const Field<ModsYaml, Map<String, ModEntry>> _f$mods = Field(
    'mods',
    _$mods,
    opt: true,
    def: const {},
  );
  static Map<String, ModEntry> _$resourcePacks(ModsYaml v) => v.resourcePacks;
  static const Field<ModsYaml, Map<String, ModEntry>> _f$resourcePacks = Field(
    'resourcePacks',
    _$resourcePacks,
    opt: true,
    def: const {},
  );
  static Map<String, ModEntry> _$dataPacks(ModsYaml v) => v.dataPacks;
  static const Field<ModsYaml, Map<String, ModEntry>> _f$dataPacks = Field(
    'dataPacks',
    _$dataPacks,
    opt: true,
    def: const {},
  );
  static Map<String, ModEntry> _$shaders(ModsYaml v) => v.shaders;
  static const Field<ModsYaml, Map<String, ModEntry>> _f$shaders = Field(
    'shaders',
    _$shaders,
    opt: true,
    def: const {},
  );
  static Map<String, ModEntry> _$overrides(ModsYaml v) => v.overrides;
  static const Field<ModsYaml, Map<String, ModEntry>> _f$overrides = Field(
    'overrides',
    _$overrides,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<ModsYaml> fields = const {
    #slug: _f$slug,
    #name: _f$name,
    #version: _f$version,
    #description: _f$description,
    #loader: _f$loader,
    #mcVersion: _f$mcVersion,
    #mods: _f$mods,
    #resourcePacks: _f$resourcePacks,
    #dataPacks: _f$dataPacks,
    #shaders: _f$shaders,
    #overrides: _f$overrides,
  };

  static ModsYaml _instantiate(DecodingData data) {
    return ModsYaml(
      slug: data.dec(_f$slug),
      name: data.dec(_f$name),
      version: data.dec(_f$version),
      description: data.dec(_f$description),
      loader: data.dec(_f$loader),
      mcVersion: data.dec(_f$mcVersion),
      mods: data.dec(_f$mods),
      resourcePacks: data.dec(_f$resourcePacks),
      dataPacks: data.dec(_f$dataPacks),
      shaders: data.dec(_f$shaders),
      overrides: data.dec(_f$overrides),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModsYaml fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModsYaml>(map);
  }

  static ModsYaml fromJson(String json) {
    return ensureInitialized().decodeJson<ModsYaml>(json);
  }
}

mixin ModsYamlMappable {
  String toJson() {
    return ModsYamlMapper.ensureInitialized().encodeJson<ModsYaml>(
      this as ModsYaml,
    );
  }

  Map<String, dynamic> toMap() {
    return ModsYamlMapper.ensureInitialized().encodeMap<ModsYaml>(
      this as ModsYaml,
    );
  }

  ModsYamlCopyWith<ModsYaml, ModsYaml, ModsYaml> get copyWith =>
      _ModsYamlCopyWithImpl<ModsYaml, ModsYaml>(
        this as ModsYaml,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModsYamlMapper.ensureInitialized().stringifyValue(this as ModsYaml);
  }

  @override
  bool operator ==(Object other) {
    return ModsYamlMapper.ensureInitialized().equalsValue(
      this as ModsYaml,
      other,
    );
  }

  @override
  int get hashCode {
    return ModsYamlMapper.ensureInitialized().hashValue(this as ModsYaml);
  }
}

extension ModsYamlValueCopy<$R, $Out> on ObjectCopyWith<$R, ModsYaml, $Out> {
  ModsYamlCopyWith<$R, ModsYaml, $Out> get $asModsYaml =>
      $base.as((v, t, t2) => _ModsYamlCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModsYamlCopyWith<$R, $In extends ModsYaml, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  LoaderConfigCopyWith<$R, LoaderConfig, LoaderConfig> get loader;
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get mods;
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get resourcePacks;
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get dataPacks;
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get shaders;
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get overrides;
  $R call({
    String? slug,
    String? name,
    String? version,
    String? description,
    LoaderConfig? loader,
    String? mcVersion,
    Map<String, ModEntry>? mods,
    Map<String, ModEntry>? resourcePacks,
    Map<String, ModEntry>? dataPacks,
    Map<String, ModEntry>? shaders,
    Map<String, ModEntry>? overrides,
  });
  ModsYamlCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModsYamlCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModsYaml, $Out>
    implements ModsYamlCopyWith<$R, ModsYaml, $Out> {
  _ModsYamlCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModsYaml> $mapper =
      ModsYamlMapper.ensureInitialized();
  @override
  LoaderConfigCopyWith<$R, LoaderConfig, LoaderConfig> get loader =>
      $value.loader.copyWith.$chain((v) => call(loader: v));
  @override
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get mods => MapCopyWith(
    $value.mods,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(mods: v),
  );
  @override
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get resourcePacks => MapCopyWith(
    $value.resourcePacks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(resourcePacks: v),
  );
  @override
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get dataPacks => MapCopyWith(
    $value.dataPacks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(dataPacks: v),
  );
  @override
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get shaders => MapCopyWith(
    $value.shaders,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(shaders: v),
  );
  @override
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get overrides => MapCopyWith(
    $value.overrides,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(overrides: v),
  );
  @override
  $R call({
    String? slug,
    String? name,
    String? version,
    String? description,
    LoaderConfig? loader,
    String? mcVersion,
    Map<String, ModEntry>? mods,
    Map<String, ModEntry>? resourcePacks,
    Map<String, ModEntry>? dataPacks,
    Map<String, ModEntry>? shaders,
    Map<String, ModEntry>? overrides,
  }) => $apply(
    FieldCopyWithData({
      if (slug != null) #slug: slug,
      if (name != null) #name: name,
      if (version != null) #version: version,
      if (description != null) #description: description,
      if (loader != null) #loader: loader,
      if (mcVersion != null) #mcVersion: mcVersion,
      if (mods != null) #mods: mods,
      if (resourcePacks != null) #resourcePacks: resourcePacks,
      if (dataPacks != null) #dataPacks: dataPacks,
      if (shaders != null) #shaders: shaders,
      if (overrides != null) #overrides: overrides,
    }),
  );
  @override
  ModsYaml $make(CopyWithData data) => ModsYaml(
    slug: data.get(#slug, or: $value.slug),
    name: data.get(#name, or: $value.name),
    version: data.get(#version, or: $value.version),
    description: data.get(#description, or: $value.description),
    loader: data.get(#loader, or: $value.loader),
    mcVersion: data.get(#mcVersion, or: $value.mcVersion),
    mods: data.get(#mods, or: $value.mods),
    resourcePacks: data.get(#resourcePacks, or: $value.resourcePacks),
    dataPacks: data.get(#dataPacks, or: $value.dataPacks),
    shaders: data.get(#shaders, or: $value.shaders),
    overrides: data.get(#overrides, or: $value.overrides),
  );

  @override
  ModsYamlCopyWith<$R2, ModsYaml, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModsYamlCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

