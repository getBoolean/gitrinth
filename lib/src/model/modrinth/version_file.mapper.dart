// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'version_file.dart';

class VersionFileMapper extends ClassMapperBase<VersionFile> {
  VersionFileMapper._();

  static VersionFileMapper? _instance;
  static VersionFileMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VersionFileMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'VersionFile';

  static String _$url(VersionFile v) => v.url;
  static const Field<VersionFile, String> _f$url = Field('url', _$url);
  static String _$filename(VersionFile v) => v.filename;
  static const Field<VersionFile, String> _f$filename = Field(
    'filename',
    _$filename,
  );
  static Map<String, String> _$hashes(VersionFile v) => v.hashes;
  static const Field<VersionFile, Map<String, String>> _f$hashes = Field(
    'hashes',
    _$hashes,
  );
  static int _$size(VersionFile v) => v.size;
  static const Field<VersionFile, int> _f$size = Field('size', _$size);
  static bool _$primary(VersionFile v) => v.primary;
  static const Field<VersionFile, bool> _f$primary = Field(
    'primary',
    _$primary,
  );

  @override
  final MappableFields<VersionFile> fields = const {
    #url: _f$url,
    #filename: _f$filename,
    #hashes: _f$hashes,
    #size: _f$size,
    #primary: _f$primary,
  };

  static VersionFile _instantiate(DecodingData data) {
    return VersionFile(
      url: data.dec(_f$url),
      filename: data.dec(_f$filename),
      hashes: data.dec(_f$hashes),
      size: data.dec(_f$size),
      primary: data.dec(_f$primary),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static VersionFile fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<VersionFile>(map);
  }

  static VersionFile fromJson(String json) {
    return ensureInitialized().decodeJson<VersionFile>(json);
  }
}

mixin VersionFileMappable {
  String toJson() {
    return VersionFileMapper.ensureInitialized().encodeJson<VersionFile>(
      this as VersionFile,
    );
  }

  Map<String, dynamic> toMap() {
    return VersionFileMapper.ensureInitialized().encodeMap<VersionFile>(
      this as VersionFile,
    );
  }

  VersionFileCopyWith<VersionFile, VersionFile, VersionFile> get copyWith =>
      _VersionFileCopyWithImpl<VersionFile, VersionFile>(
        this as VersionFile,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return VersionFileMapper.ensureInitialized().stringifyValue(
      this as VersionFile,
    );
  }

  @override
  bool operator ==(Object other) {
    return VersionFileMapper.ensureInitialized().equalsValue(
      this as VersionFile,
      other,
    );
  }

  @override
  int get hashCode {
    return VersionFileMapper.ensureInitialized().hashValue(this as VersionFile);
  }
}

extension VersionFileValueCopy<$R, $Out>
    on ObjectCopyWith<$R, VersionFile, $Out> {
  VersionFileCopyWith<$R, VersionFile, $Out> get $asVersionFile =>
      $base.as((v, t, t2) => _VersionFileCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class VersionFileCopyWith<$R, $In extends VersionFile, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get hashes;
  $R call({
    String? url,
    String? filename,
    Map<String, String>? hashes,
    int? size,
    bool? primary,
  });
  VersionFileCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _VersionFileCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, VersionFile, $Out>
    implements VersionFileCopyWith<$R, VersionFile, $Out> {
  _VersionFileCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<VersionFile> $mapper =
      VersionFileMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get hashes => MapCopyWith(
    $value.hashes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(hashes: v),
  );
  @override
  $R call({
    String? url,
    String? filename,
    Map<String, String>? hashes,
    int? size,
    bool? primary,
  }) => $apply(
    FieldCopyWithData({
      if (url != null) #url: url,
      if (filename != null) #filename: filename,
      if (hashes != null) #hashes: hashes,
      if (size != null) #size: size,
      if (primary != null) #primary: primary,
    }),
  );
  @override
  VersionFile $make(CopyWithData data) => VersionFile(
    url: data.get(#url, or: $value.url),
    filename: data.get(#filename, or: $value.filename),
    hashes: data.get(#hashes, or: $value.hashes),
    size: data.get(#size, or: $value.size),
    primary: data.get(#primary, or: $value.primary),
  );

  @override
  VersionFileCopyWith<$R2, VersionFile, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _VersionFileCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

