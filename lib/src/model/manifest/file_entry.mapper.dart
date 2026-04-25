// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'file_entry.dart';

class FileEntryMapper extends ClassMapperBase<FileEntry> {
  FileEntryMapper._();

  static FileEntryMapper? _instance;
  static FileEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FileEntryMapper._());
      SideEnvMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'FileEntry';

  static String _$destination(FileEntry v) => v.destination;
  static const Field<FileEntry, String> _f$destination = Field(
    'destination',
    _$destination,
  );
  static String _$sourcePath(FileEntry v) => v.sourcePath;
  static const Field<FileEntry, String> _f$sourcePath = Field(
    'sourcePath',
    _$sourcePath,
  );
  static SideEnv _$client(FileEntry v) => v.client;
  static const Field<FileEntry, SideEnv> _f$client = Field(
    'client',
    _$client,
    opt: true,
    def: SideEnv.required,
  );
  static SideEnv _$server(FileEntry v) => v.server;
  static const Field<FileEntry, SideEnv> _f$server = Field(
    'server',
    _$server,
    opt: true,
    def: SideEnv.required,
  );
  static bool _$preserve(FileEntry v) => v.preserve;
  static const Field<FileEntry, bool> _f$preserve = Field(
    'preserve',
    _$preserve,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<FileEntry> fields = const {
    #destination: _f$destination,
    #sourcePath: _f$sourcePath,
    #client: _f$client,
    #server: _f$server,
    #preserve: _f$preserve,
  };

  static FileEntry _instantiate(DecodingData data) {
    return FileEntry(
      destination: data.dec(_f$destination),
      sourcePath: data.dec(_f$sourcePath),
      client: data.dec(_f$client),
      server: data.dec(_f$server),
      preserve: data.dec(_f$preserve),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FileEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FileEntry>(map);
  }

  static FileEntry fromJson(String json) {
    return ensureInitialized().decodeJson<FileEntry>(json);
  }
}

mixin FileEntryMappable {
  String toJson() {
    return FileEntryMapper.ensureInitialized().encodeJson<FileEntry>(
      this as FileEntry,
    );
  }

  Map<String, dynamic> toMap() {
    return FileEntryMapper.ensureInitialized().encodeMap<FileEntry>(
      this as FileEntry,
    );
  }

  FileEntryCopyWith<FileEntry, FileEntry, FileEntry> get copyWith =>
      _FileEntryCopyWithImpl<FileEntry, FileEntry>(
        this as FileEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FileEntryMapper.ensureInitialized().stringifyValue(
      this as FileEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return FileEntryMapper.ensureInitialized().equalsValue(
      this as FileEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return FileEntryMapper.ensureInitialized().hashValue(this as FileEntry);
  }
}

extension FileEntryValueCopy<$R, $Out> on ObjectCopyWith<$R, FileEntry, $Out> {
  FileEntryCopyWith<$R, FileEntry, $Out> get $asFileEntry =>
      $base.as((v, t, t2) => _FileEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FileEntryCopyWith<$R, $In extends FileEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? destination,
    String? sourcePath,
    SideEnv? client,
    SideEnv? server,
    bool? preserve,
  });
  FileEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FileEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FileEntry, $Out>
    implements FileEntryCopyWith<$R, FileEntry, $Out> {
  _FileEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FileEntry> $mapper =
      FileEntryMapper.ensureInitialized();
  @override
  $R call({
    String? destination,
    String? sourcePath,
    SideEnv? client,
    SideEnv? server,
    bool? preserve,
  }) => $apply(
    FieldCopyWithData({
      if (destination != null) #destination: destination,
      if (sourcePath != null) #sourcePath: sourcePath,
      if (client != null) #client: client,
      if (server != null) #server: server,
      if (preserve != null) #preserve: preserve,
    }),
  );
  @override
  FileEntry $make(CopyWithData data) => FileEntry(
    destination: data.get(#destination, or: $value.destination),
    sourcePath: data.get(#sourcePath, or: $value.sourcePath),
    client: data.get(#client, or: $value.client),
    server: data.get(#server, or: $value.server),
    preserve: data.get(#preserve, or: $value.preserve),
  );

  @override
  FileEntryCopyWith<$R2, FileEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FileEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

