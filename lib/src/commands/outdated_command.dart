import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pub_semver/pub_semver.dart' as semver;

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../model/resolver/version_selection.dart';
import '../service/cache.dart';
import '../service/console.dart';
import '../service/manifest_io.dart';
import '../service/modrinth_api.dart';

class OutdatedCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'outdated';

  @override
  String get description =>
      'Report mods.lock entries behind newer compatible versions.';

  @override
  String get invocation => 'gitrinth outdated [arguments]';

  OutdatedCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit a machine-readable JSON report.',
      )
      ..addFlag(
        'show-all',
        negatable: false,
        help: 'Include up-to-date entries in the report.',
      )
      ..addFlag(
        'transitive',
        defaultsTo: true,
        help: 'Include transitive dependencies in the report. '
            'Pass --no-transitive to suppress.',
      );
    addOfflineFlag();
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final asJson = results['json'] as bool;
    final showAll = results['show-all'] as bool;
    final includeTransitive = results['transitive'] as bool;
    final offline = readOfflineFlag();

    final io = ManifestIo();
    final lock = io.readModsLock();
    if (lock == null) {
      console.error('mods.lock not found. Run `gitrinth get`.');
      return exitUserError;
    }
    final manifest = io.readModsYaml();
    final overrides = io.readProjectOverrides();
    final overriddenSlugs = overrides.entries.keys.toSet();

    final api = read(modrinthApiProvider);
    final cache = read(cacheProvider);

    final rows = <_Row>[];
    for (final section in Section.values) {
      final lockSection = lock.sectionFor(section);
      final manifestSection = manifest.sectionEntries(section);
      // Stable order: alphabetical within each section.
      final slugs = lockSection.keys.toList()..sort();
      for (final slug in slugs) {
        final locked = lockSection[slug]!;
        if (!includeTransitive &&
            locked.dependency == LockedDependencyKind.transitive) {
          continue;
        }
        final manifestEntry = manifestSection[slug];
        final isOverridden = overriddenSlugs.contains(slug);
        final row = await _computeRow(
          slug: slug,
          section: section,
          locked: locked,
          manifestEntry: manifestEntry,
          mcVersion: lock.mcVersion,
          loaderName: lock.loader.mods.name,
          api: api,
          cache: cache,
          offline: offline,
          isOverridden: isOverridden,
        );
        rows.add(row);
      }
    }

    if (asJson) {
      _printJson(rows);
      return exitOk;
    }
    _printTable(rows, showAll: showAll);
    return exitOk;
  }

  Future<_Row> _computeRow({
    required String slug,
    required Section section,
    required LockedEntry locked,
    required ModEntry? manifestEntry,
    required String mcVersion,
    required String loaderName,
    required ModrinthApi api,
    required GitrinthCache cache,
    required bool offline,
    required bool isOverridden,
  }) async {
    final currentVersion = locked.version ?? locked.path ?? '';
    final marker =
        manifestEntry == null ? null : _markerOf(manifestEntry.constraintRaw);
    if (locked.sourceKind != LockedSourceKind.modrinth) {
      return _Row(
        slug: slug,
        section: section,
        kind: locked.dependency,
        sourceKind: locked.sourceKind,
        current: currentVersion,
        upgradable: null,
        latest: null,
        isOverridden: isOverridden,
        marker: marker,
      );
    }
    if (marker != null) {
      return _Row(
        slug: slug,
        section: section,
        kind: locked.dependency,
        sourceKind: locked.sourceKind,
        current: currentVersion,
        upgradable: null,
        latest: null,
        isOverridden: isOverridden,
        marker: marker,
      );
    }

    final acceptsMc = manifestEntry?.acceptsMc ?? const <String>[];
    final gameVersions = <String>{mcVersion, ...acceptsMc}.toList();
    final loaderFilter = _filterForSection(section, loaderName);
    final channel = manifestEntry?.channel ?? Channel.alpha;
    final constraint = _safeParseConstraint(manifestEntry?.constraintRaw);

    final List<modrinth.Version> versions;
    if (offline) {
      final pid = locked.projectId;
      if (pid == null) {
        return _Row(
          slug: slug,
          section: section,
          kind: locked.dependency,
          sourceKind: locked.sourceKind,
          current: currentVersion,
          upgradable: null,
          latest: null,
          isOverridden: isOverridden,
          marker: marker,
        );
      }
      versions = cache.listCachedVersions(pid).where((v) {
        final loaderOk = loaderFilter == null ||
            v.loaders.any(loaderFilter.contains);
        final mcOk = v.gameVersions.any(gameVersions.contains);
        return loaderOk && mcOk;
      }).toList();
    } else {
      try {
        versions = await api.listVersions(
          slug,
          loadersJson: loaderFilter == null
              ? null
              : encodeFilterArray(loaderFilter),
          gameVersionsJson: encodeFilterArray(gameVersions),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          return _Row(
            slug: slug,
            section: section,
            kind: locked.dependency,
            sourceKind: locked.sourceKind,
            current: currentVersion,
            upgradable: null,
            latest: null,
            isOverridden: isOverridden,
            marker: marker,
          );
        }
        rethrow;
      }
    }

    // Upgradable: newest within the entry's constraint and channel floor.
    final upgradable = pickHighestMatching(versions, constraint, channel);
    // Latest: newest under just the channel floor (constraint widened
    // to `any`). For overridden entries, the override pin is what
    // gitrinth would lock, so report that as latest.
    final latest = pickHighestMatching(
      versions,
      semver.VersionConstraint.any,
      channel,
    );

    return _Row(
      slug: slug,
      section: section,
      kind: locked.dependency,
      sourceKind: locked.sourceKind,
      current: currentVersion,
      upgradable: upgradable?.versionNumber,
      latest: latest?.versionNumber,
      isOverridden: isOverridden,
      marker: marker,
    );
  }

  semver.VersionConstraint _safeParseConstraint(String? raw) {
    try {
      return parseConstraint(raw);
    } on Object {
      return semver.VersionConstraint.any;
    }
  }

  String? _markerOf(String? raw) {
    if (isNotFoundMarker(raw)) return 'not-found';
    if (isDisabledByConflictMarker(raw)) return 'disabled-by-conflict';
    return null;
  }

  List<String>? _filterForSection(Section section, String loaderName) {
    switch (section) {
      case Section.mods:
        return [loaderName];
      case Section.shaders:
        // Shader project type uses the shader-loader tag; we don't have
        // it here on the lock side, so leave the filter open.
        return null;
      case Section.resourcePacks:
        return const ['minecraft'];
      case Section.dataPacks:
        return const ['datapack'];
    }
  }

  void _printJson(List<_Row> rows) {
    final out = {
      'packages': [
        for (final r in rows)
          {
            'slug': r.slug,
            'section': r.section.name,
            'kind': r.kind.name,
            'source': r.sourceKind.name,
            'current': r.current.isEmpty ? null : {'version': r.current},
            'upgradable':
                r.upgradable == null ? null : {'version': r.upgradable},
            'latest': r.latest == null ? null : {'version': r.latest},
            'isOverridden': r.isOverridden,
            'marker': r.marker,
          },
      ],
    };
    console.message(const JsonEncoder.withIndent('  ').convert(out));
  }

  void _printTable(List<_Row> rows, {required bool showAll}) {
    if (rows.isEmpty) {
      console.message('Found no outdated mods.');
      return;
    }

    final filtered = showAll
        ? rows
        : rows.where((r) => !_isUpToDate(r)).toList();
    if (filtered.isEmpty) {
      console.message('Found no outdated mods.');
      return;
    }

    final c = console;
    console.message('Showing outdated mods.');
    console.message(
      '[${c.red('*')}] indicates versions that are not the latest available.',
    );
    console.message('');

    final direct = filtered
        .where((r) => r.kind == LockedDependencyKind.direct)
        .toList();
    final transitive = filtered
        .where((r) => r.kind == LockedDependencyKind.transitive)
        .toList();

    // Column widths: based on plain text lengths so ANSI escapes don't
    // skew the layout. Header is left-padded into the slug column.
    String pkgLabel(_Row r) =>
        r.isOverridden ? '${r.slug} (overridden)' : r.slug;
    final slugWidth = [
      'Package'.length,
      for (final r in filtered) pkgLabel(r).length + 2, // +2 for "* "
    ].reduce((a, b) => a > b ? a : b);
    final currentWidth = [
      'Current'.length,
      for (final r in filtered) (r.current).length,
    ].reduce((a, b) => a > b ? a : b);
    final upgradableWidth = [
      'Upgradable'.length,
      for (final r in filtered) (r.upgradable ?? '-').length,
    ].reduce((a, b) => a > b ? a : b);
    // Latest column is rightmost; no trailing pad needed.

    final header = '${c.bold('Package'.padRight(slugWidth))}  '
        '${c.bold('Current'.padRight(currentWidth))}  '
        '${c.bold('Upgradable'.padRight(upgradableWidth))}  '
        '${c.bold('Latest')}';
    console.message(header);

    void printSection(String title, List<_Row> section) {
      if (section.isEmpty) return;
      console.message(c.bold('$title:'));
      for (final r in section) {
        final pkg = pkgLabel(r);
        final markedPkg = (r.upgradable != null && r.latest != null &&
                _parsedNotEqual(r.current, r.latest!))
            ? '${c.red('*')} $pkg'
            : '  $pkg';
        // Pad the visible content to slugWidth (account for the 2-char
        // "* " prefix already present).
        final pkgPadded = markedPkg.padRight(slugWidth + _ansiOverhead(markedPkg));
        final currentText = r.current;
        final currentColored = (r.upgradable != null &&
                _parsedNotEqual(currentText, r.latest ?? currentText))
            ? c.red(currentText)
            : currentText;
        final currentPadded = currentColored
            .padRight(currentWidth + _ansiOverhead(currentColored));
        final upgradableRaw = r.upgradable ?? '-';
        final upgradableColored = _grayIfEqual(c, upgradableRaw, currentText);
        final upgradablePadded = (upgradableColored.contains('\x1b')
                ? upgradableColored
                : upgradableColored)
            .padRight(upgradableWidth + _ansiOverhead(upgradableColored));
        final latestRaw = r.latest ?? '-';
        final latestColored = _grayIfEqual(c, latestRaw, upgradableRaw);
        console.message(
          '  $pkgPadded  $currentPadded  $upgradablePadded  $latestColored',
        );
      }
    }

    printSection('direct dependencies', direct);
    if (direct.isNotEmpty && transitive.isNotEmpty) console.message('');
    printSection('transitive dependencies', transitive);

    final upgradableLockedToOlder = filtered
        .where((r) =>
            r.upgradable != null &&
            r.current.isNotEmpty &&
            r.upgradable != r.current)
        .length;
    final blockedByConstraint = filtered
        .where((r) =>
            r.upgradable != null &&
            r.latest != null &&
            r.upgradable == r.current &&
            r.upgradable != r.latest)
        .length;

    console.message('');
    if (upgradableLockedToOlder > 0) {
      final n = upgradableLockedToOlder;
      console.message(
        '$n ${n == 1 ? 'upgradable dependency is' : 'upgradable dependencies are'} '
        'locked (in mods.lock) to older versions.\n'
        'To update ${n == 1 ? 'it' : 'them'}, run `gitrinth upgrade`.',
      );
    }
    if (blockedByConstraint > 0) {
      final n = blockedByConstraint;
      console.message(
        '$n ${n == 1 ? 'dependency is' : 'dependencies are'} constrained to '
        'versions that are older than a resolvable version.\n'
        'To update ${n == 1 ? 'it' : 'them'}, '
        'run `gitrinth upgrade --major-versions`.',
      );
    }
  }

  bool _isUpToDate(_Row r) {
    if (r.sourceKind != LockedSourceKind.modrinth) return true;
    if (r.upgradable == null && r.latest == null) return true;
    if (r.latest == null) return r.upgradable == r.current;
    return r.current == r.latest;
  }

  bool _parsedNotEqual(String a, String b) {
    if (a == b) return false;
    return true;
  }

  String _grayIfEqual(Console c, String value, String compareTo) {
    if (value == compareTo && value != '-') {
      return c.gray(value);
    }
    return value;
  }

  /// Number of invisible ANSI bytes in [s], so `padRight` can be told
  /// to pad to the *visible* width.
  int _ansiOverhead(String s) {
    final m = RegExp('\x1b\\[[0-9;]*m').allMatches(s);
    var total = 0;
    for (final match in m) {
      total += match.end - match.start;
    }
    return total;
  }
}

class _Row {
  final String slug;
  final Section section;
  final LockedDependencyKind kind;
  final LockedSourceKind sourceKind;
  final String current;
  final String? upgradable;
  final String? latest;
  final bool isOverridden;
  final String? marker;
  const _Row({
    required this.slug,
    required this.section,
    required this.kind,
    required this.sourceKind,
    required this.current,
    required this.upgradable,
    required this.latest,
    required this.isOverridden,
    required this.marker,
  });
}
