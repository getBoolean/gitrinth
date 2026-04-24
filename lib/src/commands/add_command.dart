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
  String get invocation => 'gitrinth add <slug>[@<constraint>] [arguments]';

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
        help:
            'Use a path: source. Marks the pack non-publishable when added to mods.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the edit without writing.',
      )
      ..addMultiOption(
        'accepts-mc',
        valueHelp: 'mc-version',
        help:
            'Additively widen the Minecraft version filter for this entry '
            'when querying Modrinth, and persist the list under '
            '`accepts-mc` in mods.yaml. Repeatable. Use when a mod works '
            "on the pack's mc-version but the author tagged only adjacent "
            'versions on Modrinth.',
      )
      ..addFlag(
        'exact',
        negatable: false,
        help:
            "Preserve the resolved version's build metadata inside the caret "
            'constraint (e.g. ^6.0.10+mc1.21.1 instead of ^6.0.10).',
      )
      ..addFlag(
        'pin',
        negatable: false,
        help:
            'Write the resolved version as a bare semver (no caret), '
            'freezing the entry in place. Equivalent to `add` followed by '
            '`pin`.',
      )
      ..addOption(
        'type',
        allowed: typeFlagValues,
        help:
            'Override the inferred section. Required for --url/--path '
            'entries whose filename does not uniquely identify a type '
            '(e.g. .zip files).',
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
    final exactFlag = argResults!['exact'] as bool;
    final pinFlag = argResults!['pin'] as bool;
    final typeOverride = sectionFromTypeFlag(argResults!['type'] as String?);
    final acceptsMc = _parseAcceptsMcFlag(
      argResults!['accepts-mc'] as List<String>,
    );
    if (urlOpt != null && pathOpt != null) {
      throw const UsageError('--url and --path are mutually exclusive.');
    }
    if (acceptsMc.isNotEmpty && (urlOpt != null || pathOpt != null)) {
      throw const UsageError(
        '--accepts-mc applies to Modrinth-sourced entries; cannot combine '
        'with --url or --path.',
      );
    }
    if (exactFlag && (urlOpt != null || pathOpt != null)) {
      throw const UsageError(
        '--exact applies to Modrinth-sourced entries; cannot combine '
        'with --url or --path.',
      );
    }
    if (pinFlag && exactFlag) {
      throw const UsageError('--pin and --exact are mutually exclusive.');
    }
    if (pinFlag && (urlOpt != null || pathOpt != null)) {
      throw const UsageError(
        '--pin applies to Modrinth-sourced entries; cannot combine with '
        '--url or --path.',
      );
    }

    final (:slug, :constraintRaw) = _parsePositional(positional);
    if (exactFlag && constraintRaw != null) {
      throw const UsageError(
        '--exact has no effect when a version constraint is supplied '
        'explicitly.',
      );
    }
    if (pinFlag && constraintRaw != null) {
      throw const UsageError(
        '--pin has no effect when a version constraint is supplied '
        'explicitly.',
      );
    }

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
      if (typeOverride != null) {
        section = typeOverride;
      } else {
        final inferred = inferSectionFromFilename(filename);
        if (inferred == null) {
          throw ValidationError(
            'cannot infer section for $filename; pass '
            '--type <mod|resourcepack|datapack|shader> to choose one '
            '(or rename the file to use a .jar extension for mods).',
          );
        }
        section = inferred;
      }

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
      final inferredSection = inferSectionFromProject(
        projectType: project.projectType,
        loaders: project.loaders,
      );
      if (typeOverride != null && typeOverride != inferredSection) {
        console.warn(
          "--type ${sectionKeyFor(typeOverride)} overrides the inferred "
          "section '${sectionKeyFor(inferredSection)}' for '$slug'.",
        );
        section = typeOverride;
      } else {
        section = inferredSection;
      }

      // Resolve a default constraint (caret-pin the newest release's
      // major.minor.patch, dropping build metadata) when the user didn't
      // pass one. `--exact` keeps the full resolved version inside the caret.
      final String effectiveConstraint;
      if (constraintRaw == null) {
        final latest = await _pickLatestReleaseVersion(
          api: api,
          slug: slug,
          section: section,
          loaderConfig: existingManifest.loader,
          mcVersion: existingManifest.mcVersion,
          acceptsMc: acceptsMc,
        );
        if (latest == null) {
          final widened = acceptsMc.isEmpty
              ? ''
              : ' (widened with accepts-mc=${acceptsMc.join(",")})';
          throw UserError(
            "No release version of '$slug' is compatible with "
            "loader=${_loaderNameForSection(existingManifest.loader, section) ?? '<none>'} "
            "mc=${existingManifest.mcVersion}$widened. "
            'Pass `@<version>` explicitly to pin an alpha/beta.',
          );
        }
        if (exactFlag) {
          effectiveConstraint = '^$latest';
        } else if (pinFlag) {
          effectiveConstraint = bareVersionForPin(latest);
        } else {
          final parsed = parseModrinthVersion(latest);
          effectiveConstraint =
              '^${parsed.major}.${parsed.minor}.${parsed.patch}';
        }
      } else {
        // Validate the user-supplied constraint so a bad `@xyz` fails fast
        // with a single-line error before we touch mods.yaml.
        final channel = parseChannelToken(constraintRaw);
        if (channel == null) {
          parseConstraint(constraintRaw); // throws ValidationError on bad input
        }
        effectiveConstraint = constraintRaw;
      }

      final needsLongForm =
          (envOpt != null && envOpt != 'both') || acceptsMc.isNotEmpty;
      if (needsLongForm) {
        final long = <String, Object?>{'version': effectiveConstraint};
        if (envOpt != null && envOpt != 'both') long['environment'] = envOpt;
        if (acceptsMc.isNotEmpty) {
          long['accepts-mc'] = acceptsMc.length == 1
              ? acceptsMc.first
              : acceptsMc;
        }
        longForm = long;
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
      console.info(
        _describeEntry(
          slug: slug,
          shorthand: longForm == null ? writtenValue : null,
          longForm: longForm,
        ),
      );
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

  // Same permissive pattern the YAML parser uses for accepts-mc.
  // Accepts releases, pre/rc, and snapshots; Modrinth validates the
  // actual tag server-side.
  static final _acceptsMcPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');

  List<String> _parseAcceptsMcFlag(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final entry in raw) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      if (!_acceptsMcPattern.hasMatch(trimmed)) {
        throw UserError(
          '--accepts-mc "$trimmed" is not a valid Minecraft version tag '
          '(expected forms like "1.21", "1.20.1", "24w10a", or '
          '"1.21-pre1").',
        );
      }
      if (seen.add(trimmed)) out.add(trimmed);
    }
    return out;
  }

  Future<String?> _pickLatestReleaseVersion({
    required ModrinthApi api,
    required String slug,
    required Section section,
    required LoaderConfig loaderConfig,
    required String mcVersion,
    List<String> acceptsMc = const [],
  }) async {
    final loaderFilter = _filterLoadersForSection(loaderConfig, section);
    final gameVersions = <String>{mcVersion, ...acceptsMc}.toList();
    final List<modrinth.Version> versions;
    try {
      versions = await api.listVersions(
        slug,
        loadersJson: loaderFilter == null
            ? null
            : encodeFilterArray(loaderFilter),
        gameVersionsJson: encodeFilterArray(gameVersions),
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

  List<String>? _filterLoadersForSection(LoaderConfig config, Section section) {
    switch (section) {
      case Section.mods:
        return [config.mods.name];
      case Section.shaders:
        return config.shaders == null ? null : [config.shaders!.name];
      case Section.resourcePacks:
        return const ['minecraft'];
      case Section.dataPacks:
        return const ['datapack'];
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
