import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/resolver/constraint.dart';
import '../service/console.dart';
import '../service/manifest_io.dart';
import 'pin_editor.dart';

/// Rewrites caret-bound entries in `mods.yaml` to `^<bare>` for the resolved
/// version when the existing caret no longer admits it (`majorVersions`) or
/// the lower bound is stale (`tighten`). Shared by `upgrade` and `migrate`.
void rewriteCaretConstraints({
  required ManifestIo io,
  required Console console,
  required Map<(Section, String), ModEntry> modrinthByEntry,
  required Set<String> targets,
  required Set<String> relaxSet,
  required bool majorVersions,
  required bool tighten,
  required ModsLock newLock,
}) {
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
      console.message(
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
    console.message('$slug: $raw → $newConstraint in mods.yaml');
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
/// the raw string when parsing fails. Used by the `tighten` predicate to
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
