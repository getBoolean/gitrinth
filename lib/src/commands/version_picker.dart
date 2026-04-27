import 'package:dio/dio.dart';

import '../cli/exceptions.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/modrinth/version.dart' as modrinth;
import '../model/resolver/constraint.dart';
import '../service/modrinth_api.dart';

/// Picks the latest **release** version of [slug] satisfying the
/// supplied loader/mc filter. Returns null when no eligible version
/// exists. Used by `add` and `override` to resolve an implicit-latest
/// pin (positional `<slug>` with no `@<constraint>`).
Future<modrinth.Version?> pickLatestReleaseVersion({
  required ModrinthApi api,
  required String slug,
  required Section section,
  required LoaderConfig loaderConfig,
  required String mcVersion,
  List<String> acceptsMc = const [],
}) async {
  final loaderFilter = filterLoadersForSection(loaderConfig, section);
  final gameVersions = <String>{mcVersion, ...acceptsMc}.toList();
  final List<modrinth.Version> versions;
  try {
    versions = await api.listVersions(
      slug,
      loadersJson: loaderFilter == null
          ? null
          : encodeFilterArray(loaderFilter),
      gameVersionsJson: encodeFilterArray(gameVersions),
    );
  } on DioException catch (e) {
    final err = e.error;
    if (err is GitrinthException) throw err;
    rethrow;
  }
  modrinth.Version? best;
  dynamic bestParsed;
  for (final v in versions) {
    if ((v.versionType ?? 'release') != 'release') continue;
    try {
      final parsed = parseModrinthVersionBestEffort(v.versionNumber);
      if (bestParsed == null || parsed > bestParsed) {
        bestParsed = parsed;
        best = v;
      }
    } on FormatException {
      // skip — only reached for pure-symbol inputs the fallback
      // can't sanitise into a legal pre-release identifier.
    }
  }
  return best;
}

/// Maps a [Section] to the `loaders=` filter array gitrinth uses when
/// listing Modrinth versions for that section. Mods use the loader
/// declared in `mods.yaml`; shaders and plugins use the declared
/// shader/plugin loader if any; resource packs and data packs use
/// Modrinth's fixed sentinel values. Single source of truth — callers
/// route through this helper instead of switching on [Section]
/// themselves.
List<String>? filterLoadersForSection(LoaderConfig config, Section section) {
  switch (section) {
    case Section.mods:
      // No mod runtime — there is nothing to filter against. Modrinth
      // has no `vanilla` loader token; null tells the caller to skip
      // resolution for the mods section. The parser already rejects
      // populated `mods:` entries under vanilla, so this branch is
      // only ever hit by code that walks every section unconditionally.
      return config.hasModRuntime ? [config.mods.name] : null;
    case Section.shaders:
      final shaders = config.shaders;
      return shaders == null ? null : [shaders.name];
    case Section.resourcePacks:
      return const ['minecraft'];
    case Section.dataPacks:
      return const ['datapack'];
    case Section.plugins:
      final plugins = config.plugins;
      return plugins == null ? null : [plugins.modrinthLoaderToken];
  }
}

/// Produces the default-written constraint for an implicit-latest pin.
/// Uses a caret on `major.minor.patch` when [latest] parses as semver,
/// and falls back to pinning the raw version verbatim when it doesn't
/// — some Modrinth mods use arbitrary strings as version names, and
/// carets have no meaning for those.
String caretOrPinFallback(String latest) {
  try {
    final parsed = parseModrinthVersion(latest);
    return '^${parsed.major}.${parsed.minor}.${parsed.patch}';
  } on FormatException {
    return latest;
  }
}

/// Returns a human-readable display loader name for the supplied
/// [section] under [config], or null when the section uses Modrinth's
/// fixed sentinel (`minecraft` / `datapack`).
String? loaderNameForSection(LoaderConfig config, Section section) {
  switch (section) {
    case Section.mods:
      return config.hasModRuntime ? config.mods.name : null;
    case Section.shaders:
      return config.shaders?.name;
    case Section.plugins:
      return config.plugins?.modrinthLoaderToken;
    case Section.resourcePacks:
    case Section.dataPacks:
      return null;
  }
}
