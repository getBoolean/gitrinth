import 'package:dart_mappable/dart_mappable.dart';

import 'cf_mod_file.dart';

part 'cf_mod.mapper.dart';

/// A CurseForge mod project, as returned by `/v1/mods/{id}` and
/// `/v1/mods/search`.
@MappableClass()
class Mod with ModMappable {
  final int id;
  final int gameId;
  final String name;
  final String slug;
  final String? summary;

  /// CurseForge `classId` — content type (mods=6, plugins=5,
  /// resourcePacks=12, etc.). Mapped from the manifest [Section]
  /// taxonomy in `cf_constants.dart`.
  final int classId;

  final List<ModFile> latestFiles;

  /// Whether CurseForge permits programmatic distribution of this mod's
  /// files. When `false`, [ModFile.downloadUrl] is `null` and Part 4
  /// raises a "manual download required" error rather than attempting
  /// to fetch. Defaults to `true` for response shapes that omit the
  /// field — older CF endpoints didn't include it.
  final bool allowModDistribution;

  const Mod({
    required this.id,
    required this.gameId,
    required this.name,
    required this.slug,
    this.summary,
    required this.classId,
    this.latestFiles = const [],
    this.allowModDistribution = true,
  });
}
