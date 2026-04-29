import 'package:args/command_runner.dart';
import 'package:riverpod/riverpod.dart';

import '../app/providers.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/version_selection.dart';
import '../service/console.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import 'exceptions.dart';
import 'runner.dart';

abstract class GitrinthCommand extends Command<int> {
  GitrinthRunner get gitrinthRunner => runner as GitrinthRunner;

  ProviderContainer get container => gitrinthRunner.container;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  Console get console => container.read(consoleProvider);

  /// Reads a single positional argument from `argResults!.rest`. Throws
  /// [UsageError] when zero or more than one positional was supplied.
  /// [name] names the argument in the error message (e.g. `slug`).
  /// [usage] is appended to the empty-args error so callers can include
  /// the full one-liner (`gitrinth add <slug>[@<constraint>]`).
  String parseSinglePositional({required String name, String? usage}) {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      final tail = usage == null ? '' : ': $usage';
      throw UsageError('${this.name} requires a $name$tail');
    }
    if (rest.length > 1) {
      throw UsageError(
        'Unexpected arguments after $name: ${rest.skip(1).join(' ')}',
      );
    }
    return rest.first;
  }

  /// Validates that `--exact`, `--pin`, and an explicit `--constraint`
  /// (or `@<constraint>` shorthand on a positional) aren't combined in
  /// contradictory ways. [constraint] is the constraint string the
  /// caller has already extracted (or null when none was given).
  void validateConstraintFlags({
    required bool exact,
    required bool pin,
    String? constraint,
  }) {
    if (pin && exact) {
      throw const UsageError('--pin and --exact are mutually exclusive.');
    }
    if (exact && constraint != null) {
      throw const UsageError(
        '--exact has no effect when a version constraint is supplied '
        'explicitly.',
      );
    }
    if (pin && constraint != null) {
      throw const UsageError(
        '--pin has no effect when a version constraint is supplied '
        'explicitly.',
      );
    }
  }

  /// Wraps [resolveAndSync] with the standard provider plumbing every command
  /// uses (api, cache, downloader, loader resolver, console). Commands that
  /// need [SolveReporter] still construct it themselves — it's used for
  /// post-resolve reporting, not passed into the resolve.
  Future<ResolveSyncResult> runResolveAndSync({
    required ManifestIo io,
    required bool offline,
    bool dryRun = false,
    bool enforce = false,
    Set<String> freshSlugs = const {},
    Set<String> relaxConstraints = const {},
    ModsYaml? manifestOverride,
    SolveType solveType = SolveType.get,
  }) {
    return resolveAndSync(
      io: io,
      console: console,
      apiFactory: read(modrinthApiFactoryProvider),
      cache: read(cacheProvider),
      downloader: read(downloaderProvider),
      modLoaderResolver: read(modLoaderVersionResolverProvider),
      pluginLoaderResolver: read(pluginLoaderVersionResolverProvider),
      offline: offline,
      dryRun: dryRun,
      enforce: enforce,
      freshSlugs: freshSlugs,
      relaxConstraints: relaxConstraints,
      manifestOverride: manifestOverride,
      solveType: solveType,
    );
  }
}
