import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/constraint.dart';
import '../model/resolver/pubgrub.dart';
import 'console.dart';
import 'resolve_and_sync.dart';

/// Outcome of [resolveWithConflictAutoDisable]: the second-pass
/// resolve result plus the slugs the helper auto-disabled (empty when
/// the first pass succeeded). Used by `migrate` and `upgrade
/// --major-versions` to write the `gitrinth:disabled-by-conflict`
/// markers back to disk.
class ConflictDisableOutcome {
  final ResolveSyncResult result;
  final Set<(Section, String)> disabledByConflict;
  final UnsatisfiableGraphError? originalError;

  const ConflictDisableOutcome({
    required this.result,
    required this.disabledByConflict,
    required this.originalError,
  });

  factory ConflictDisableOutcome.singlePass(ResolveSyncResult r) =>
      ConflictDisableOutcome(
        result: r,
        disabledByConflict: const {},
        originalError: null,
      );
}

/// Closure shape for the resolve call inside
/// [resolveWithConflictAutoDisable]. Lets each call site (`migrate`,
/// `upgrade --major-versions`) supply its own pre-built `freshSlugs`
/// and `relaxConstraints` while sharing the auto-disable retry path.
typedef ResolveCall = Future<ResolveSyncResult> Function({
  required ModsYaml manifestForResolve,
  required Set<String> freshSlugs,
  required Set<String> relaxConstraints,
});

/// Wraps [resolve] with the auto-disable retry path. On
/// [UnsatisfiableGraphError], computes the disable set from
/// `e.conflictingUserSlugs`, applies the
/// `gitrinth:disabled-by-conflict` marker in-memory, and re-resolves
/// with the disabled slugs removed from `relaxConstraints`. If the
/// second pass also fails, throws [ValidationError] with both
/// messages.
///
/// [manifest] is the base `mods.yaml` (unmodified). It's used only to
/// look up which section a conflicting slug lives in, so the marker
/// rewrite hits the correct section.
///
/// [resolutionManifest] is the manifest the first-pass resolve uses
/// (typically [manifest] with already-known unrecoverable entries
/// stripped, e.g. by `migrate`).
Future<ConflictDisableOutcome> resolveWithConflictAutoDisable({
  required ModsYaml manifest,
  required ModsYaml resolutionManifest,
  required Set<String> targets,
  required Set<String> relaxSet,
  required Console console,
  required ResolveCall resolve,
}) async {
  ResolveSyncResult result;
  final disabledByConflict = <(Section, String)>{};
  UnsatisfiableGraphError? originalError;
  try {
    result = await resolve(
      manifestForResolve: resolutionManifest,
      freshSlugs: targets,
      relaxConstraints: relaxSet,
    );
  } on UnsatisfiableGraphError catch (e) {
    originalError = e;
    for (final slug in e.conflictingUserSlugs) {
      for (final section in Section.values) {
        if (manifest.sectionEntries(section).containsKey(slug)) {
          disabledByConflict.add((section, slug));
          break;
        }
      }
    }
    if (disabledByConflict.isEmpty) rethrow;

    // Apply the markers in-memory and re-resolve. The retry must NOT
    // relax the disabled slugs — their `disabledByConflictMarker` has
    // to reach the resolver-skip in `resolver.dart`, otherwise the
    // resolve_and_sync constraint relaxation would rewrite it back to
    // `null` (= any) and PubGrub would re-encounter the same conflict.
    final candidateManifest = applyDisableMarkers(
      resolutionManifest,
      disabledByConflict,
    );
    final retryRelax = relaxSet.difference({
      for (final s in disabledByConflict) s.$2,
    });
    try {
      result = await resolve(
        manifestForResolve: candidateManifest,
        freshSlugs: targets,
        relaxConstraints: retryRelax,
      );
    } on UnsatisfiableGraphError catch (cascade) {
      throw ValidationError(
        'Disabling ${disabledByConflict.map((s) => s.$2).join(", ")} did '
        'not resolve the conflict — re-resolution still failed:\n'
        '${cascade.message}\n\n'
        'Original failure:\n${e.message}',
      );
    }
    final names = disabledByConflict.map((s) => s.$2).toList()..sort();
    console.message(
      'disabled ${names.length} mod(s) due to dependency conflict: '
      '${names.join(", ")}. Edit mods.yaml to re-enable any you want '
      'back, then re-run.',
    );
  }
  return ConflictDisableOutcome(
    result: result,
    disabledByConflict: disabledByConflict,
    originalError: originalError,
  );
}

/// Returns [manifest] with each `(section, slug)` in [disabled]
/// rewritten to carry `constraintRaw: disabledByConflictMarker`.
/// Mirrors the in-memory marker-application migrate has done since
/// the auto-disable feature shipped.
ModsYaml applyDisableMarkers(
  ModsYaml manifest,
  Set<(Section, String)> disabled,
) {
  if (disabled.isEmpty) return manifest;
  Map<String, ModEntry> mark(
    Section section,
    Map<String, ModEntry> m,
  ) =>
      {
        for (final e in m.entries)
          e.key: disabled.contains((section, e.key))
              ? e.value.copyWith(constraintRaw: disabledByConflictMarker)
              : e.value,
      };
  return manifest.copyWith(
    mods: mark(Section.mods, manifest.mods),
    resourcePacks: mark(Section.resourcePacks, manifest.resourcePacks),
    dataPacks: mark(Section.dataPacks, manifest.dataPacks),
    shaders: mark(Section.shaders, manifest.shaders),
  );
}
