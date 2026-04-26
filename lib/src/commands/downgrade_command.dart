import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/constraint.dart';
import '../model/resolver/version_selection.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/solve_report.dart';

class DowngradeCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'downgrade';

  @override
  String get description =>
      "Resolve the current modpack's entries to their oldest compatible "
      'versions.';

  @override
  String get invocation => 'gitrinth downgrade [<slug>...] [arguments]';

  DowngradeCommand() {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: "Report what entries would change but don't change any.",
    );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final dryRun = results['dry-run'] as bool;
    final offline = readOfflineFlag();
    final requestedSlugs = results.rest;

    final io = ManifestIo();
    final manifest = io.readModsYaml();

    // Identify Modrinth-source entries. Marker entries
    // (`gitrinth:not-found`/`gitrinth:disabled-by-conflict`) and
    // url:/path: entries don't take part — they have no version pool
    // to walk.
    final modrinthSlugs = <String>{};
    final markerSlugs = <String>{};
    final nonModrinthSlugs = <String>{};
    for (final section in Section.values) {
      manifest.sectionEntries(section).forEach((slug, entry) {
        if (entry.source is ModrinthEntrySource) {
          if (isAnyGitrinthMarker(entry.constraintRaw)) {
            markerSlugs.add(slug);
          } else {
            modrinthSlugs.add(slug);
          }
        } else {
          nonModrinthSlugs.add(slug);
        }
      });
    }
    final allSlugs = {...modrinthSlugs, ...markerSlugs, ...nonModrinthSlugs};

    Set<String> targets;
    if (requestedSlugs.isEmpty) {
      targets = {...modrinthSlugs};
    } else {
      final unknown = requestedSlugs
          .where((s) => !allSlugs.contains(s))
          .toList();
      if (unknown.isNotEmpty) {
        throw UsageError(
          'unknown entry/entries in mods.yaml: ${unknown.join(', ')}',
        );
      }
      targets = <String>{};
      for (final slug in requestedSlugs) {
        if (modrinthSlugs.contains(slug)) {
          targets.add(slug);
        } else if (markerSlugs.contains(slug)) {
          console.message(
            "skipping '$slug' — marker entry has no version to downgrade.",
          );
        } else {
          console.io(
            "skipping '$slug' — non-Modrinth source has no version to downgrade.",
          );
        }
      }
    }

    final api = read(modrinthApiProvider);
    final cache = read(cacheProvider);
    final downloader = read(downloaderProvider);
    final loaderResolver = read(loaderVersionResolverProvider);
    final reporter = SolveReporter(console);

    final result = await resolveAndSync(
      io: io,
      console: console,
      api: api,
      cache: cache,
      downloader: downloader,
      loaderResolver: loaderResolver,
      offline: offline,
      dryRun: dryRun,
      // Drop lock pins for every target so the resolver actually walks
      // the candidate list under SolveType.downgrade instead of
      // preserving the existing pin.
      freshSlugs: targets,
      solveType: SolveType.downgrade,
    );

    if (result.exitCode != exitOk) {
      return result.exitCode;
    }
    if (dryRun) {
      return exitOk;
    }
    reporter.printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    if (offline) {
      console.warn(
        'Downgrading when offline may not update you to the oldest '
        'versions of your dependencies.',
      );
    }
    return exitOk;
  }
}
