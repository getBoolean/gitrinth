import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exit_codes.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/solve_report.dart';

class GetCommand extends GitrinthCommand {
  @override
  String get name => 'get';

  @override
  String get description => "Get the current modpack's entries.";

  @override
  String get invocation => 'gitrinth get [arguments]';

  GetCommand() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: "Report what entries would change but don't change any.",
      )
      ..addFlag(
        'enforce-lockfile',
        negatable: false,
        help:
            'Enforce mods.lock. '
            'Fail `gitrinth get` if the current `mods.lock` '
            'does not exactly specify a valid resolution of `mods.yaml` '
            'or if any content hash has changed.\n'
            'Useful for CI or deploying to production.',
      );
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final dryRun = results['dry-run'] as bool;
    final enforce = results['enforce-lockfile'] as bool;

    final api = read(modrinthApiProvider);
    final cache = read(cacheProvider);
    final downloader = read(downloaderProvider);
    final loaderResolver = read(loaderVersionResolverProvider);
    final reporter = SolveReporter(console);

    final io = ManifestIo();
    final result = await resolveAndSync(
      io: io,
      console: console,
      api: api,
      cache: cache,
      downloader: downloader,
      loaderResolver: loaderResolver,
      verbose: gitrinthRunner.verbose,
      dryRun: dryRun,
      enforce: enforce,
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
    return exitOk;
  }
}
