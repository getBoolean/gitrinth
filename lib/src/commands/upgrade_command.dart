import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/constraint.dart';
import '../service/cache.dart';
import '../service/manifest_io.dart';
import '../service/resolve_and_sync.dart';
import '../service/solve_report.dart';
import 'pin_editor.dart';

class UpgradeCommand extends GitrinthCommand {
  @override
  String get name => 'upgrade';

  @override
  String get description =>
      "Upgrade the current modpack's entries to the newest versions.";

  @override
  String get invocation => 'gitrinth upgrade [<slug>...] [arguments]';

  UpgradeCommand() {
    argParser
      ..addFlag(
        'major-versions',
        negatable: false,
        help:
            'Upgrades entries to their latest resolvable versions, and '
            'updates mods.yaml.',
      )
      ..addFlag(
        'tighten',
        negatable: false,
        help:
            'Updates lower bounds in mods.yaml to match the resolved version.',
      )
      ..addFlag(
        'unlock-transitive',
        negatable: false,
        help: 'Also upgrades the transitive dependencies of the listed '
            'entries.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: "Report what entries would change but don't change any.",
      );
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final majorVersions = results['major-versions'] as bool;
    final tighten = results['tighten'] as bool;
    final unlockTransitive = results['unlock-transitive'] as bool;
    final dryRun = results['dry-run'] as bool;
    final requestedSlugs = results.rest;

    final io = ManifestIo();
    final manifest = io.readModsYaml();

    final modrinthByEntry = <(Section, String), ModEntry>{};
    final nonModrinthSlugs = <String>{};
    for (final section in Section.values) {
      manifest.sectionEntries(section).forEach((slug, entry) {
        if (entry.source is ModrinthEntrySource) {
          modrinthByEntry[(section, slug)] = entry;
        } else {
          nonModrinthSlugs.add(slug);
        }
      });
    }
    final modrinthSlugs = {for (final k in modrinthByEntry.keys) k.$2};
    final allSlugs = {...modrinthSlugs, ...nonModrinthSlugs};

    Set<String> targets;
    if (requestedSlugs.isEmpty) {
      targets = modrinthSlugs;
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
        } else {
          console.detail(
            "skipping '$slug' — non-Modrinth source has no version to upgrade.",
          );
        }
      }
    }

    if (unlockTransitive && targets.isNotEmpty) {
      targets = _expandTransitiveClosure(
        targets,
        io.readModsLock(),
        read(cacheProvider),
      );
    }

    final relaxSet = majorVersions
        ? {
            for (final entry in modrinthByEntry.entries)
              if (targets.contains(entry.key.$2) &&
                  (entry.value.constraintRaw?.trimLeft().startsWith('^') ??
                      false))
                entry.key.$2,
          }
        : <String>{};

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
      dryRun: dryRun,
      freshSlugs: targets,
      relaxConstraints: relaxSet,
    );

    if (result.exitCode != exitOk) {
      return result.exitCode;
    }
    if (dryRun) {
      return exitOk;
    }

    if ((majorVersions || tighten) && result.newLock != null) {
      _rewriteCaretConstraints(
        io: io,
        modrinthByEntry: modrinthByEntry,
        targets: targets,
        relaxSet: relaxSet,
        majorVersions: majorVersions,
        tighten: tighten,
        result: result,
      );
    }

    reporter.printSummary(
      changeCount: result.changeCount,
      outdated: result.outdated,
    );
    return exitOk;
  }

  /// Walks each Modrinth-source caret-bound target whose resolved version
  /// either crossed the caret (`--major-versions`) or moved within-major
  /// (`--tighten`), and rewrites `mods.yaml` to `^<bare>` for the resolved
  /// version. Mirrors `dart pub upgrade`'s `allowsAll`-skip — entries already
  /// satisfied by the existing constraint are left alone.
  void _rewriteCaretConstraints({
    required ManifestIo io,
    required Map<(Section, String), ModEntry> modrinthByEntry,
    required Set<String> targets,
    required Set<String> relaxSet,
    required bool majorVersions,
    required bool tighten,
    required ResolveSyncResult result,
  }) {
    final newLock = result.newLock!;
    var yamlText = File(io.modsYamlPath).readAsStringSync();
    var rewrites = 0;

    for (final entry in modrinthByEntry.entries) {
      final (section, slug) = entry.key;
      if (!targets.contains(slug)) continue;
      final mod = entry.value;
      final raw = mod.constraintRaw?.trim();
      if (raw == null || !raw.startsWith('^')) continue;

      final locked = newLock.sectionFor(section)[slug];
      final resolvedRaw = locked?.version;
      if (resolvedRaw == null) continue;

      final String bareResolved;
      try {
        bareResolved = bareVersionForPin(resolvedRaw);
      } on FormatException {
        console.info(
          "skipped '$slug' rewrite — resolved version '$resolvedRaw' is not "
          'semver-shaped.',
        );
        continue;
      }

      final crossed =
          majorVersions && relaxSet.contains(slug) &&
          !_constraintAllows(raw, resolvedRaw);
      final tightened = tighten && _bareCaretBase(raw) != bareResolved;
      if (!crossed && !tightened) continue;

      final newConstraint = '^$bareResolved';
      final updated = updateEntryConstraint(
        yamlText,
        section: section,
        slug: slug,
        newConstraint: newConstraint,
      );
      if (updated == yamlText) continue;
      yamlText = updated;
      rewrites++;
      console.info('$slug: $raw → $newConstraint in mods.yaml');
    }

    if (rewrites > 0) {
      io.writeModsYaml(yamlText);
    }
  }

  bool _constraintAllows(String raw, String resolvedRaw) {
    final VersionConstraint constraint;
    try {
      constraint = parseConstraint(raw);
    } on Object {
      return false;
    }
    final Version parsed;
    try {
      parsed = parseModrinthVersionBestEffort(resolvedRaw);
    } on FormatException {
      return false;
    }
    return constraint.allows(parsed);
  }

  /// Returns the bare-pinnable form of a caret constraint's base version, or
  /// the raw string when parsing fails. Used by the `--tighten` predicate to
  /// detect "constraint base differs from resolved" without false positives
  /// from tag metadata in either side.
  String _bareCaretBase(String raw) {
    if (!raw.startsWith('^')) return raw;
    final base = raw.substring(1);
    try {
      return bareVersionForPin(base);
    } on FormatException {
      return base;
    }
  }

  /// BFS over the dep graph to compute the transitive closure of
  /// [seeds]. Powers `--unlock-transitive`: every slug in the returned
  /// set is fed to [resolveAndSync] as a `freshSlug`, so the resolver
  /// picks newest-within-constraint instead of preserving the existing
  /// pin.
  ///
  /// Edges are read from the artifact cache's per-version `version.json`
  /// (mirrors dart pub's "graph in cache" architecture — see
  /// [GitrinthCache.modrinthVersionMetadataPath]). Cold-cache entries
  /// (a slug whose `version.json` hasn't been written yet) are reported
  /// via `console.detail` and their children are skipped; subsequent
  /// runs populate the cache.
  Set<String> _expandTransitiveClosure(
    Set<String> seeds,
    ModsLock? lock,
    GitrinthCache cache,
  ) {
    if (lock == null) {
      console.info(
        'upgrade --unlock-transitive: no mods.lock found yet — '
        'falling back to unlocking only the named entries.',
      );
      return seeds;
    }

    final lookup = <String, LockedEntry>{};
    final projectIdToSlug = <String, String>{};
    for (final entry in lock.allEntries) {
      lookup[entry.key] = entry.value;
      final pid = entry.value.projectId;
      if (pid != null) projectIdToSlug[pid] = entry.key;
    }

    final closure = <String>{...seeds};
    final queue = <String>[...seeds];
    while (queue.isNotEmpty) {
      final slug = queue.removeLast();
      final entry = lookup[slug];
      if (entry == null) {
        console.detail(
          "upgrade --unlock-transitive: '$slug' not in mods.lock; skipping.",
        );
        continue;
      }
      if (entry.sourceKind != LockedSourceKind.modrinth) continue;
      final pid = entry.projectId;
      final vid = entry.versionId;
      if (pid == null || vid == null) continue;

      final children = _readCachedRequiredChildren(cache, pid, vid);
      if (children == null) {
        console.detail(
          "upgrade --unlock-transitive: no cached version.json for "
          "'$slug' ($pid/$vid); skipping its transitive children. "
          'Run `gitrinth get` to populate the cache.',
        );
        continue;
      }
      for (final childPid in children) {
        final childSlug = projectIdToSlug[childPid];
        if (childSlug == null) continue;
        if (closure.add(childSlug)) queue.add(childSlug);
      }
    }
    return closure;
  }

  /// Reads the `dependencies` array out of the cached `version.json`
  /// and returns the list of `project_id`s for entries whose
  /// `dependency_type == "required"`. Returns null when the cache file
  /// is missing or unparseable (cold cache); returns an empty list when
  /// the version legitimately has no required deps.
  List<String>? _readCachedRequiredChildren(
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
    final out = <String>[];
    for (final d in deps) {
      if (d is! Map) continue;
      if (d['dependency_type'] != 'required') continue;
      final pid = d['project_id'];
      if (pid is String && pid.isNotEmpty) out.add(pid);
    }
    return out;
  }
}
