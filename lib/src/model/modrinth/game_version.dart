import 'package:dart_mappable/dart_mappable.dart';

part 'game_version.mapper.dart';

@MappableClass()
class GameVersion with GameVersionMappable {
  final String version;
  @MappableField(key: 'version_type')
  final String versionType;
  final String date;
  final bool major;

  const GameVersion({
    required this.version,
    required this.versionType,
    required this.date,
    required this.major,
  });
}
