import 'dart:io';

import 'package:dio/dio.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/project.dart';
import '../model/resolver/constraint.dart';
import '../service/manifest_io.dart';
import '../service/section_inference.dart';
import '../service/solve_report.dart';
import '_constraint_helpers.dart';
import 'add_command_editor.dart';
import 'override_command_editor.dart';
import 'slug_constraint_parser.dart';
import 'version_picker.dart';

/// `gitrinth override <slug>[@<constraint>] [--standalone]`
///
/// Adds a sticky override entry to `mods.yaml`'s `project_overrides:`
/// section, or — with `--standalone` — to the companion
/// `project_overrides.yaml` file.
///
/// Override semantics differ from `add`: the resolver pins the chosen
/// version regardless of constraints from other mods on the slug, and
/// silently drops `incompatible:` edges that touch the slug in either
/// direction. This is the right tool when a `gitrinth:disabled-by-conflict`
/// marker has parked a mod you want in the pack despite a declared
/// incompatibility — `override` bypasses the same checks `add` enforces
/// (including the incompatibility-prevention guard).
class OverrideCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'override';

  @override
  String get description =>
      'Add a sticky override to project_overrides in `mods.yaml`.';

  @override
  String get invocation =>
      'gitrinth override <slug>[@<constraint>] [arguments]';

  OverrideCommand() {
    argParser
      ..addOption(
        'env',
        allowed: ['client', 'server', 'both'],
        valueHelp: 'client|server|both',
        help: 'Restrict the override to a side.',
      )
      ..addOption(
        'url',
        valueHelp: 'url',
        help: 'Use a url: source for the override.',
      )
      ..addOption(
        'path',
        valueHelp: 'path',
        help: 'Use a path: source for the override.',
      )
      ..addOption(
        'type',
        allowed: typeFlagValues,
        help:
            'Force the section used for loader filtering. Useful when '
            'the slug is purely transitive and section inference is '
            'wrong.',
      )
      ..addMultiOption(
        'accepts-mc',
        valueHelp: 'mc-version',
        help:
            'Additively widen the Minecraft version filter for this '
            'override. Repeatable.',
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
            'override in place.',
      )
      ..addFlag(
        'standalone',
        negatable: false,
        help:
            'Write the override to project_overrides.yaml instead of '
            "mods.yaml's project_overrides: section. Creates the file "
            'if it does not exist.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: "Report what would change but don't write or resolve.",
      );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final positional = parseSinglePositional(
      name: 'slug',
      usage: 'gitrinth override <slug>[@<constraint>]',
    );
    final urlOpt = argResults!['url'] as String?;
    final pathOpt = argResults!['path'] as String?;
    final envOpt = argResults!['env'] as String?;
    final dryRun = argResults!['dry-run'] as bool;
    final exactFlag = argResults!['exact'] as bool;
    final pinFlag = argResults!['pin'] as bool;
    final standalone = argResults!['standalone'] as bool;
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
        '--accepts-mc applies to Modrinth-sourced overrides; cannot '
        'combine with --url or --path.',
      );
    }
    if (exactFlag && (urlOpt != null || pathOpt != null)) {
      throw const UsageError(
        '--exact applies to Modrinth-sourced overrides; cannot combine '
        'with --url or --path.',
      );
    }
    if (pinFlag && (urlOpt != null || pathOpt != null)) {
      throw const UsageError(
        '--pin applies to Modrinth-sourced overrides; cannot combine '
        'with --url or --path.',
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
    final existingStandalone = io.readProjectOverrides();

    // Duplicate check — refuse if the slug is already overridden in
    // the target file.
    if (standalone) {
      if (existingStandalone.entries.containsKey(slug)) {
        throw UserError(
          "'$slug' is already in project_overrides.yaml; remove it or "
          'edit directly.',
        );
      }
    } else {
      if (existingManifest.projectOverrides.containsKey(slug)) {
        throw UserError(
          "'$slug' is already in project_overrides in mods.yaml; "
          'remove it or edit directly.',
        );
      }
    }

    final Section section;
    final String? writtenValue;
    final Map<String, Object?>? longForm;

    if (urlOpt != null || pathOpt != null) {
      // Local / url: source — no Modrinth round-trip and no version
      // promotion. The resolver doesn't see this override; the lock
      // builder routes it through the url/path branches.
      final filename = urlOpt ?? pathOpt;
      if (filename == null) {
        throw ArgumentError(
          'override_command: neither --url nor --path supplied; '
          'argument-validation should have rejected earlier.',
        );
      }
      if (typeOverride != null) {
        section = typeOverride;
      } else {
        // Section is only used for the warn/info message in this
        // branch — no listVersions call follows.
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
      // Modrinth source. Determine the section for loader filtering:
      //   1. If the slug is in mods.yaml's mods/resource_packs/etc.,
      //      use that section (purely-transitive overrides excluded).
      //   2. Else query Modrinth for the project type.
      //   3. --type wins if set.
      Section? declaredSection;
      for (final s in Section.values) {
        if (existingManifest.sectionEntries(s).containsKey(slug)) {
          declaredSection = s;
          break;
        }
      }
      final api = read(modrinthApiFactoryProvider)
          .forHost(existingManifest.modrinthHost);
      final Section inferredSection;
      Project? project;
      if (declaredSection != null) {
        inferredSection = declaredSection;
      } else {
        try {
          project = await api.getProject(slug);
        } on DioException catch (e) {
          final err = e.error;
          if (err is GitrinthException) throw err;
          rethrow;
        }
        inferredSection = inferSectionFromProject(
          projectType: project.projectType,
          loaders: project.loaders,
        );
      }
      if (typeOverride != null && typeOverride != inferredSection) {
        console.warn(
          "--type ${sectionKeyFor(typeOverride)} overrides the inferred "
          "section '${sectionKeyFor(inferredSection)}' for '$slug'.",
        );
        section = typeOverride;
      } else {
        section = inferredSection;
      }

      // Version resolution (mirrors `add`'s no-`@constraint` path).
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
        if (exactFlag) {
          effectiveConstraint = '^${latest.versionNumber}';
        } else if (pinFlag) {
          effectiveConstraint = bareVersionForPin(latest.versionNumber);
        } else {
          effectiveConstraint = caretOrPinFallback(latest.versionNumber);
        }
      } else {
        // Validate the user-supplied constraint so a bad `@xyz` fails
        // fast with a single-line error before we touch any file.
        final channel = parseChannelToken(constraintRaw);
        if (channel == null) {
          parseConstraint(constraintRaw); // throws ValidationError
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

    final String updated;
    if (standalone) {
      final existingText = File(io.projectOverridesPath).existsSync()
          ? File(io.projectOverridesPath).readAsStringSync()
          : '';
      updated = injectStandaloneOverrideEntry(
        existingText,
        slug: slug,
        shorthandValue: longForm == null ? writtenValue : null,
        longForm: longForm,
      );
    } else {
      final yamlText = File(io.modsYamlPath).readAsStringSync();
      updated = injectOverrideEntry(
        yamlText,
        slug: slug,
        shorthandValue: longForm == null ? writtenValue : null,
        longForm: longForm,
      );
    }

    if (dryRun) {
      final destFile = standalone ? 'project_overrides.yaml' : 'mods.yaml';
      console.message(
        'Would add to project_overrides in $destFile (section: '
        '${sectionKeyFor(section)}):',
      );
      console.message(
        _describeEntry(
          slug: slug,
          shorthand: longForm == null ? writtenValue : null,
          longForm: longForm,
        ),
      );
      return exitOk;
    }

    if (standalone) {
      io.writeProjectOverrides(updated);
    } else {
      io.writeModsYaml(updated);
    }

    final reporter = SolveReporter(console);

    final result = await runResolveAndSync(io: io, offline: offline);
    if (result.exitCode != exitOk) return result.exitCode;
    reporter.printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    if (offline) {
      console.warn(
        'Overrides applied when offline may not resolve to the latest '
        'compatible version available.',
      );
    }
    return exitOk;
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
