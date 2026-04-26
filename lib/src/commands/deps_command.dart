import 'dart:convert';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/lock_graph.dart';
import '../service/manifest_io.dart';
import '../util/ascii_tree.dart' as ascii_tree;

class DepsCommand extends GitrinthCommand {
  @override
  String get name => 'deps';

  @override
  String get description => 'Print the resolved dependency tree.';

  @override
  String get invocation => 'gitrinth deps [<slug>] [arguments]';

  DepsCommand() {
    argParser
      ..addOption(
        'style',
        abbr: 's',
        allowed: ['compact', 'tree', 'list'],
        defaultsTo: 'tree',
        help: 'Output style.',
      )
      ..addOption(
        'env',
        allowed: ['client', 'server', 'both'],
        defaultsTo: 'both',
        help: 'Filter entries by environment.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit a machine-readable JSON report. Mutually exclusive with --style.',
      );
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final style = results['style'] as String;
    final env = results['env'] as String;
    final asJson = results['json'] as bool;
    final positional = results.rest;
    final targetSlug = positional.isEmpty ? null : positional.single;

    if (asJson && results.wasParsed('style')) {
      throw UsageError('--json and --style cannot be combined.');
    }

    final io = ManifestIo();
    final lock = io.readModsLock();
    if (lock == null) {
      throw UserError('mods.lock is missing; run `gitrinth get` and retry.');
    }
    final manifest = io.readModsYaml();
    _checkLockFreshness(manifest, lock);

    final cache = read(cacheProvider);

    // Index entries by slug for quick lookup; capture sections so the
    // renderer can prefix `mods/` etc. on direct entries (mirrors dart
    // pub's `mods/<slug>` flavor).
    final lockBySlug = <String, _LockedWithSection>{};
    for (final section in Section.values) {
      lock.sectionFor(section).forEach((slug, locked) {
        lockBySlug[slug] = _LockedWithSection(locked, section);
      });
    }

    // Build child edges per slug from the cached version.json sidecars.
    // Cold-cache entries get an empty edge list; we count them so a
    // trailing footer can warn the user.
    final children = <String, List<String>>{};
    var coldCacheCount = 0;
    final projectIdToSlug = <String, String>{
      for (final entry in lockBySlug.entries)
        if (entry.value.locked.projectId != null)
          entry.value.locked.projectId!: entry.key,
    };
    for (final entry in lockBySlug.entries) {
      final slug = entry.key;
      final locked = entry.value.locked;
      if (locked.sourceKind != LockedSourceKind.modrinth) {
        children[slug] = const [];
        continue;
      }
      final pid = locked.projectId;
      final vid = locked.versionId;
      if (pid == null || vid == null) {
        children[slug] = const [];
        continue;
      }
      final raw = readCachedRequiredChildren(cache, pid, vid);
      if (raw == null) {
        coldCacheCount++;
        children[slug] = const [];
        continue;
      }
      children[slug] = [
        for (final childPid in raw)
          if (projectIdToSlug.containsKey(childPid)) projectIdToSlug[childPid]!,
      ]..sort();
    }

    final visibleSlugs = _filterByEnv(lockBySlug, env);

    if (targetSlug != null) {
      final entry = lockBySlug[targetSlug];
      if (entry == null) {
        throw UsageError("no entry '$targetSlug' in mods.lock.");
      }
      if (entry.locked.dependency != LockedDependencyKind.direct) {
        throw UsageError(
          "'$targetSlug' is a transitive dependency. Run `gitrinth deps` "
          'on the direct entry that pulls it in.',
        );
      }
    }

    if (asJson) {
      _printJson(
        manifest: manifest,
        lockBySlug: lockBySlug,
        children: children,
        visibleSlugs: visibleSlugs,
        targetSlug: targetSlug,
      );
      _printColdCacheWarning(coldCacheCount);
      return exitOk;
    }

    switch (style) {
      case 'tree':
        _printTree(
          manifest: manifest,
          lockBySlug: lockBySlug,
          children: children,
          visibleSlugs: visibleSlugs,
          targetSlug: targetSlug,
        );
        break;
      case 'list':
        _printList(
          lockBySlug: lockBySlug,
          children: children,
          visibleSlugs: visibleSlugs,
          targetSlug: targetSlug,
        );
        break;
      case 'compact':
        _printCompact(
          lockBySlug: lockBySlug,
          children: children,
          visibleSlugs: visibleSlugs,
          targetSlug: targetSlug,
        );
        break;
    }
    _printColdCacheWarning(coldCacheCount);
    return exitOk;
  }

  /// Throws [UserError] when [manifest] declares an entry that
  /// [lock] hasn't recorded — staleness check that mirrors
  /// `_checkUserEntriesPresentInLock` in `resolve_and_sync.dart` but
  /// without coupling `deps` to the resolve path.
  void _checkLockFreshness(ModsYaml manifest, ModsLock lock) {
    final missing = <String>[];
    for (final section in Section.values) {
      final entries = manifest.sectionEntries(section);
      final lockSection = lock.sectionFor(section);
      for (final e in entries.entries) {
        // Marker entries are absent from the lock by design.
        final raw = e.value.constraintRaw;
        if (raw != null &&
            (raw.trim() == 'gitrinth:not-found' ||
                raw.trim() == 'gitrinth:disabled-by-conflict')) {
          continue;
        }
        if (!lockSection.containsKey(e.key)) missing.add(e.key);
      }
    }
    if (missing.isNotEmpty) {
      throw UserError(
        'mods.lock is stale; run `gitrinth get` and retry. '
        'Missing entries: ${missing.join(', ')}.',
      );
    }
  }

  Set<String> _filterByEnv(
    Map<String, _LockedWithSection> lockBySlug,
    String env,
  ) {
    bool keep(LockedEntry locked) {
      switch (env) {
        case 'client':
          return locked.client != SideEnv.unsupported;
        case 'server':
          return locked.server != SideEnv.unsupported;
        case 'both':
        default:
          return true;
      }
    }

    return {
      for (final entry in lockBySlug.entries)
        if (keep(entry.value.locked)) entry.key,
    };
  }

  void _printColdCacheWarning(int n) {
    if (n == 0) return;
    console.warn(
      'dependency edges for $n ${n == 1 ? 'entry are' : 'entries are'} '
      'not cached. Run `gitrinth get` once to populate the cache.',
    );
  }

  Map<String, Map<String, dynamic>> _buildTreeMap({
    required ModsYaml manifest,
    required Map<String, _LockedWithSection> lockBySlug,
    required Map<String, List<String>> children,
    required Set<String> visibleSlugs,
    required String? targetSlug,
  }) {
    String label(String slug, {bool prefixSection = false}) {
      final entry = lockBySlug[slug]!;
      final ver = entry.locked.version ?? entry.locked.path ?? '';
      final prefix = prefixSection ? '${entry.section.name}/' : '';
      return ver.isEmpty ? '$prefix$slug' : '$prefix$slug $ver';
    }

    final seen = <String>{};
    Map<String, Map<String, dynamic>> walk(
      String slug, {
      required bool prefixSection,
    }) {
      if (!seen.add(slug)) {
        return {
          console.gray('$slug...'): const <String, Map<String, dynamic>>{},
        };
      }
      final out = <String, Map<String, dynamic>>{};
      final kids = children[slug] ?? const [];
      for (final child in kids) {
        if (!visibleSlugs.contains(child)) continue;
        out.addAll(walk(child, prefixSection: false));
      }
      return {label(slug, prefixSection: prefixSection): out};
    }

    if (targetSlug != null) {
      return walk(targetSlug, prefixSection: true);
    }

    final root = '${manifest.slug} ${manifest.version}';
    final rootChildren = <String, Map<String, dynamic>>{};

    final directChildren = <String, Map<String, dynamic>>{};
    final transitiveChildren = <String, Map<String, dynamic>>{};

    final directSlugs = [
      for (final e in lockBySlug.entries)
        if (e.value.locked.dependency == LockedDependencyKind.direct &&
            visibleSlugs.contains(e.key))
          e.key,
    ]..sort();
    for (final slug in directSlugs) {
      directChildren.addAll(walk(slug, prefixSection: true));
    }

    final transitiveSlugs = [
      for (final e in lockBySlug.entries)
        if (e.value.locked.dependency == LockedDependencyKind.transitive &&
            visibleSlugs.contains(e.key))
          e.key,
    ]..sort();
    // Reset the seen set so transitives appear in their own subtree even
    // if they were already rendered inline beneath a direct entry.
    seen.clear();
    for (final slug in transitiveSlugs) {
      transitiveChildren.addAll(walk(slug, prefixSection: false));
    }

    if (directChildren.isNotEmpty) {
      rootChildren['direct dependencies'] = directChildren;
    }
    if (transitiveChildren.isNotEmpty) {
      rootChildren['transitive dependencies'] = transitiveChildren;
    }
    return {root: rootChildren};
  }

  void _printTree({
    required ModsYaml manifest,
    required Map<String, _LockedWithSection> lockBySlug,
    required Map<String, List<String>> children,
    required Set<String> visibleSlugs,
    required String? targetSlug,
  }) {
    final tree = _buildTreeMap(
      manifest: manifest,
      lockBySlug: lockBySlug,
      children: children,
      visibleSlugs: visibleSlugs,
      targetSlug: targetSlug,
    );
    final rendered = ascii_tree.fromMap(tree);
    // Trim trailing newline; console.info adds one.
    final lines = rendered.trimRight().split('\n');
    for (final l in lines) {
      console.message(l);
    }
  }

  void _printList({
    required Map<String, _LockedWithSection> lockBySlug,
    required Map<String, List<String>> children,
    required Set<String> visibleSlugs,
    required String? targetSlug,
  }) {
    if (targetSlug != null) {
      _printListForSlug(targetSlug, lockBySlug, children, visibleSlugs);
      return;
    }
    final directSlugs = [
      for (final e in lockBySlug.entries)
        if (e.value.locked.dependency == LockedDependencyKind.direct &&
            visibleSlugs.contains(e.key))
          e.key,
    ]..sort();
    final transitiveSlugs = [
      for (final e in lockBySlug.entries)
        if (e.value.locked.dependency == LockedDependencyKind.transitive &&
            visibleSlugs.contains(e.key))
          e.key,
    ]..sort();

    if (directSlugs.isNotEmpty) {
      console.message('direct dependencies:');
      for (final slug in directSlugs) {
        _printListForSlug(
          slug,
          lockBySlug,
          children,
          visibleSlugs,
          sectionPrefix: true,
        );
      }
    }
    if (transitiveSlugs.isNotEmpty) {
      if (directSlugs.isNotEmpty) console.message('');
      console.message('transitive dependencies:');
      for (final slug in transitiveSlugs) {
        final entry = lockBySlug[slug]!;
        final ver = entry.locked.version ?? entry.locked.path ?? '';
        console.message('- $slug${ver.isEmpty ? '' : ' $ver'}');
      }
    }
  }

  void _printListForSlug(
    String slug,
    Map<String, _LockedWithSection> lockBySlug,
    Map<String, List<String>> children,
    Set<String> visibleSlugs, {
    bool sectionPrefix = true,
  }) {
    final entry = lockBySlug[slug];
    if (entry == null) return;
    final ver = entry.locked.version ?? entry.locked.path ?? '';
    final label = sectionPrefix ? '${entry.section.name}/$slug' : slug;
    console.message('- $label${ver.isEmpty ? '' : ' $ver'}');
    final kids = (children[slug] ?? const [])
        .where(visibleSlugs.contains)
        .toList();
    for (final c in kids) {
      final childEntry = lockBySlug[c];
      if (childEntry == null) continue;
      final childVer =
          childEntry.locked.version ?? childEntry.locked.path ?? '';
      console.message('  - $c${childVer.isEmpty ? '' : ' $childVer'}');
    }
  }

  void _printCompact({
    required Map<String, _LockedWithSection> lockBySlug,
    required Map<String, List<String>> children,
    required Set<String> visibleSlugs,
    required String? targetSlug,
  }) {
    if (targetSlug != null) {
      _printCompactForSlug(targetSlug, lockBySlug, children, visibleSlugs);
      return;
    }
    final directSlugs = [
      for (final e in lockBySlug.entries)
        if (e.value.locked.dependency == LockedDependencyKind.direct &&
            visibleSlugs.contains(e.key))
          e.key,
    ]..sort();
    final transitiveSlugs = [
      for (final e in lockBySlug.entries)
        if (e.value.locked.dependency == LockedDependencyKind.transitive &&
            visibleSlugs.contains(e.key))
          e.key,
    ]..sort();

    if (directSlugs.isNotEmpty) {
      console.message('direct dependencies:');
      for (final slug in directSlugs) {
        _printCompactForSlug(
          slug,
          lockBySlug,
          children,
          visibleSlugs,
          sectionPrefix: true,
        );
      }
    }
    if (transitiveSlugs.isNotEmpty) {
      if (directSlugs.isNotEmpty) console.message('');
      console.message('transitive dependencies:');
      for (final slug in transitiveSlugs) {
        final entry = lockBySlug[slug]!;
        final ver = entry.locked.version ?? entry.locked.path ?? '';
        console.message('- $slug${ver.isEmpty ? '' : ' $ver'}');
      }
    }
  }

  void _printCompactForSlug(
    String slug,
    Map<String, _LockedWithSection> lockBySlug,
    Map<String, List<String>> children,
    Set<String> visibleSlugs, {
    bool sectionPrefix = true,
  }) {
    final entry = lockBySlug[slug];
    if (entry == null) return;
    final ver = entry.locked.version ?? entry.locked.path ?? '';
    final label = sectionPrefix ? '${entry.section.name}/$slug' : slug;
    final kids = (children[slug] ?? const [])
        .where(visibleSlugs.contains)
        .toList();
    final kidsText = kids.isEmpty ? '[]' : '[${kids.join(' ')}]';
    console.message('- $label${ver.isEmpty ? '' : ' $ver'} $kidsText');
  }

  void _printJson({
    required ModsYaml manifest,
    required Map<String, _LockedWithSection> lockBySlug,
    required Map<String, List<String>> children,
    required Set<String> visibleSlugs,
    required String? targetSlug,
  }) {
    Iterable<String> targetSlugs() sync* {
      if (targetSlug != null) {
        yield* _walkClosure(targetSlug, children, visibleSlugs);
        return;
      }
      yield* visibleSlugs;
    }

    final packages = <Map<String, dynamic>>[];
    final emitted = <String>{};
    for (final slug in targetSlugs()) {
      if (!emitted.add(slug)) continue;
      final entry = lockBySlug[slug];
      if (entry == null) continue;
      final ver = entry.locked.version ?? entry.locked.path ?? '';
      final kids = (children[slug] ?? const [])
          .where(visibleSlugs.contains)
          .toList();
      packages.add({
        'slug': slug,
        'version': ver.isEmpty ? null : ver,
        'kind': entry.locked.dependency.name,
        'section': entry.section.name,
        'source': entry.locked.sourceKind.name,
        'dependencies': kids,
      });
    }
    final out = {
      'root': manifest.slug,
      'version': manifest.version,
      'packages': packages,
    };
    console.raw(const JsonEncoder.withIndent('  ').convert(out));
  }

  Iterable<String> _walkClosure(
    String start,
    Map<String, List<String>> children,
    Set<String> visibleSlugs,
  ) sync* {
    final seen = <String>{};
    final queue = <String>[start];
    while (queue.isNotEmpty) {
      final slug = queue.removeAt(0);
      if (!seen.add(slug)) continue;
      yield slug;
      for (final c in children[slug] ?? const <String>[]) {
        if (visibleSlugs.contains(c)) queue.add(c);
      }
    }
  }
}

class _LockedWithSection {
  final LockedEntry locked;
  final Section section;
  const _LockedWithSection(this.locked, this.section);
}
