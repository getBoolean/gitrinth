import 'package:intl/intl.dart';
import 'package:pub_semver/pub_semver.dart' as semver;

import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import 'console.dart';

enum DiffKind { added, removed, updated, unchanged }

class LockDiff {
  final DiffKind kind;
  final Section section;
  final String slug;
  final LockedEntry? before;
  final LockedEntry? after;
  const LockDiff(this.kind, this.section, this.slug, {this.before, this.after});
}

/// Computes per-entry differences between two lockfiles, sorted alphabetically
/// within each section and ordered by [Section.values] across sections. A
/// missing [oldLock] is treated as an empty lock (every entry shows up as
/// [DiffKind.added]).
List<LockDiff> diffLocks(ModsLock? oldLock, ModsLock newLock) {
  final out = <LockDiff>[];
  for (final section in Section.values) {
    final newMap = newLock.sectionFor(section);
    final oldMap =
        oldLock?.sectionFor(section) ?? const <String, LockedEntry>{};
    final allSlugs = {...oldMap.keys, ...newMap.keys}.toList()..sort();
    for (final slug in allSlugs) {
      final oldEntry = oldMap[slug];
      final newEntry = newMap[slug];
      if (oldEntry == null && newEntry != null) {
        out.add(
          LockDiff(
            DiffKind.added,
            section,
            slug,
            before: null,
            after: newEntry,
          ),
        );
      } else if (oldEntry != null && newEntry == null) {
        out.add(
          LockDiff(
            DiffKind.removed,
            section,
            slug,
            before: oldEntry,
            after: null,
          ),
        );
      } else if (oldEntry != null && newEntry != null) {
        if (!_equalLocked(oldEntry, newEntry)) {
          out.add(
            LockDiff(
              DiffKind.updated,
              section,
              slug,
              before: oldEntry,
              after: newEntry,
            ),
          );
        }
      }
    }
  }
  return out;
}

bool _equalLocked(LockedEntry a, LockedEntry b) {
  return a.sourceKind == b.sourceKind &&
      a.version == b.version &&
      a.projectId == b.projectId &&
      a.versionId == b.versionId &&
      a.path == b.path &&
      a.client == b.client &&
      a.server == b.server &&
      a.dependency == b.dependency &&
      a.file?.name == b.file?.name &&
      a.file?.url == b.file?.url &&
      a.file?.sha512 == b.file?.sha512 &&
      a.file?.size == b.file?.size;
}

/// Returns the raw `version_number` of the newest entry in [candidates]
/// that ranks strictly above [chosenRaw] under the resolver's selection
/// order — `date_published` descending, parsed semver descending as
/// tiebreaker (see [compareModrinthSelectionOrder]). Returns null when
/// [chosenRaw] is already the newest, when parsing fails, or when the
/// candidate list is missing. Unparseable candidates are skipped rather
/// than failing — the resolver would have skipped them too.
///
/// Mirroring the resolver's order matters because the user's "(X
/// available)" hint must point at what `gitrinth upgrade` would actually
/// pick. For date-encoded labels (Faithful 32x' `1.21.x-<month>-<year>`),
/// parsed-semver-only comparison would advertise an older publish date as
/// "newer" simply because its leading max-MC segment is higher.
String? newerAvailableThan(
  String chosenRaw,
  List<modrinth.Version>? candidates,
) {
  if (candidates == null || candidates.isEmpty) return null;
  final semver.Version chosenParsed;
  try {
    chosenParsed = parseModrinthVersion(chosenRaw);
  } on FormatException {
    return null;
  }
  // The chosen version's datePublished comes from the candidate list when
  // it's there (typical: `versionsPerSlug` carries the API response that
  // resolution chose from). Falling back to a synthetic Version with no
  // date keeps the comparator's null-handling rules consistent.
  modrinth.Version chosenForCompare = candidates.firstWhere(
    (v) => v.versionNumber == chosenRaw,
    orElse: () => modrinth.Version(
      id: '',
      projectId: '',
      versionNumber: chosenRaw,
      files: const [],
      dependencies: const [],
      loaders: const [],
      gameVersions: const [],
    ),
  );

  modrinth.Version? best;
  semver.Version? bestParsed;
  for (final v in candidates) {
    final semver.Version parsed;
    try {
      parsed = parseModrinthVersion(v.versionNumber);
    } on FormatException {
      continue;
    }
    if (best == null ||
        compareModrinthSelectionOrder(v, parsed, best, bestParsed!) < 0) {
      best = v;
      bestParsed = parsed;
    }
  }
  if (best == null || bestParsed == null) return null;
  if (best.versionNumber == chosenRaw) return null;
  if (compareModrinthSelectionOrder(best, bestParsed, chosenForCompare, chosenParsed) >= 0) {
    return null;
  }
  return best.versionNumber;
}

/// Counts modrinth-source entries across every section of [newLock] that have
/// a newer compatible version available in [versionsPerSlug]. `url`/`path`
/// sources are ignored — there's no "latest" concept for them.
int countOutdated(
  ModsLock newLock,
  Map<String, List<modrinth.Version>> versionsPerSlug,
) {
  var n = 0;
  for (final section in Section.values) {
    final sectionMap = newLock.sectionFor(section);
    for (final entry in sectionMap.entries) {
      final locked = entry.value;
      if (locked.sourceKind != LockedSourceKind.modrinth) continue;
      final nr = newerAvailableThan(
        locked.version ?? '',
        versionsPerSlug[entry.key],
      );
      if (nr != null) n++;
    }
  }
  return n;
}

/// Builds a single dart-pub-style report line, or null to omit the entry.
///
/// Mirrors `SolveReport._reportPackage` from the pub source: prefix icon,
/// bold-less slug, version (or `from path/url …` for non-modrinth sources),
/// then ordered parentheticals — `(was oldv)` when upgraded/downgraded,
/// `(overridden)` when remapped via an `overrides:` block, and
/// `(X available)` when a newer loader+mc-compatible version exists.
///
/// Icons follow pub: `!` overridden, `+` added, `>` upgraded, `<`
/// downgraded, `*` other change (source kind swap), `  ` unchanged.
/// Removed entries are rendered separately by the caller under the
/// "These packages are no longer being depended on:" heading.
String? formatReportLine({
  required LockedEntry locked,
  required LockDiff? diff,
  required String? newerAvailable,
  required bool isOverridden,
}) {
  final kind = diff?.kind;
  String? icon;
  String? wasVersion;
  if (kind == DiffKind.updated) {
    final before = diff!.before;
    final after = diff.after;
    final sourceChanged = before?.sourceKind != after?.sourceKind;
    if (sourceChanged) {
      icon = '* ';
    } else {
      // Both are LockedEntry with version fields. Compare parsed semver
      // to pick `>` / `<`; fall back to `*` for unparseable or path/url
      // entries where only `path`/`url` changed.
      final bv = before?.version;
      final av = after?.version;
      if (bv != null && av != null) {
        try {
          final bp = parseModrinthVersion(bv);
          final ap = parseModrinthVersion(av);
          icon = ap > bp ? '> ' : (ap < bp ? '< ' : '* ');
        } on FormatException {
          icon = '* ';
        }
      } else {
        icon = '* ';
      }
      wasVersion = bv ?? before?.path;
    }
  } else if (kind == DiffKind.added) {
    icon = '+ ';
  } else if (newerAvailable != null) {
    // Unchanged but outdated — pub prints these with the two-space icon.
    icon = '  ';
  }
  // Override icon wins over the diff-derived icon, but `wasVersion` from
  // the update branch is preserved so all three parentheticals can render.
  if (isOverridden) {
    icon = '! ';
  }
  if (icon == null) return null;

  final buf = StringBuffer(icon)..write(locked.slug);
  switch (locked.sourceKind) {
    case LockedSourceKind.modrinth:
      if (locked.version != null) {
        buf.write(' ');
        buf.write(locked.version);
      }
      break;
    case LockedSourceKind.url:
      final url = locked.file?.url;
      buf.write(' from url ${url ?? ''}'.trimRight());
      break;
    case LockedSourceKind.path:
      buf.write(' from path ${locked.path}');
      break;
  }
  if (wasVersion != null) {
    buf.write(' (was $wasVersion)');
  }
  if (isOverridden) {
    buf.write(' (overridden)');
  }
  if (newerAvailable != null) {
    buf.write(' ($newerAvailable available)');
  }
  return buf.toString();
}

/// Emits `dart pub get`-style output for a resolve. Shared by every command
/// that mutates the lockfile so `+ slug version` / `- slug version` /
/// `> slug version (was …)` lines are identical across `get`, `add`, and
/// `remove`.
class SolveReporter {
  final Console console;

  SolveReporter(this.console);

  /// Prints the per-entry report for a finished resolve: lazy
  /// `Downloading packages…` header, one line per rendered entry (in
  /// [Section.values] order then section-map key order), and a trailing
  /// `These packages are no longer being depended on:` block listing removed
  /// entries. Silent when no entry would render (clean rerun with nothing
  /// outdated).
  void printReport({
    required ModsLock newLock,
    required List<LockDiff> diff,
    required Map<String, List<modrinth.Version>> versionsPerSlug,
    required Set<String> overriddenSlugs,
  }) {
    final diffByKey = <String, LockDiff>{
      for (final d in diff) '${d.section.name}/${d.slug}': d,
    };

    final reportLines = <String>[];
    for (final section in Section.values) {
      final sectionMap = newLock.sectionFor(section);
      for (final slug in sectionMap.keys) {
        final locked = sectionMap[slug]!;
        final newerRaw = locked.sourceKind == LockedSourceKind.modrinth
            ? newerAvailableThan(locked.version ?? '', versionsPerSlug[slug])
            : null;
        final isOverridden = overriddenSlugs.contains(slug);
        final d = diffByKey['${section.name}/$slug'];
        final line = formatReportLine(
          locked: locked,
          diff: d,
          newerAvailable: newerRaw,
          isOverridden: isOverridden,
        );
        if (line != null) reportLines.add(line);
      }
    }
    // Appended-at-end section mirroring dart pub's "These packages are no
    // longer being depended on:" block.
    final removedDiffs = diff.where((d) => d.kind == DiffKind.removed).toList();
    if (removedDiffs.isNotEmpty) {
      reportLines.add('These packages are no longer being depended on:');
      for (final d in removedDiffs) {
        final v = d.before?.version ?? d.before?.path ?? '';
        reportLines.add('- ${d.slug}${v.isEmpty ? '' : ' $v'}');
      }
    }

    if (reportLines.isNotEmpty) {
      console.message('Downloading packages...');
      for (final l in reportLines) {
        console.message(l);
      }
    }
  }

  /// Prints the trailing line(s): either `Got dependencies!` or
  /// `Changed N dependency/dependencies!`, followed by the
  /// `N package(s) have newer versions available.` hint when [outdated] > 0.
  void printSummary({required int changeCount, required int outdated}) {
    if (changeCount > 0) {
      console.message(
        Intl.plural(
          changeCount,
          one: 'Changed $changeCount dependency!',
          other: 'Changed $changeCount dependencies!',
        ),
      );
    } else {
      console.message('Got dependencies!');
    }
    if (outdated > 0) {
      console.message(
        Intl.plural(
          outdated,
          one: '$outdated package has a newer version available.',
          other: '$outdated packages have newer versions available.',
        ),
      );
    }
  }

  /// Legacy one-line-per-change format used in `--dry-run` and at
  /// `--verbosity=io` and above. Prints `mods.lock unchanged.` when
  /// [diff] is empty. When [force] is true the lines print
  /// unconditionally (dry-run); otherwise they go through `console.io`
  /// so the floor decides.
  void printSimpleDiff(List<LockDiff> diff, {bool force = false}) {
    void emit(String line) {
      if (force) {
        console.message(line);
      } else {
        console.io(line);
      }
    }

    if (diff.isEmpty) {
      emit('mods.lock unchanged.');
      return;
    }
    for (final d in diff) {
      final symbol = switch (d.kind) {
        DiffKind.added => '+',
        DiffKind.removed => '-',
        DiffKind.updated => '~',
        DiffKind.unchanged => ' ',
      };
      final beforeV = d.before?.version ?? d.before?.path ?? '(none)';
      final afterV = d.after?.version ?? d.after?.path ?? '(none)';
      emit('$symbol ${d.section.name}/${d.slug}: $beforeV -> $afterV');
    }
  }
}
