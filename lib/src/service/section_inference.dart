import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';

/// Infers the `mods.yaml` [Section] from a Modrinth project response.
///
/// Maps `project_type` plus the `loaders` array onto a section:
///   - `resourcepack`  → [Section.resourcePacks]
///   - `shader`        → [Section.shaders]
///   - `datapack`      → [Section.dataPacks]
///   - `mod`           → [Section.mods], except when the project's only
///     non-mod loader-tag is a datapack-shaped one — Modrinth stores
///     datapack projects like Terralith under `project_type: mod` with
///     `loaders: [datapack]`, so we route them to [Section.dataPacks].
///   - `modpack`       → throws (packs can't embed other packs in MVP).
///   - `plugin`        → [Section.plugins].
///
/// Throws a [ValidationError] for unhandled shapes so the caller can
/// surface a single-line message without a stack trace.
Section inferSectionFromProject({
  required String projectType,
  required List<String> loaders,
}) {
  switch (projectType.toLowerCase()) {
    case 'resourcepack':
      return Section.resourcePacks;
    case 'shader':
      return Section.shaders;
    case 'datapack':
      return Section.dataPacks;
    case 'mod':
      // Terralith-style: Modrinth labels it `mod` but the loaders array
      // only contains datapack-shaped entries. The stability floor here is
      // "every declared loader is one of the known data-pack loaders".
      final lowered = loaders.map((l) => l.toLowerCase()).toSet();
      if (lowered.isNotEmpty && lowered.every(_isDataPackLoader)) {
        return Section.dataPacks;
      }
      return Section.mods;
    case 'modpack':
      throw const ValidationError('cannot add a modpack to a modpack.');
    case 'plugin':
      return Section.plugins;
    default:
      throw ValidationError(
        'unknown Modrinth project_type "$projectType"; cannot infer section.',
      );
  }
}

/// Known Modrinth `loaders` tags that indicate a datapack-shaped artifact.
/// Kept conservative — anything else flips the mod → mods section.
bool _isDataPackLoader(String loader) {
  switch (loader) {
    case 'datapack':
    case 'minecraft':
      // `minecraft` appears on e.g. Modrinth data-pack-only projects that
      // don't declare a loader. Treating it as data-pack-shaped is the
      // conservative call — the only other place `minecraft` shows up is
      // resource-pack projects, which already route via `project_type:
      // resourcepack`.
      return true;
    default:
      return false;
  }
}

/// Infers a section from a local filename or URL path.
///
/// Used for `gitrinth add --url ...` and `gitrinth add --path ...` where the
/// Modrinth project type isn't available. Returns `null` when the extension
/// and MIME lookup both come back ambiguous — the caller should surface a
/// [ValidationError] asking the user to pick a section manually.
///
///   - `.jar` / `application/java-archive` → [Section.mods]
///   - `.zip` alone → null (ambiguous: resource pack vs. data pack vs. shader).
Section? inferSectionFromFilename(String filenameOrPath) {
  if (filenameOrPath.isEmpty) return null;
  final ext = p.extension(filenameOrPath).toLowerCase();
  // Strip URL query/fragment noise for MIME lookup.
  final cleaned = _stripUrlNoise(filenameOrPath);

  // Tier 1: by extension.
  switch (ext) {
    case '.jar':
      return Section.mods;
  }

  // Tier 2: by MIME (the mime package works purely from extension +
  // magic-bytes database, no I/O).
  final mime = lookupMimeType(cleaned);
  switch (mime) {
    case 'application/java-archive':
      return Section.mods;
  }

  // Ambiguous (.zip with no other signal). Caller raises the error so it can
  // include context like the user-provided URL/path.
  return null;
}

String _stripUrlNoise(String input) {
  final qIndex = input.indexOf('?');
  final hIndex = input.indexOf('#');
  var cut = input.length;
  if (qIndex >= 0 && qIndex < cut) cut = qIndex;
  if (hIndex >= 0 && hIndex < cut) cut = hIndex;
  return input.substring(0, cut);
}
