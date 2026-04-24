import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/project.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../service/manifest_io.dart';
import '../service/modrinth_api.dart';
import '../service/modrinth_project_url.dart';
import '../service/resolve_and_sync.dart';
import '../service/section_inference.dart';
import '../service/solve_report.dart';
import 'add_command_editor.dart';

class AddCommand extends GitrinthCommand {
  @override
  String get name => 'add';

  @override
  String get description => 'Add an entry to a section.';

  @override
  String get invocation =>
      'gitrinth add <slug>[@<constraint>] [arguments]';

  AddCommand() {
    argParser
      ..addOption(
        'env',
        allowed: ['client', 'server', 'both'],
        valueHelp: 'client|server|both',
        help: 'Restrict the entry to a side.',
      )
      ..addOption(
        'url',
        valueHelp: 'url',
        help:
            'Use a url: source. Marks the pack non-publishable when added to mods.',
      )
      ..addOption(
        'path',
        valueHelp: 'path',
        help: 'Use a path: source.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the edit without writing.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError(
        'add requires a slug: gitrinth add <slug>[@<constraint>]',
      );
    }
    if (rest.length > 1) {
      throw UsageError(
        'Unexpected arguments after slug: ${rest.skip(1).join(' ')}',
      );
    }

    final positional = rest.first;
    final urlOpt = argResults!['url'] as String?;
    final pathOpt = argResults!['path'] as String?;
    final envOpt = argResults!['env'] as String?;
    final dryRun = argResults!['dry-run'] as bool;
    if (urlOpt != null && pathOpt != null) {
      throw const UsageError('--url and --path are mutually exclusive.');
    }

    final (:slug, :constraintRaw) = _parsePositional(positional);

    final io = ManifestIo();
    final existingManifest = io.readModsYaml();

    // Duplicate check — scan every section. `dart pub add` rejects adds for
    // already-declared packages; we mirror that.
    for (final section in Section.values) {
      if (existingManifest.sectionEntries(section).containsKey(slug)) {
        throw UserError(
          "'$slug' is already in mods.yaml under "
          "'${sectionKeyFor(section)}'. "
          'Edit the entry directly or remove it first.',
        );
      }
    }

    final Section section;
    final String? writtenValue;
    final Map<String, Object?>? longForm;

    if (urlOpt != null || pathOpt != null) {
      // Local / url: source — no Modrinth round-trip.
      final filename = urlOpt ?? pathOpt!;
      final inferred = inferSectionFromFilename(filename);
      if (inferred == null) {
        throw ValidationError(
          'cannot infer section for $filename; sections for --url/--path '
          'entries are inferred from the filename. Rename the file to use '
          'a .jar extension for mods, or add the entry manually to mods.yaml.',
        );
      }
      section = inferred;

      final long = <String, Object?>{};
      if (urlOpt != null) long['url'] = urlOpt;
      if (pathOpt != null) long['path'] = pathOpt;
      if (envOpt != null && envOpt != 'both') long['environment'] = envOpt;
      longForm = long;
      writtenValue = null;
    } else {
      // Modrinth source.
      final api = read(modrinthApiProvider);
      final Project project;
      try {
        project = await api.getProject(slug);
      } on DioException catch (e) {
        final err = e.error;
        if (err is GitrinthException) throw err;
        rethrow;
      }
      section = inferSectionFromProject(
        projectType: project.projectType,
        loaders: project.loaders,
      );

      // Resolve a default constraint (caret-pin the newest release) when
      // the user didn't pass one.
      final String effectiveConstraint;
      if (constraintRaw == null) {
        final latest = await _pickLatestReleaseVersion(
          api: api,
          slug: slug,
          section: section,
          loaderConfig: existingManifest.loader,
          mcVersion: existingManifest.mcVersion,
        );
        if (latest == null) {
          throw UserError(
            "No release version of '$slug' is compatible with "
            "loader=${_loaderNameForSection(existingManifest.loader, section) ?? '<none>'} "
            "mc=${existingManifest.mcVersion}. "
            'Pass `@<version>` explicitly to pin an alpha/beta.',
          );
        }
        effectiveConstraint = '^$latest';
      } else {
        // Validate the user-supplied constraint so a bad `@xyz` fails fast
        // with a single-line error before we touch mods.yaml.
        final channel = parseChannelToken(constraintRaw);
        if (channel == null) {
          parseConstraint(constraintRaw); // throws ValidationError on bad input
        }
        effectiveConstraint = constraintRaw;
      }

      if (envOpt != null && envOpt != 'both') {
        longForm = <String, Object?>{
          'version': effectiveConstraint,
          'environment': envOpt,
        };
        writtenValue = null;
      } else {
        longForm = null;
        writtenValue = effectiveConstraint;
      }
    }

    final yamlText = File(io.modsYamlPath).readAsStringSync();
    final updated = injectEntry(
      yamlText,
      section: section,
      slug: slug,
      shorthandValue: longForm == null ? writtenValue : null,
      longForm: longForm,
    );

    if (dryRun) {
      console.info('Would add to ${sectionKeyFor(section)}:');
      console.info(_describeEntry(
        slug: slug,
        shorthand: longForm == null ? writtenValue : null,
        longForm: longForm,
      ));
      return exitOk;
    }

    io.writeModsYaml(updated);

    final api = read(modrinthApiProvider);
    final cache = read(cacheProvider);
    final downloader = read(downloaderProvider);
    final reporter = SolveReporter(console);

    final result = await resolveAndSync(
      io: io,
      console: console,
      api: api,
      cache: cache,
      downloader: downloader,
      verbose: gitrinthRunner.verbose,
    );
    if (result.exitCode != exitOk) return result.exitCode;
    reporter.printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    return exitOk;
  }

  ({String slug, String? constraintRaw}) _parsePositional(String input) {
    final atIndex = input.lastIndexOf('@');
    String prefix;
    String? maybeConstraint;
    if (atIndex <= 0 || atIndex == input.length - 1) {
      prefix = input;
      maybeConstraint = null;
    } else {
      prefix = input.substring(0, atIndex);
      maybeConstraint = input.substring(atIndex + 1);
    }

    final urlRef = parseModrinthProjectUrl(prefix);
    if (urlRef != null) {
      return (slug: urlRef.slug, constraintRaw: maybeConstraint);
    }

    // Not a URL — maybe `@` was actually part of the slug/URL? Try the
    // whole input once more to catch `modrinth.com/mod/foo@bar` shapes.
    final urlRefFull = parseModrinthProjectUrl(input);
    if (urlRefFull != null) {
      return (slug: urlRefFull.slug, constraintRaw: null);
    }

    return (slug: prefix, constraintRaw: maybeConstraint);
  }

  Future<String?> _pickLatestReleaseVersion({
    required ModrinthApi api,
    required String slug,
    required Section section,
    required LoaderConfig loaderConfig,
    required String mcVersion,
  }) async {
    final loaderFilter = _filterLoadersForSection(loaderConfig, section);
    final List<modrinth.Version> versions;
    try {
      versions = await api.listVersions(
        slug,
        loadersJson:
            loaderFilter == null ? null : encodeFilterArray(loaderFilter),
        gameVersionsJson: encodeFilterArray([mcVersion]),
      );
    } on DioException catch (e) {
      final err = e.error;
      if (err is GitrinthException) throw err;
      rethrow;
    }
    String? best;
    dynamic bestParsed;
    for (final v in versions) {
      if ((v.versionType ?? 'release') != 'release') continue;
      try {
        final parsed = parseModrinthVersion(v.versionNumber);
        if (bestParsed == null || parsed > bestParsed) {
          bestParsed = parsed;
          best = v.versionNumber;
        }
      } on FormatException {
        // skip — same policy as the resolver.
      }
    }
    return best;
  }

  List<String>? _filterLoadersForSection(
    LoaderConfig config,
    Section section,
  ) {
    switch (section) {
      case Section.mods:
        return [config.mods.name];
      case Section.shaders:
        return config.shaders == null ? null : [config.shaders!.name];
      case Section.resourcePacks:
      case Section.dataPacks:
        return null;
    }
  }

  String? _loaderNameForSection(LoaderConfig config, Section section) {
    switch (section) {
      case Section.mods:
        return config.mods.name;
      case Section.shaders:
        return config.shaders?.name;
      case Section.resourcePacks:
      case Section.dataPacks:
        return null;
    }
  }

  String _describeEntry({
    required String slug,
    String? shorthand,
    Map<String, Object?>? longForm,
  }) {
    if (shorthand != null) {
      return '  $slug: $shorthand';
    }
    final buf = StringBuffer('  $slug:\n');
    final entries = longForm!.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.write('    ${e.key}: ${e.value}');
      if (i < entries.length - 1) buf.write('\n');
    }
    return buf.toString();
  }
}

