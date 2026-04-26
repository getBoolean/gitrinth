import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/dependency.dart';
import '../model/modrinth/project.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../service/cache.dart';
import '../service/manifest_io.dart';
import '../service/section_inference.dart';
import '../service/solve_report.dart';
import '_constraint_helpers.dart';
import 'add_command_editor.dart';
import 'slug_constraint_parser.dart';
import 'version_picker.dart';

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
    final positional = parseSinglePositional(
      name: 'slug',
      usage: 'gitrinth add <slug>[@<constraint>]',
    );
    final urlOpt = argResults!['url'] as String?;
    final pathOpt = argResults!['path'] as String?;
    final envOpt = argResults!['env'] as String?;
    final dryRun = argResults!['dry-run'] as bool;
    final exactFlag = argResults!['exact'] as bool;
    final pinFlag = argResults!['pin'] as bool;
    final offline = readOfflineFlag();
    final typeOverride = sectionFromTypeFlag(argResults!['type'] as String?);
    final acceptsMc = parseAcceptsMcFlag(
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
    if (pinFlag && (urlOpt != null || pathOpt != null)) {
      throw const UsageError(
        '--pin applies to Modrinth-sourced entries; cannot combine with '
        '--url or --path.',
      );
    }

    final (:slug, :constraintRaw) = parseSlugConstraint(positional);
    validateConstraintFlags(
      exact: exactFlag,
      pin: pinFlag,
      constraint: constraintRaw,
    );

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
      writeSideFields(long, envOpt);
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
        final latest = await pickLatestReleaseVersion(
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
            "loader=${loaderNameForSection(existingManifest.loader, section) ?? '<none>'} "
            "mc=${existingManifest.mcVersion}$widened. "
            'Pass `@<version>` explicitly to pin an alpha/beta.',
          );
        }
        await _validateNoIncompatibility(
          io: io,
          cache: read(cacheProvider),
          existingManifest: existingManifest,
          newSlug: slug,
          newProjectId: project.id,
          pickedVersion: latest,
        );
        if (exactFlag) {
          effectiveConstraint = '^${latest.versionNumber}';
        } else if (pinFlag) {
          effectiveConstraint = bareVersionForPin(latest.versionNumber);
        } else {
          // Default: caret on major.minor.patch. If Modrinth's version
          // isn't semver-shaped (some mods use arbitrary strings),
          // carets are meaningless — fall back to pinning the raw
          // version verbatim.
          effectiveConstraint = caretOrPinFallback(latest.versionNumber);
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
        writeSideFields(long, envOpt);
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
      console.message('Would add to ${sectionKeyFor(section)}:');
      console.message(
        _describeEntry(
          slug: slug,
          shorthand: longForm == null ? writtenValue : null,
          longForm: longForm,
        ),
      );
      return exitOk;
    }

    io.writeModsYaml(updated);

    final reporter = SolveReporter(console);

    final result = await runResolveAndSync(io: io, offline: offline);
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

  // Same permissive pattern the YAML parser uses for accepts-mc.
  Future<void> _validateNoIncompatibility({
    required ManifestIo io,
    required GitrinthCache cache,
    required ModsYaml existingManifest,
    required String newSlug,
    required String newProjectId,
    required modrinth.Version pickedVersion,
  }) async {
    final lock = io.readModsLock();
    final pidToSlug = <String, String>{
      if (lock != null)
        for (final entry in lock.allEntries)
          if (entry.value.projectId != null) entry.value.projectId!: entry.key,
    };
    final declaredSlugs = <String>{
      for (final s in Section.values)
        ...existingManifest.sectionEntries(s).keys,
    };

    for (final dep in pickedVersion.dependencies) {
      if (dep.dependencyType != DependencyType.incompatible) continue;
      final pid = dep.projectId;
      if (pid == null) continue;
      final otherSlug = pidToSlug[pid];
      if (otherSlug != null && declaredSlugs.contains(otherSlug)) {
        throw UserError(
          "Cannot add '$newSlug' — its picked version "
          "${pickedVersion.versionNumber} declares '$otherSlug' as "
          'incompatible. Pin an older compatible version with '
          "`gitrinth add $newSlug@<version>`, or remove '$otherSlug' first.",
        );
      }
    }

    if (lock == null) return;
    for (final entry in lock.allEntries) {
      final locked = entry.value;
      if (locked.sourceKind != LockedSourceKind.modrinth) continue;
      final pid = locked.projectId;
      final vid = locked.versionId;
      if (pid == null || vid == null) continue;
      final cachedDeps = _readCachedDeps(cache, pid, vid);
      if (cachedDeps == null) continue;
      for (final d in cachedDeps) {
        if (d['dependency_type'] != 'incompatible') continue;
        if (d['project_id'] == newProjectId) {
          throw UserError(
            "Cannot add '$newSlug' — '${entry.key}' (locked at "
            "${locked.version ?? '?'}) declares it as incompatible. "
            "Pin an older compatible version of '${entry.key}' first, or "
            "remove '${entry.key}'.",
          );
        }
      }
    }
  }

  List<Map<String, dynamic>>? _readCachedDeps(
    GitrinthCache cache,
    String projectId,
    String versionId,
  ) {
    final path = cache.modrinthVersionMetadataPath(
      projectId: projectId,
      versionId: versionId,
    );
    final file = File(path);
    if (!file.existsSync()) return null;
    final dynamic raw;
    try {
      raw = jsonDecode(file.readAsStringSync());
    } on Object {
      return null;
    }
    if (raw is! Map) return null;
    final deps = raw['dependencies'];
    if (deps is! List) return const [];
    return [
      for (final d in deps)
        if (d is Map) d.cast<String, dynamic>(),
    ];
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
