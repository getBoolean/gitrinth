// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project.dart';

class ProjectMapper extends ClassMapperBase<Project> {
  ProjectMapper._();

  static ProjectMapper? _instance;
  static ProjectMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Project';

  static String _$id(Project v) => v.id;
  static const Field<Project, String> _f$id = Field('id', _$id);
  static String _$slug(Project v) => v.slug;
  static const Field<Project, String> _f$slug = Field('slug', _$slug);
  static String _$title(Project v) => v.title;
  static const Field<Project, String> _f$title = Field('title', _$title);
  static String _$projectType(Project v) => v.projectType;
  static const Field<Project, String> _f$projectType = Field(
    'projectType',
    _$projectType,
    key: r'project_type',
  );
  static List<String> _$loaders(Project v) => v.loaders;
  static const Field<Project, List<String>> _f$loaders = Field(
    'loaders',
    _$loaders,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<Project> fields = const {
    #id: _f$id,
    #slug: _f$slug,
    #title: _f$title,
    #projectType: _f$projectType,
    #loaders: _f$loaders,
  };

  static Project _instantiate(DecodingData data) {
    return Project(
      id: data.dec(_f$id),
      slug: data.dec(_f$slug),
      title: data.dec(_f$title),
      projectType: data.dec(_f$projectType),
      loaders: data.dec(_f$loaders),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Project fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Project>(map);
  }

  static Project fromJson(String json) {
    return ensureInitialized().decodeJson<Project>(json);
  }
}

mixin ProjectMappable {
  String toJson() {
    return ProjectMapper.ensureInitialized().encodeJson<Project>(
      this as Project,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectMapper.ensureInitialized().encodeMap<Project>(
      this as Project,
    );
  }

  ProjectCopyWith<Project, Project, Project> get copyWith =>
      _ProjectCopyWithImpl<Project, Project>(
        this as Project,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProjectMapper.ensureInitialized().stringifyValue(this as Project);
  }

  @override
  bool operator ==(Object other) {
    return ProjectMapper.ensureInitialized().equalsValue(
      this as Project,
      other,
    );
  }

  @override
  int get hashCode {
    return ProjectMapper.ensureInitialized().hashValue(this as Project);
  }
}

extension ProjectValueCopy<$R, $Out> on ObjectCopyWith<$R, Project, $Out> {
  ProjectCopyWith<$R, Project, $Out> get $asProject =>
      $base.as((v, t, t2) => _ProjectCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ProjectCopyWith<$R, $In extends Project, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get loaders;
  $R call({
    String? id,
    String? slug,
    String? title,
    String? projectType,
    List<String>? loaders,
  });
  ProjectCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ProjectCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Project, $Out>
    implements ProjectCopyWith<$R, Project, $Out> {
  _ProjectCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Project> $mapper =
      ProjectMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get loaders =>
      ListCopyWith(
        $value.loaders,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(loaders: v),
      );
  @override
  $R call({
    String? id,
    String? slug,
    String? title,
    String? projectType,
    List<String>? loaders,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (slug != null) #slug: slug,
      if (title != null) #title: title,
      if (projectType != null) #projectType: projectType,
      if (loaders != null) #loaders: loaders,
    }),
  );
  @override
  Project $make(CopyWithData data) => Project(
    id: data.get(#id, or: $value.id),
    slug: data.get(#slug, or: $value.slug),
    title: data.get(#title, or: $value.title),
    projectType: data.get(#projectType, or: $value.projectType),
    loaders: data.get(#loaders, or: $value.loaders),
  );

  @override
  ProjectCopyWith<$R2, Project, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ProjectCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

