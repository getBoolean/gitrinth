import 'package:dart_mappable/dart_mappable.dart';

import '../manifest/mods_lock.dart';
import '../manifest/mods_yaml.dart';
import '../modrinth/version.dart' as modrinth;
import '../modrinth/version_file.dart';

part 'result.mapper.dart';

@MappableClass()
class ResolvedEntry with ResolvedEntryMappable {
  final String slug;
  final Section section;
  final Environment env;

  /// `transitive` when the entry was pulled in by another mod's required
  /// deps, `direct` when it appears in `mods.yaml`. Mirrors dart pub's
  /// `dependency: "direct main" | "transitive"` lock-file classification —
  /// the actual dep-graph edges live in the artifact cache, not here.
  final LockedDependencyKind dependency;

  final modrinth.Version version;
  final VersionFile file;
  final bool optional;

  const ResolvedEntry({
    required this.slug,
    required this.section,
    required this.env,
    required this.dependency,
    required this.version,
    required this.file,
    this.optional = false,
  });
}

@MappableClass()
class ResolutionResult with ResolutionResultMappable {
  final List<ResolvedEntry> entries;

  const ResolutionResult(this.entries);
}
