// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project_overrides.dart';

class ProjectOverridesMapper extends ClassMapperBase<ProjectOverrides> {
  ProjectOverridesMapper._();

  static ProjectOverridesMapper? _instance;
  static ProjectOverridesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectOverridesMapper._());
      ModEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectOverrides';

  static Map<String, ModEntry> _$entries(ProjectOverrides v) => v.entries;
  static const Field<ProjectOverrides, Map<String, ModEntry>> _f$entries =
      Field('entries', _$entries, opt: true, def: const {});

  @override
  final MappableFields<ProjectOverrides> fields = const {#entries: _f$entries};

  static ProjectOverrides _instantiate(DecodingData data) {
    return ProjectOverrides(entries: data.dec(_f$entries));
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectOverrides fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectOverrides>(map);
  }

  static ProjectOverrides fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectOverrides>(json);
  }
}

mixin ProjectOverridesMappable {
  String toJson() {
    return ProjectOverridesMapper.ensureInitialized()
        .encodeJson<ProjectOverrides>(this as ProjectOverrides);
  }

  Map<String, dynamic> toMap() {
    return ProjectOverridesMapper.ensureInitialized()
        .encodeMap<ProjectOverrides>(this as ProjectOverrides);
  }

  ProjectOverridesCopyWith<ProjectOverrides, ProjectOverrides, ProjectOverrides>
  get copyWith =>
      _ProjectOverridesCopyWithImpl<ProjectOverrides, ProjectOverrides>(
        this as ProjectOverrides,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProjectOverridesMapper.ensureInitialized().stringifyValue(
      this as ProjectOverrides,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProjectOverridesMapper.ensureInitialized().equalsValue(
      this as ProjectOverrides,
      other,
    );
  }

  @override
  int get hashCode {
    return ProjectOverridesMapper.ensureInitialized().hashValue(
      this as ProjectOverrides,
    );
  }
}

extension ProjectOverridesValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProjectOverrides, $Out> {
  ProjectOverridesCopyWith<$R, ProjectOverrides, $Out>
  get $asProjectOverrides =>
      $base.as((v, t, t2) => _ProjectOverridesCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ProjectOverridesCopyWith<$R, $In extends ProjectOverrides, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get entries;
  $R call({Map<String, ModEntry>? entries});
  ProjectOverridesCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ProjectOverridesCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProjectOverrides, $Out>
    implements ProjectOverridesCopyWith<$R, ProjectOverrides, $Out> {
  _ProjectOverridesCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProjectOverrides> $mapper =
      ProjectOverridesMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, ModEntry, ModEntryCopyWith<$R, ModEntry, ModEntry>>
  get entries => MapCopyWith(
    $value.entries,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(entries: v),
  );
  @override
  $R call({Map<String, ModEntry>? entries}) =>
      $apply(FieldCopyWithData({if (entries != null) #entries: entries}));
  @override
  ProjectOverrides $make(CopyWithData data) =>
      ProjectOverrides(entries: data.get(#entries, or: $value.entries));

  @override
  ProjectOverridesCopyWith<$R2, ProjectOverrides, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ProjectOverridesCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

