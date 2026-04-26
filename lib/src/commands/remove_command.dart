import 'dart:io';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/solve_report.dart';
import 'add_command_editor.dart';
import 'remove_command_editor.dart';

class RemoveCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'remove';

  @override
  String get description => 'Removes an entry from `mods.yaml`.';

  @override
  String get invocation => 'gitrinth remove <slug> [arguments]';

  RemoveCommand() {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: "Report what entries would change but don't change any.",
    );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError('remove requires a slug: gitrinth remove <slug>');
    }
    if (rest.length > 1) {
      throw UsageError(
        'Unexpected arguments after slug: ${rest.skip(1).join(' ')}',
      );
    }

    final slug = rest.first;
    if (slug.contains('@')) {
      throw UsageError(
        "remove does not take a version — drop the '@' and pass just the "
        "slug (e.g. `gitrinth remove ${slug.split('@').first}`).",
      );
    }

    final dryRun = argResults!['dry-run'] as bool;
    final offline = readOfflineFlag();

    final io = ManifestIo();
    final manifest = io.readModsYaml();

    Section? foundSection;
    ModEntry? foundEntry;
    for (final section in Section.values) {
      final entries = manifest.sectionEntries(section);
      final entry = entries[slug];
      if (entry != null) {
        foundSection = section;
        foundEntry = entry;
        break;
      }
    }

    if (foundSection == null || foundEntry == null) {
      throw UserError("'$slug' is not in mods.yaml.");
    }

    final yamlText = File(io.modsYamlPath).readAsStringSync();
    final updated = removeEntry(yamlText, section: foundSection, slug: slug);

    if (dryRun) {
      console.message('Would remove from ${sectionKeyFor(foundSection)}:');
      console.message(_describeEntry(slug, foundEntry, foundSection));
      return exitOk;
    }

    io.writeModsYaml(updated);

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
    );
    if (result.exitCode != exitOk) return result.exitCode;
    reporter.printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    return exitOk;
  }

  String _describeEntry(String slug, ModEntry entry, Section section) {
    final src = entry.source;
    if (src is UrlEntrySource) {
      return '  $slug: url ${src.url}';
    }
    if (src is PathEntrySource) {
      return '  $slug: path ${src.path}';
    }
    final parts = <String>[];
    if (entry.constraintRaw != null) {
      parts.add(entry.constraintRaw!);
    } else if (entry.channel != null) {
      parts.add(entry.channel!.name);
    }
    final defaults = defaultSidesFor(section);
    if (entry.client != defaults.client) {
      parts.add('[client=${entry.client.name}]');
    }
    if (entry.server != defaults.server) {
      parts.add('[server=${entry.server.name}]');
    }
    if (parts.isEmpty) return '  $slug';
    return '  $slug: ${parts.join(' ')}';
  }
}
