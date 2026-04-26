import 'package:args/command_runner.dart';
import 'package:riverpod/riverpod.dart';

import '../app/providers.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/version_selection.dart';
import '../service/console.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import 'runner.dart';

abstract class GitrinthCommand extends Command<int> {
  GitrinthRunner get gitrinthRunner => runner as GitrinthRunner;

  ProviderContainer get container => gitrinthRunner.container;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  Console get console => container.read(consoleProvider);

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
      api: read(modrinthApiProvider),
      cache: read(cacheProvider),
      downloader: read(downloaderProvider),
      loaderResolver: read(loaderVersionResolverProvider),
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
