import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
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

class AddCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'add';

  @override
  String get description => 'Add an entry to `mods.yaml`.';

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
            'Use a url: source. Marks the pack non-publishable when added '
            'to mods.',
      )
      ..addOption(
        'path',
        valueHelp: 'path',
        help:
            'Use a path: source. Marks the pack non-publishable when added '
            'to mods.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: "Report what entries would change but don't change any.",
      )
      ..addMultiOption(
        'accepts-mc',
        valueHelp: 'mc-version',
        help:
            'Additively widen the Minecraft version filter for this entry. '
            'Repeatable.',
      )
      ..addFlag(
        'exact',
        negatable: false,
        help:
            "Preserve the resolved version's build metadata inside the "
            'caret constraint.',
      )
      ..addFlag(
        'pin',
        negatable: false,
        help:
            'Write the resolved version as a bare semver, freezing the '
            'entry in place.',
      )
      ..addOption(
        'type',
        allowed: typeFlagValues,
        help: 'Override the inferred section.',
      );
    addOfflineFlag();
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
    final offline = readOfflineFlag();
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
      _writeSideFields(long, envOpt);
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
          // Default: caret on major.minor.patch. If Modrinth's version
          // isn't semver-shaped (some mods use arbitrary strings),
          // carets are meaningless — fall back to pinning the raw
          // version verbatim.
          effectiveConstraint = _caretOrPinFallback(latest);
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
        _writeSideFields(long, envOpt);
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
      offline: offline,
    );
    if (result.exitCode != exitOk) return result.exitCode;
    reporter.printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    if (offline) {
      console.warn(
        'Entries added when offline may not resolve to the latest '
        'compatible version available.',
      );
    }
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
        // Best-effort parse: non-semver versions (arbitrary strings)
        // fall back to `Version(0.0.0-<sanitised>)` so we still pick
        // one and write it back — the caller will then pin it
        // verbatim rather than trying to caret-wrap a non-semver.
        final parsed = parseModrinthVersionBestEffort(v.versionNumber);
        if (bestParsed == null || parsed > bestParsed) {
          bestParsed = parsed;
          best = v.versionNumber;
        }
      } on FormatException {
        // skip — only reached for pure-symbol inputs the fallback
        // can't sanitise into a legal pre-release identifier.
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

  /// Produces the default-written constraint for `add` (no flags). Uses
  /// a caret on `major.minor.patch` when [latest] parses as semver, and
  /// falls back to pinning the raw version verbatim when it doesn't —
  /// some Modrinth mods use arbitrary strings as version names, and
  /// carets have no meaning for those.
  String _caretOrPinFallback(String latest) {
    try {
      final parsed = parseModrinthVersion(latest);
      return '^${parsed.major}.${parsed.minor}.${parsed.patch}';
    } on FormatException {
      return latest;
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

  /// Translate the legacy `--env client|server|both` flag into per-side
  /// `client:` / `server:` map entries on a long-form add. Default
  /// (`both` or null) leaves the map untouched so the parser falls back
  /// to per-section defaults.
  void _writeSideFields(Map<String, Object?> long, String? envOpt) {
    if (envOpt == null || envOpt == 'both') return;
    if (envOpt == 'client') {
      long['client'] = 'required';
      long['server'] = 'unsupported';
    } else if (envOpt == 'server') {
      long['client'] = 'unsupported';
      long['server'] = 'required';
    }
  }
}
