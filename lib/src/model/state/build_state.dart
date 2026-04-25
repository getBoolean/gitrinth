import 'package:dart_mappable/dart_mappable.dart';

part 'build_state.mapper.dart';

/// Per-env ledger of files installed by the most recent `gitrinth build`
/// run. Persisted to `build/<env>/.gitrinth-state.yaml`.
///
/// The ledger is the source of truth for what `build` may safely prune on
/// re-run: files in the prior ledger but not in the new desired set are
/// deleted; files NOT in the prior ledger (user-dropped jars, server
/// installer outputs) are never touched. This mirrors packwiz-installer's
/// `cachedFiles` map — see [`docs/todo.md`](../../../docs/todo.md) for
/// the design rationale.
///
/// `--no-prune` on `gitrinth build` skips the deletion pass while still
/// writing the new ledger.
@MappableEnum()
enum LedgerEnv { client, server }

/// Provenance of a single ledger entry. Discriminator distinguishes a
/// resolved mod entry (`mod-entry`) from a loose-file declaration
/// (`file-entry`); the two flow through different parts of the
/// orchestrator and need different identifying metadata.
@MappableClass(discriminatorKey: 'kind')
sealed class LedgerSource with LedgerSourceMappable {
  const LedgerSource();
}

/// Resolved mod/pack entry written from `lock.sectionFor(section)`.
@MappableClass(discriminatorValue: 'mod-entry')
class LedgerModSource extends LedgerSource with LedgerModSourceMappable {
  final String section;
  final String slug;
  final String? sha512;

  const LedgerModSource({
    required this.section,
    required this.slug,
    this.sha512,
  });
}

/// Loose file declared in the top-level `files:` section.
@MappableClass(discriminatorValue: 'file-entry')
class LedgerFileSource extends LedgerSource with LedgerFileSourceMappable {
  final String key;
  final bool preserve;
  final String sourcePath;
  final String? sha512;

  const LedgerFileSource({
    required this.key,
    required this.preserve,
    required this.sourcePath,
    this.sha512,
  });
}

@MappableClass()
class BuildLedger with BuildLedgerMappable {
  /// Version of gitrinth that wrote this ledger. Recorded so future
  /// migrations can detect ledgers from older formats.
  final String gitrinthVersion;
  final LedgerEnv env;

  /// ISO-8601 UTC timestamp of when the ledger was written. Informational;
  /// build does not consult it.
  final String generatedAt;

  /// File entries keyed by destination path relative to the env root.
  final Map<String, LedgerSource> files;

  const BuildLedger({
    required this.gitrinthVersion,
    required this.env,
    required this.generatedAt,
    this.files = const {},
  });
}
