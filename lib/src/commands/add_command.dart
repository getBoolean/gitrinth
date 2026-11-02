import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/parser.dart';
import '../model/manifest/source_eligibility.dart';
import '../model/curseforge/cf_constants.dart';
import '../service/curseforge/curseforge_filters.dart';
import '../service/curseforge/curseforge_version.dart';
import '../model/modrinth/dependency.dart';
import '../model/modrinth/project.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../service/cache.dart';
import '../service/manifest_io.dart';
import '../service/resolve/section_inference.dart';
import '../service/resolve/solve_report.dart';
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
      ..addFlag('modrinth', help: 'Resolve on Modrinth for this entry.')
      ..addFlag('curseforge', help: 'Resolve on CurseForge for this entry.')
      ..addFlag(
        'allow-hash-mismatch',
        negatable: false,
        help: 'Accept and record different platform hashes.',
      )
      ..addFlag(
        'search',
        defaultsTo: true,
        help:
            'Search for cross-platform peers when a slug is missing or hashes differ.',
      )
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

    final cfSugar = positional.startsWith('cf:');
    final (:slug, :constraintRaw) = parseSlugConstraint(
      cfSugar ? positional.substring(3) : positional,
    );
    if (slug.isEmpty) {
      throw const UsageError('Missing CurseForge slug after cf:.');
    }
    validateConstraintFlags(
      exact: exactFlag,
      pin: pinFlag,
      constraint: constraintRaw,
    );

    final io = ManifestIo();
    final existingManifest = io.readModsYaml();

    final platformFlags =
        argResults!.wasParsed('modrinth') ||
        argResults!.wasParsed('curseforge');
    final mismatch = argResults!['allow-hash-mismatch'] as bool;
    if ((cfSugar || platformFlags || mismatch) &&
        (urlOpt != null || pathOpt != null)) {
      throw const UsageError(
        'Platform options cannot be combined with --url or --path.',
      );
    }
    if (cfSugar &&
        ((argResults!.wasParsed('modrinth') &&
                argResults!['modrinth'] == true) ||
            (argResults!.wasParsed('curseforge') &&
                argResults!['curseforge'] == false))) {
      throw const UsageError(
        'cf: requires CurseForge enabled and Modrinth disabled.',
      );
    }

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

    if (urlOpt == null &&
        pathOpt == null &&
        (cfSugar ||
            platformFlags ||
            mismatch ||
            existingManifest.gitrinth.isPlatformEnabled(
              SourceKind.curseforge,
            ) ||
            !existingManifest.gitrinth.isPlatformEnabled(
              SourceKind.modrinth,
            ))) {
      return _addPlatformEntry(
        io: io,
        manifest: existingManifest,
        slug: slug,
        constraint: constraintRaw,
        cfSugar: cfSugar,
        sectionOverride: typeOverride,
        env: envOpt,
        acceptsMc: acceptsMc,
        exact: exactFlag,
        pin: pinFlag,
        dryRun: dryRun,
        offline: offline,
      );
    }

    final Section section;
    final String? writtenValue;
    final Map<String, Object?>? longForm;

    if (urlOpt != null || pathOpt != null) {
      // Local / url: source — no Modrinth round-trip.
      final filename = urlOpt ?? pathOpt;
      if (filename == null) {
        throw ArgumentError(
          'add_command: neither --url nor --path supplied; '
          'argument-validation should have rejected earlier.',
        );
      }
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
      final api = read(
        modrinthApiFactoryProvider,
      ).forHost(existingManifest.modrinthHost);
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
          long['accepts_mc'] = acceptsMc.length == 1
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

    if (section == Section.mods && !existingManifest.loader.hasModRuntime) {
      throw UserError(
        'cannot add mod "$slug": loader.mods is not set. Declare a mod '
        'loader first (e.g. `loader: { mods: neoforge }`) before '
        'adding mods.',
      );
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

  Future<int> _addPlatformEntry({
    required ManifestIo io,
    required ModsYaml manifest,
    required String slug,
    required String? constraint,
    required bool cfSugar,
    required Section? sectionOverride,
    required String? env,
    required List<String> acceptsMc,
    required bool exact,
    required bool pin,
    required bool dryRun,
    required bool offline,
  }) async {
    final requested = <SourceKind>{};
    for (final kind in SourceKind.values) {
      final selected = cfSugar
          ? kind == SourceKind.curseforge
          : argResults!.wasParsed(kind.name)
          ? argResults![kind.name] as bool
          : manifest.gitrinth.isPlatformEnabled(kind);
      if (selected) requested.add(kind);
    }
    if (requested.isEmpty) {
      throw const UsageError('At least one platform must be enabled for add.');
    }
    var section = sectionOverride;
    section ??=
        !manifest.loader.hasModRuntime && manifest.loader.plugins != null
        ? Section.plugins
        : null;
    void checkEligibility() {
      if (section != null &&
          requested.contains(SourceKind.curseforge) &&
          !sectionAllowsCurseforge(section, manifest.loader.plugins)) {
        if (cfSugar ||
            argResults!.wasParsed('curseforge') ||
            (argResults!.wasParsed('modrinth') &&
                argResults!['modrinth'] == false)) {
          throw const ValidationError(
            'CurseForge plugins require loader.plugins bukkit, spigot, or paper. See the source eligibility matrix.',
          );
        }
        requested.remove(SourceKind.curseforge);
      }
    }

    checkEligibility();
    if (section == null && requested.contains(SourceKind.modrinth)) {
      try {
        final project = await read(
          modrinthApiFactoryProvider,
        ).forHost(manifest.modrinthHost).getProject(slug);
        section = inferSectionFromProject(
          projectType: project.projectType,
          loaders: project.loaders,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
    }
    if (section == null && requested.contains(SourceKind.curseforge)) {
      final api = read(curseForgeApiFactoryProvider).api;
      if (int.tryParse(slug) case final int id) {
        final project = (await api.getMod(id)).data;
        section = Section.values
            .where((s) => s.cfClassId == project.classId)
            .firstOrNull;
      } else {
        for (final candidate in Section.values) {
          if (!sectionAllowsCurseforge(candidate, manifest.loader.plugins)) {
            continue;
          }
          if (await findModBySlug(api, slug: slug, section: candidate) !=
              null) {
            section = candidate;
            break;
          }
        }
      }
    }
    if (section == null) throw UserError('No eligible platform has "$slug".');
    checkEligibility();
    if (requested.isEmpty) {
      throw const UsageError(
        'No eligible platform is enabled for this section.',
      );
    }
    if (section == Section.mods && !manifest.loader.hasModRuntime) {
      throw UserError('cannot add mod "$slug": loader.mods is not set.');
    }
    final original = File(io.modsYamlPath).readAsStringSync();
    final fields = <String, Object?>{
      'version': constraint ?? 'release',
      'sources': requested.map((k) => k.name).toList(),
      if (argResults!['allow-hash-mismatch'] as bool)
        'allow_hash_mismatch': true,
      if (acceptsMc.isNotEmpty)
        'accepts_mc': acceptsMc.length == 1 ? acceptsMc.first : acceptsMc,
    };
    writeSideFields(fields, env);
    String render(Map<String, Object?> value) => injectEntry(
      original,
      section: section!,
      slug: slug,
      shorthandValue: value.length == 1 ? value['version'] as String : null,
      longForm: value.length == 1 ? null : value,
    );
    final preview =
        await runResolveAndSync(
          io: io,
          offline: offline,
          dryRun: true,
          manifestOverride: parseModsYaml(
            render(fields),
            filePath: io.modsYamlPath,
          ),
          allowMissingSourcesForSlugs: {slug},
        ).catchError((Object error) {
          if (error is ValidationError) {
            throw ValidationError(
              '${error.message}\nFor add, select a source with '
              '--[no-]modrinth / --[no-]curseforge, or accept divergent hashes '
              'with --allow-hash-mismatch.',
            );
          }
          throw error;
        });
    final locked = preview.newLock?.allEntries
        .where((e) => e.key == slug)
        .firstOrNull
        ?.value;
    if (locked == null) {
      throw UserError(
        'No eligible platform has a compatible version of "$slug".',
      );
    }
    final resolved = <SourceKind>{
      if (locked.modrinth != null) SourceKind.modrinth,
      if (locked.curseforge != null) SourceKind.curseforge,
    };
    if (resolved.isEmpty) {
      throw UserError(
        'No eligible platform has a compatible version of "$slug".',
      );
    }
    if (locked.modrinth != null && locked.curseforge != null) {
      final latestMr = locked.modrinth!.discoveredViaSearch
          ? null
          : await pickLatestReleaseVersion(
              api: read(
                modrinthApiFactoryProvider,
              ).forHost(manifest.modrinthHost),
              slug: slug,
              section: section,
              loaderConfig: manifest.loader,
              mcVersion: manifest.mcVersion,
              acceptsMc: acceptsMc,
            );
      final latestCf = await listCompatibleFiles(
        api: read(curseForgeApiFactoryProvider).api,
        projectId: locked.curseforge!.projectId,
        section: section,
        modLoader: section == Section.mods ? manifest.loader.mods : null,
        pluginLoader: manifest.loader.plugins,
        gameVersions: [manifest.mcVersion, ...acceptsMc],
        channel: Channel.release,
      );
      if ((latestMr != null && latestMr.id != locked.modrinth!.versionId) ||
          (latestCf.isNotEmpty &&
              latestCf.first.id != locked.curseforge!.fileId)) {
        console.message(
          'Selected matching version ${locked.modrinth!.versionNumber}; '
          'latest Modrinth: ${latestMr?.versionNumber ?? "<none>"}, '
          'latest CurseForge: ${latestCf.firstOrNull?.displayName ?? "<none>"}.',
        );
      }
    }
    if (constraint == null) {
      var version = locked.modrinth?.versionNumber;
      if (version == null && locked.curseforge != null) {
        final cf = locked.curseforge!;
        final file = (await read(
          curseForgeApiFactoryProvider,
        ).api.getFile(cf.projectId, cf.fileId)).data;
        version = curseForgeFileVersion(file);
      }
      // CF display names need not contain a semantic version.
      version ??= 'release';
      fields['version'] = exact
          ? '^$version'
          : pin
          ? bareVersionForPin(version)
          : caretOrPinFallback(version);
    }
    final explicit =
        cfSugar ||
        argResults!.wasParsed('modrinth') ||
        argResults!.wasParsed('curseforge');
    final defaults = effectiveSources(manifest, ModEntry(slug: slug), section);
    if (resolved.length == requested.length &&
        !explicit &&
        defaults.length == resolved.length &&
        defaults.containsAll(resolved)) {
      fields.remove('sources');
    } else {
      fields['sources'] = cfSugar
          ? 'curseforge'
          : resolved.map((k) => k.name).toList();
    }
    if (resolved.length < requested.length) {
      console.message(
        'Only ${resolved.single.name} has a compatible version of $slug; restricting sources.',
      );
    }
    final updated = render(fields);
    parseModsYaml(updated, filePath: io.modsYamlPath);
    if (dryRun) {
      console.message('Would add to ${sectionKeyFor(section)}:');
      console.message(
        _describeEntry(
          slug: slug,
          shorthand: fields.length == 1 ? fields['version'] as String : null,
          longForm: fields.length == 1 ? null : fields,
        ),
      );
      return exitOk;
    }
    io.writeModsYaml(updated);
    final result = await runResolveAndSync(io: io, offline: offline);
    if (result.exitCode == exitOk) {
      SolveReporter(console).printSummary(
        changeCount: result.changeCount,
        outdated: result.outdated,
      );
    }
    return result.exitCode;
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
          if (entry.value.modrinth?.projectId != null)
            entry.value.modrinth!.projectId: entry.key,
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
    final defaultBaseUrl = read(modrinthApiFactoryProvider).defaultBaseUrl;
    for (final entry in lock.allEntries) {
      final locked = entry.value;
      final mr = locked.modrinth;
      if (mr == null) continue;
      final pid = mr.projectId;
      final vid = mr.versionId;
      if (pid.isEmpty || vid.isEmpty) continue;
      // Re-derive the host the lock entry was fetched against by
      // looking up the same slug in the live manifest. Locked entries
      // don't carry host metadata yet — that lands with Part 4.
      String host = existingManifest.modrinthHost ?? defaultBaseUrl;
      for (final section in Section.values) {
        final manifestEntry = existingManifest.sectionEntries(
          section,
        )[entry.key];
        if (manifestEntry != null) {
          host = existingManifest.effectiveModrinthHost(
            manifestEntry,
            defaultBaseUrl,
          );
          break;
        }
      }
      final cachedDeps = _readCachedDeps(cache, host, pid, vid);
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
    String host,
    String projectId,
    String versionId,
  ) {
    final path = cache.modrinthVersionMetadataPath(
      host: host,
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
    final lf = longForm;
    if (lf == null) {
      throw ArgumentError('_describeEntry: shorthand and longForm both null');
    }
    final buf = StringBuffer('  $slug:\n');
    final entries = lf.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.write('    ${e.key}: ${e.value}');
      if (i < entries.length - 1) buf.write('\n');
    }
    return buf.toString();
  }
}
