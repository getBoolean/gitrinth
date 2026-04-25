import 'package:dart_mappable/dart_mappable.dart';

import '../manifest/mods_yaml.dart';
import '../modrinth/version.dart' as modrinth;
import '../modrinth/version_file.dart';

part 'result.mapper.dart';

@MappableClass()
class ResolvedEntry with ResolvedEntryMappable {
  final String slug;
  final Section section;
  final Environment env;
  final bool auto;
  final modrinth.Version version;
  final VersionFile file;
  final bool optional;

  /// Forward dep-graph edges: slugs this entry directly required at
  /// resolution time. Sorted ascending. Persists to `mods.lock` so
  /// `gitrinth upgrade --unlock-transitive` can compute the transitive
  /// closure of named targets without a re-resolve.
  final List<String> dependencies;

  const ResolvedEntry({
    required this.slug,
    required this.section,
    required this.env,
    required this.auto,
    required this.version,
    required this.file,
    this.optional = false,
    this.dependencies = const [],
  });
}

@MappableClass()
class ResolutionResult with ResolutionResultMappable {
  final List<ResolvedEntry> entries;

  const ResolutionResult(this.entries);
}
