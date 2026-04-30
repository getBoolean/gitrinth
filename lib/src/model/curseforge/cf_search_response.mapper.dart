// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'cf_search_response.dart';

class PaginationMapper extends ClassMapperBase<Pagination> {
  PaginationMapper._();

  static PaginationMapper? _instance;
  static PaginationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PaginationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Pagination';

  static int _$index(Pagination v) => v.index;
  static const Field<Pagination, int> _f$index = Field('index', _$index);
  static int _$pageSize(Pagination v) => v.pageSize;
  static const Field<Pagination, int> _f$pageSize = Field(
    'pageSize',
    _$pageSize,
  );
  static int _$resultCount(Pagination v) => v.resultCount;
  static const Field<Pagination, int> _f$resultCount = Field(
    'resultCount',
    _$resultCount,
  );
  static int _$totalCount(Pagination v) => v.totalCount;
  static const Field<Pagination, int> _f$totalCount = Field(
    'totalCount',
    _$totalCount,
  );

  @override
  final MappableFields<Pagination> fields = const {
    #index: _f$index,
    #pageSize: _f$pageSize,
    #resultCount: _f$resultCount,
    #totalCount: _f$totalCount,
  };

  static Pagination _instantiate(DecodingData data) {
    return Pagination(
      index: data.dec(_f$index),
      pageSize: data.dec(_f$pageSize),
      resultCount: data.dec(_f$resultCount),
      totalCount: data.dec(_f$totalCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Pagination fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Pagination>(map);
  }

  static Pagination fromJson(String json) {
    return ensureInitialized().decodeJson<Pagination>(json);
  }
}

mixin PaginationMappable {
  String toJson() {
    return PaginationMapper.ensureInitialized().encodeJson<Pagination>(
      this as Pagination,
    );
  }

  Map<String, dynamic> toMap() {
    return PaginationMapper.ensureInitialized().encodeMap<Pagination>(
      this as Pagination,
    );
  }

  PaginationCopyWith<Pagination, Pagination, Pagination> get copyWith =>
      _PaginationCopyWithImpl<Pagination, Pagination>(
        this as Pagination,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PaginationMapper.ensureInitialized().stringifyValue(
      this as Pagination,
    );
  }

  @override
  bool operator ==(Object other) {
    return PaginationMapper.ensureInitialized().equalsValue(
      this as Pagination,
      other,
    );
  }

  @override
  int get hashCode {
    return PaginationMapper.ensureInitialized().hashValue(this as Pagination);
  }
}

extension PaginationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, Pagination, $Out> {
  PaginationCopyWith<$R, Pagination, $Out> get $asPagination =>
      $base.as((v, t, t2) => _PaginationCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PaginationCopyWith<$R, $In extends Pagination, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? index, int? pageSize, int? resultCount, int? totalCount});
  PaginationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _PaginationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Pagination, $Out>
    implements PaginationCopyWith<$R, Pagination, $Out> {
  _PaginationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Pagination> $mapper =
      PaginationMapper.ensureInitialized();
  @override
  $R call({int? index, int? pageSize, int? resultCount, int? totalCount}) =>
      $apply(
        FieldCopyWithData({
          if (index != null) #index: index,
          if (pageSize != null) #pageSize: pageSize,
          if (resultCount != null) #resultCount: resultCount,
          if (totalCount != null) #totalCount: totalCount,
        }),
      );
  @override
  Pagination $make(CopyWithData data) => Pagination(
    index: data.get(#index, or: $value.index),
    pageSize: data.get(#pageSize, or: $value.pageSize),
    resultCount: data.get(#resultCount, or: $value.resultCount),
    totalCount: data.get(#totalCount, or: $value.totalCount),
  );

  @override
  PaginationCopyWith<$R2, Pagination, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PaginationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModEnvelopeMapper extends ClassMapperBase<ModEnvelope> {
  ModEnvelopeMapper._();

  static ModEnvelopeMapper? _instance;
  static ModEnvelopeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModEnvelopeMapper._());
      ModMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModEnvelope';

  static Mod _$data(ModEnvelope v) => v.data;
  static const Field<ModEnvelope, Mod> _f$data = Field('data', _$data);

  @override
  final MappableFields<ModEnvelope> fields = const {#data: _f$data};

  static ModEnvelope _instantiate(DecodingData data) {
    return ModEnvelope(data: data.dec(_f$data));
  }

  @override
  final Function instantiate = _instantiate;

  static ModEnvelope fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModEnvelope>(map);
  }

  static ModEnvelope fromJson(String json) {
    return ensureInitialized().decodeJson<ModEnvelope>(json);
  }
}

mixin ModEnvelopeMappable {
  String toJson() {
    return ModEnvelopeMapper.ensureInitialized().encodeJson<ModEnvelope>(
      this as ModEnvelope,
    );
  }

  Map<String, dynamic> toMap() {
    return ModEnvelopeMapper.ensureInitialized().encodeMap<ModEnvelope>(
      this as ModEnvelope,
    );
  }

  ModEnvelopeCopyWith<ModEnvelope, ModEnvelope, ModEnvelope> get copyWith =>
      _ModEnvelopeCopyWithImpl<ModEnvelope, ModEnvelope>(
        this as ModEnvelope,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModEnvelopeMapper.ensureInitialized().stringifyValue(
      this as ModEnvelope,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModEnvelopeMapper.ensureInitialized().equalsValue(
      this as ModEnvelope,
      other,
    );
  }

  @override
  int get hashCode {
    return ModEnvelopeMapper.ensureInitialized().hashValue(this as ModEnvelope);
  }
}

extension ModEnvelopeValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModEnvelope, $Out> {
  ModEnvelopeCopyWith<$R, ModEnvelope, $Out> get $asModEnvelope =>
      $base.as((v, t, t2) => _ModEnvelopeCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModEnvelopeCopyWith<$R, $In extends ModEnvelope, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ModCopyWith<$R, Mod, Mod> get data;
  $R call({Mod? data});
  ModEnvelopeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ModEnvelopeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModEnvelope, $Out>
    implements ModEnvelopeCopyWith<$R, ModEnvelope, $Out> {
  _ModEnvelopeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModEnvelope> $mapper =
      ModEnvelopeMapper.ensureInitialized();
  @override
  ModCopyWith<$R, Mod, Mod> get data =>
      $value.data.copyWith.$chain((v) => call(data: v));
  @override
  $R call({Mod? data}) =>
      $apply(FieldCopyWithData({if (data != null) #data: data}));
  @override
  ModEnvelope $make(CopyWithData data) =>
      ModEnvelope(data: data.get(#data, or: $value.data));

  @override
  ModEnvelopeCopyWith<$R2, ModEnvelope, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModEnvelopeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModFileEnvelopeMapper extends ClassMapperBase<ModFileEnvelope> {
  ModFileEnvelopeMapper._();

  static ModFileEnvelopeMapper? _instance;
  static ModFileEnvelopeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModFileEnvelopeMapper._());
      ModFileMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModFileEnvelope';

  static ModFile _$data(ModFileEnvelope v) => v.data;
  static const Field<ModFileEnvelope, ModFile> _f$data = Field('data', _$data);

  @override
  final MappableFields<ModFileEnvelope> fields = const {#data: _f$data};

  static ModFileEnvelope _instantiate(DecodingData data) {
    return ModFileEnvelope(data: data.dec(_f$data));
  }

  @override
  final Function instantiate = _instantiate;

  static ModFileEnvelope fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModFileEnvelope>(map);
  }

  static ModFileEnvelope fromJson(String json) {
    return ensureInitialized().decodeJson<ModFileEnvelope>(json);
  }
}

mixin ModFileEnvelopeMappable {
  String toJson() {
    return ModFileEnvelopeMapper.ensureInitialized()
        .encodeJson<ModFileEnvelope>(this as ModFileEnvelope);
  }

  Map<String, dynamic> toMap() {
    return ModFileEnvelopeMapper.ensureInitialized().encodeMap<ModFileEnvelope>(
      this as ModFileEnvelope,
    );
  }

  ModFileEnvelopeCopyWith<ModFileEnvelope, ModFileEnvelope, ModFileEnvelope>
  get copyWith =>
      _ModFileEnvelopeCopyWithImpl<ModFileEnvelope, ModFileEnvelope>(
        this as ModFileEnvelope,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModFileEnvelopeMapper.ensureInitialized().stringifyValue(
      this as ModFileEnvelope,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModFileEnvelopeMapper.ensureInitialized().equalsValue(
      this as ModFileEnvelope,
      other,
    );
  }

  @override
  int get hashCode {
    return ModFileEnvelopeMapper.ensureInitialized().hashValue(
      this as ModFileEnvelope,
    );
  }
}

extension ModFileEnvelopeValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModFileEnvelope, $Out> {
  ModFileEnvelopeCopyWith<$R, ModFileEnvelope, $Out> get $asModFileEnvelope =>
      $base.as((v, t, t2) => _ModFileEnvelopeCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ModFileEnvelopeCopyWith<$R, $In extends ModFileEnvelope, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ModFileCopyWith<$R, ModFile, ModFile> get data;
  $R call({ModFile? data});
  ModFileEnvelopeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ModFileEnvelopeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModFileEnvelope, $Out>
    implements ModFileEnvelopeCopyWith<$R, ModFileEnvelope, $Out> {
  _ModFileEnvelopeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModFileEnvelope> $mapper =
      ModFileEnvelopeMapper.ensureInitialized();
  @override
  ModFileCopyWith<$R, ModFile, ModFile> get data =>
      $value.data.copyWith.$chain((v) => call(data: v));
  @override
  $R call({ModFile? data}) =>
      $apply(FieldCopyWithData({if (data != null) #data: data}));
  @override
  ModFileEnvelope $make(CopyWithData data) =>
      ModFileEnvelope(data: data.get(#data, or: $value.data));

  @override
  ModFileEnvelopeCopyWith<$R2, ModFileEnvelope, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModFileEnvelopeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModSearchResponseMapper extends ClassMapperBase<ModSearchResponse> {
  ModSearchResponseMapper._();

  static ModSearchResponseMapper? _instance;
  static ModSearchResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModSearchResponseMapper._());
      ModMapper.ensureInitialized();
      PaginationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModSearchResponse';

  static List<Mod> _$data(ModSearchResponse v) => v.data;
  static const Field<ModSearchResponse, List<Mod>> _f$data = Field(
    'data',
    _$data,
  );
  static Pagination _$pagination(ModSearchResponse v) => v.pagination;
  static const Field<ModSearchResponse, Pagination> _f$pagination = Field(
    'pagination',
    _$pagination,
  );

  @override
  final MappableFields<ModSearchResponse> fields = const {
    #data: _f$data,
    #pagination: _f$pagination,
  };

  static ModSearchResponse _instantiate(DecodingData data) {
    return ModSearchResponse(
      data: data.dec(_f$data),
      pagination: data.dec(_f$pagination),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModSearchResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModSearchResponse>(map);
  }

  static ModSearchResponse fromJson(String json) {
    return ensureInitialized().decodeJson<ModSearchResponse>(json);
  }
}

mixin ModSearchResponseMappable {
  String toJson() {
    return ModSearchResponseMapper.ensureInitialized()
        .encodeJson<ModSearchResponse>(this as ModSearchResponse);
  }

  Map<String, dynamic> toMap() {
    return ModSearchResponseMapper.ensureInitialized()
        .encodeMap<ModSearchResponse>(this as ModSearchResponse);
  }

  ModSearchResponseCopyWith<
    ModSearchResponse,
    ModSearchResponse,
    ModSearchResponse
  >
  get copyWith =>
      _ModSearchResponseCopyWithImpl<ModSearchResponse, ModSearchResponse>(
        this as ModSearchResponse,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ModSearchResponseMapper.ensureInitialized().stringifyValue(
      this as ModSearchResponse,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModSearchResponseMapper.ensureInitialized().equalsValue(
      this as ModSearchResponse,
      other,
    );
  }

  @override
  int get hashCode {
    return ModSearchResponseMapper.ensureInitialized().hashValue(
      this as ModSearchResponse,
    );
  }
}

extension ModSearchResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModSearchResponse, $Out> {
  ModSearchResponseCopyWith<$R, ModSearchResponse, $Out>
  get $asModSearchResponse => $base.as(
    (v, t, t2) => _ModSearchResponseCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ModSearchResponseCopyWith<
  $R,
  $In extends ModSearchResponse,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, Mod, ModCopyWith<$R, Mod, Mod>> get data;
  PaginationCopyWith<$R, Pagination, Pagination> get pagination;
  $R call({List<Mod>? data, Pagination? pagination});
  ModSearchResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ModSearchResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModSearchResponse, $Out>
    implements ModSearchResponseCopyWith<$R, ModSearchResponse, $Out> {
  _ModSearchResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModSearchResponse> $mapper =
      ModSearchResponseMapper.ensureInitialized();
  @override
  ListCopyWith<$R, Mod, ModCopyWith<$R, Mod, Mod>> get data => ListCopyWith(
    $value.data,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(data: v),
  );
  @override
  PaginationCopyWith<$R, Pagination, Pagination> get pagination =>
      $value.pagination.copyWith.$chain((v) => call(pagination: v));
  @override
  $R call({List<Mod>? data, Pagination? pagination}) => $apply(
    FieldCopyWithData({
      if (data != null) #data: data,
      if (pagination != null) #pagination: pagination,
    }),
  );
  @override
  ModSearchResponse $make(CopyWithData data) => ModSearchResponse(
    data: data.get(#data, or: $value.data),
    pagination: data.get(#pagination, or: $value.pagination),
  );

  @override
  ModSearchResponseCopyWith<$R2, ModSearchResponse, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ModSearchResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ModFileSearchResponseMapper
    extends ClassMapperBase<ModFileSearchResponse> {
  ModFileSearchResponseMapper._();

  static ModFileSearchResponseMapper? _instance;
  static ModFileSearchResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModFileSearchResponseMapper._());
      ModFileMapper.ensureInitialized();
      PaginationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModFileSearchResponse';

  static List<ModFile> _$data(ModFileSearchResponse v) => v.data;
  static const Field<ModFileSearchResponse, List<ModFile>> _f$data = Field(
    'data',
    _$data,
  );
  static Pagination _$pagination(ModFileSearchResponse v) => v.pagination;
  static const Field<ModFileSearchResponse, Pagination> _f$pagination = Field(
    'pagination',
    _$pagination,
  );

  @override
  final MappableFields<ModFileSearchResponse> fields = const {
    #data: _f$data,
    #pagination: _f$pagination,
  };

  static ModFileSearchResponse _instantiate(DecodingData data) {
    return ModFileSearchResponse(
      data: data.dec(_f$data),
      pagination: data.dec(_f$pagination),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ModFileSearchResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModFileSearchResponse>(map);
  }

  static ModFileSearchResponse fromJson(String json) {
    return ensureInitialized().decodeJson<ModFileSearchResponse>(json);
  }
}

mixin ModFileSearchResponseMappable {
  String toJson() {
    return ModFileSearchResponseMapper.ensureInitialized()
        .encodeJson<ModFileSearchResponse>(this as ModFileSearchResponse);
  }

  Map<String, dynamic> toMap() {
    return ModFileSearchResponseMapper.ensureInitialized()
        .encodeMap<ModFileSearchResponse>(this as ModFileSearchResponse);
  }

  ModFileSearchResponseCopyWith<
    ModFileSearchResponse,
    ModFileSearchResponse,
    ModFileSearchResponse
  >
  get copyWith =>
      _ModFileSearchResponseCopyWithImpl<
        ModFileSearchResponse,
        ModFileSearchResponse
      >(this as ModFileSearchResponse, $identity, $identity);
  @override
  String toString() {
    return ModFileSearchResponseMapper.ensureInitialized().stringifyValue(
      this as ModFileSearchResponse,
    );
  }

  @override
  bool operator ==(Object other) {
    return ModFileSearchResponseMapper.ensureInitialized().equalsValue(
      this as ModFileSearchResponse,
      other,
    );
  }

  @override
  int get hashCode {
    return ModFileSearchResponseMapper.ensureInitialized().hashValue(
      this as ModFileSearchResponse,
    );
  }
}

extension ModFileSearchResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ModFileSearchResponse, $Out> {
  ModFileSearchResponseCopyWith<$R, ModFileSearchResponse, $Out>
  get $asModFileSearchResponse => $base.as(
    (v, t, t2) => _ModFileSearchResponseCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ModFileSearchResponseCopyWith<
  $R,
  $In extends ModFileSearchResponse,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, ModFile, ModFileCopyWith<$R, ModFile, ModFile>> get data;
  PaginationCopyWith<$R, Pagination, Pagination> get pagination;
  $R call({List<ModFile>? data, Pagination? pagination});
  ModFileSearchResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ModFileSearchResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ModFileSearchResponse, $Out>
    implements ModFileSearchResponseCopyWith<$R, ModFileSearchResponse, $Out> {
  _ModFileSearchResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ModFileSearchResponse> $mapper =
      ModFileSearchResponseMapper.ensureInitialized();
  @override
  ListCopyWith<$R, ModFile, ModFileCopyWith<$R, ModFile, ModFile>> get data =>
      ListCopyWith(
        $value.data,
        (v, t) => v.copyWith.$chain(t),
        (v) => call(data: v),
      );
  @override
  PaginationCopyWith<$R, Pagination, Pagination> get pagination =>
      $value.pagination.copyWith.$chain((v) => call(pagination: v));
  @override
  $R call({List<ModFile>? data, Pagination? pagination}) => $apply(
    FieldCopyWithData({
      if (data != null) #data: data,
      if (pagination != null) #pagination: pagination,
    }),
  );
  @override
  ModFileSearchResponse $make(CopyWithData data) => ModFileSearchResponse(
    data: data.get(#data, or: $value.data),
    pagination: data.get(#pagination, or: $value.pagination),
  );

  @override
  ModFileSearchResponseCopyWith<$R2, ModFileSearchResponse, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ModFileSearchResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

