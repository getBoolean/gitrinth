import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'mods_overrides.mapper.dart';

@MappableClass()
class ModsOverrides with ModsOverridesMappable {
  final Map<String, ModEntry> overrides;

  const ModsOverrides({this.overrides = const {}});
}
