// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'cf_file_hash.dart';

class HashAlgoMapper extends EnumMapper<HashAlgo> {
  HashAlgoMapper._();

  static HashAlgoMapper? _instance;
  static HashAlgoMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HashAlgoMapper._());
    }
    return _instance!;
  }

  static HashAlgo fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  HashAlgo decode(dynamic value) {
    switch (value) {
      case r'sha1':
        return HashAlgo.sha1;
      case r'md5':
        return HashAlgo.md5;
      case r'unknown':
        return HashAlgo.unknown;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(HashAlgo self) {
    switch (self) {
      case HashAlgo.sha1:
        return r'sha1';
      case HashAlgo.md5:
        return r'md5';
      case HashAlgo.unknown:
        return r'unknown';
    }
  }
}

extension HashAlgoMapperExtension on HashAlgo {
  String toValue() {
    HashAlgoMapper.ensureInitialized();
    return MapperContainer.globals.toValue<HashAlgo>(this) as String;
  }
}

class FileHashMapper extends ClassMapperBase<FileHash> {
  FileHashMapper._();

  static FileHashMapper? _instance;
  static FileHashMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FileHashMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FileHash';

  static String _$value(FileHash v) => v.value;
  static const Field<FileHash, String> _f$value = Field('value', _$value);
  static int _$algoCode(FileHash v) => v.algoCode;
  static const Field<FileHash, int> _f$algoCode = Field(
    'algoCode',
    _$algoCode,
    key: r'algo',
  );

  @override
  final MappableFields<FileHash> fields = const {
    #value: _f$value,
    #algoCode: _f$algoCode,
  };

  static FileHash _instantiate(DecodingData data) {
    return FileHash(value: data.dec(_f$value), algoCode: data.dec(_f$algoCode));
  }

  @override
  final Function instantiate = _instantiate;

  static FileHash fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FileHash>(map);
  }

  static FileHash fromJson(String json) {
    return ensureInitialized().decodeJson<FileHash>(json);
  }
}

mixin FileHashMappable {
  String toJson() {
    return FileHashMapper.ensureInitialized().encodeJson<FileHash>(
      this as FileHash,
    );
  }

  Map<String, dynamic> toMap() {
    return FileHashMapper.ensureInitialized().encodeMap<FileHash>(
      this as FileHash,
    );
  }

  FileHashCopyWith<FileHash, FileHash, FileHash> get copyWith =>
      _FileHashCopyWithImpl<FileHash, FileHash>(
        this as FileHash,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FileHashMapper.ensureInitialized().stringifyValue(this as FileHash);
  }

  @override
  bool operator ==(Object other) {
    return FileHashMapper.ensureInitialized().equalsValue(
      this as FileHash,
      other,
    );
  }

  @override
  int get hashCode {
    return FileHashMapper.ensureInitialized().hashValue(this as FileHash);
  }
}

extension FileHashValueCopy<$R, $Out> on ObjectCopyWith<$R, FileHash, $Out> {
  FileHashCopyWith<$R, FileHash, $Out> get $asFileHash =>
      $base.as((v, t, t2) => _FileHashCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FileHashCopyWith<$R, $In extends FileHash, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? value, int? algoCode});
  FileHashCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FileHashCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FileHash, $Out>
    implements FileHashCopyWith<$R, FileHash, $Out> {
  _FileHashCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FileHash> $mapper =
      FileHashMapper.ensureInitialized();
  @override
  $R call({String? value, int? algoCode}) => $apply(
    FieldCopyWithData({
      if (value != null) #value: value,
      if (algoCode != null) #algoCode: algoCode,
    }),
  );
  @override
  FileHash $make(CopyWithData data) => FileHash(
    value: data.get(#value, or: $value.value),
    algoCode: data.get(#algoCode, or: $value.algoCode),
  );

  @override
  FileHashCopyWith<$R2, FileHash, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FileHashCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

