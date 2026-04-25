import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../cli/exceptions.dart';
import '../resolver/constraint.dart';
import 'file_entry.dart';
import 'mods_lock.dart';
import 'mods_overrides.dart';
import 'mods_yaml.dart';

class _ParseError extends ValidationError {
  const _ParseError(super.message);
}

ValidationError _err(String message) => _ParseError(message);

ModsYaml parseModsYaml(String yamlText, {required String filePath}) {
  final dynamic raw;
  try {
    raw = loadYaml(yamlText);
  } on YamlException catch (e) {
    throw _err('Invalid YAML in $filePath: ${e.message}');
  }
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  final map = _toPlainMap(raw);

  final slug = _requireString(map, 'slug', filePath);
  final name = _requireString(map, 'name', filePath);
  final version = _requireString(map, 'version', filePath);
  final description = _requireString(map, 'description', filePath);
  final loader = _parseLoaderConfig(map['loader'], filePath);
  final mcVersion = _requireString(map, 'mc-version', filePath);

  final mods = _parseSection(map['mods'], 'mods', filePath, Section.mods);
  final resourcePacks = _parseSection(
    map['resource_packs'],
    'resource_packs',
    filePath,
    Section.resourcePacks,
  );
  final dataPacks = _parseSection(
    map['data_packs'],
    'data_packs',
    filePath,
    Section.dataPacks,
  );
  final shaders = _parseSection(
    map['shaders'],
    'shaders',
    filePath,
    Section.shaders,
  );
  // Overrides patch entries in any section; default per-side state to
  // mods-style required/required since that's the most permissive
  // baseline. Per-side fields on the override still win when present.
  final overrides = _parseSection(
    map['overrides'],
    'overrides',
    filePath,
    Section.mods,
  );
  final files = _parseFilesSection(map['files'], filePath);

  if (shaders.isNotEmpty && loader.shaders == null) {
    throw _err(
      "$filePath: manifest has entries under 'shaders:' but no "
      "'loader.shaders' declared. Add e.g. `shaders: iris` under the "
      '`loader:` object.',
    );
  }

  return ModsYaml(
    slug: slug,
    name: name,
    version: version,
    description: description,
    loader: loader,
    mcVersion: mcVersion,
    mods: mods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
    overrides: overrides,
    files: files,
  );
}

/// Parses the top-level `files:` section. Each entry is keyed by
/// destination path (relative to the build env root) and declares a
/// local source path plus per-side state and optional `preserve`.
///
/// Validates that destination keys are relative, normalized, and free
/// of `..` segments. Source-file existence is deferred to build time
/// (mirroring how `path:` mod entries are handled).
Map<String, FileEntry> _parseFilesSection(dynamic raw, String filePath) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw _err('$filePath: files must be a mapping.');
  }
  final result = <String, FileEntry>{};
  raw.forEach((key, value) {
    final dest = key?.toString();
    if (dest == null || dest.isEmpty) {
      throw _err('$filePath: files has an empty destination key.');
    }
    _validateFileDestination(dest, filePath);
    if (value is! Map) {
      throw _err('$filePath: files/$dest must be a mapping.');
    }
    final m = _toPlainMap(value);
    const allowed = {'path', 'client', 'server', 'preserve'};
    for (final k in m.keys) {
      if (!allowed.contains(k)) {
        throw _err(
          '$filePath: files/$dest has unknown key "$k" (allowed: '
          'path, client, server, preserve).',
        );
      }
    }
    final pathRaw = m['path'];
    if (pathRaw == null) {
      throw _err('$filePath: files/$dest is missing required `path:`.');
    }
    if (pathRaw is! String || pathRaw.isEmpty) {
      throw _err('$filePath: files/$dest path must be a non-empty string.');
    }
    final client = m.containsKey('client')
        ? _parseFileSideEnv(m['client'], 'files/$dest', 'client', filePath)
        : SideEnv.required;
    final server = m.containsKey('server')
        ? _parseFileSideEnv(m['server'], 'files/$dest', 'server', filePath)
        : SideEnv.required;
    if (client == SideEnv.unsupported && server == SideEnv.unsupported) {
      throw _err(
        '$filePath: files/$dest has both sides set to `unsupported`; '
        'the file would not install anywhere.',
      );
    }
    final preserveRaw = m['preserve'];
    final bool preserve;
    if (preserveRaw == null) {
      preserve = false;
    } else if (preserveRaw is bool) {
      preserve = preserveRaw;
    } else {
      throw _err(
        '$filePath: files/$dest preserve must be a boolean (got '
        '${preserveRaw.runtimeType}).',
      );
    }
    result[dest] = FileEntry(
      destination: dest,
      sourcePath: pathRaw,
      client: client,
      server: server,
      preserve: preserve,
    );
  });
  return result;
}

void _validateFileDestination(String dest, String filePath) {
  if (dest.startsWith('/') || dest.startsWith('\\')) {
    throw _err(
      '$filePath: files key "$dest" must be a relative path '
      '(no leading separator).',
    );
  }
  if (dest.contains('\\')) {
    throw _err(
      '$filePath: files key "$dest" uses backslashes; use forward '
      'slashes for portability.',
    );
  }
  final segments = p.posix.split(dest);
  for (final seg in segments) {
    if (seg == '..') {
      throw _err(
        '$filePath: files key "$dest" contains a `..` segment; '
        'destination must be relative to the build env root.',
      );
    }
    if (seg == '.' || seg.isEmpty) {
      throw _err(
        '$filePath: files key "$dest" contains an empty or `.` '
        'segment; the path must be normalized.',
      );
    }
  }
  final normalized = p.posix.normalize(dest);
  if (normalized != dest) {
    throw _err(
      '$filePath: files key "$dest" is not normalized (expected '
      '"$normalized").',
    );
  }
}

/// Parses a `client:`/`server:` value on a `files:` entry. v1 only
/// admits `required` and `unsupported`; `optional` is rejected
/// because Modrinth's `.mrpack` overrides tree has no toggle metadata
/// to round-trip the flag, and `gitrinth build` has no UI toggle.
SideEnv _parseFileSideEnv(
  dynamic raw,
  String where,
  String fieldName,
  String filePath,
) {
  switch (raw?.toString()) {
    case 'required':
      return SideEnv.required;
    case 'unsupported':
      return SideEnv.unsupported;
    case 'optional':
      throw _err(
        '$filePath: $where $fieldName "optional" is not supported on '
        '`files:` entries. Modrinth\'s .mrpack overrides tree has no '
        'toggle metadata, and `gitrinth build` has no UI toggle, so '
        '`optional` would have no observable effect. Use `required` '
        'or `unsupported`.',
      );
    default:
      throw _err(
        '$filePath: $where $fieldName "$raw" must be `required` or '
        '`unsupported` (`optional` is reserved).',
      );
  }
}

ModsOverrides parseModsOverrides(String yamlText, {required String filePath}) {
  final raw = yamlText.trim().isEmpty ? null : loadYaml(yamlText);
  if (raw == null) return const ModsOverrides();
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  final map = _toPlainMap(raw);
  final overridesRaw = map['overrides'];
  if (overridesRaw == null) return const ModsOverrides();
  return ModsOverrides(
    overrides: _parseSection(
      overridesRaw,
      'overrides',
      filePath,
      Section.mods,
    ),
  );
}

ModsLock parseModsLock(String yamlText, {required String filePath}) {
  final dynamic raw;
  try {
    raw = loadYaml(yamlText);
  } on YamlException catch (e) {
    throw _err('Invalid YAML in $filePath: ${e.message}');
  }
  if (raw is! YamlMap) {
    throw _err('$filePath: top-level must be a mapping.');
  }
  final map = _toPlainMap(raw);
  final gitrinthVersion = _requireString(map, 'gitrinth-version', filePath);
  final loader = _parseLoaderConfig(map['loader'], filePath);
  final mcVersion = _requireString(map, 'mc-version', filePath);
  final mods = _parseLockSection(map['mods'], 'mods', filePath);
  final resourcePacks = _parseLockSection(
    map['resource_packs'],
    'resource_packs',
    filePath,
  );
  final dataPacks = _parseLockSection(
    map['data_packs'],
    'data_packs',
    filePath,
  );
  final shaders = _parseLockSection(map['shaders'], 'shaders', filePath);
  final files = _parseLockFilesSection(map['files'], filePath);

  if (shaders.isNotEmpty && loader.shaders == null) {
    throw _err(
      "$filePath: lockfile has entries under 'shaders:' but no "
      "'loader.shaders' declared.",
    );
  }

  return ModsLock(
    gitrinthVersion: gitrinthVersion,
    loader: loader,
    mcVersion: mcVersion,
    mods: mods,
    resourcePacks: resourcePacks,
    dataPacks: dataPacks,
    shaders: shaders,
    files: files,
  );
}

/// Permissive parser for the `files:` section in `mods.lock`. Per
/// the project's "lock parser stays permissive" rule, validation
/// errors are limited to structural problems; semantic checks
/// (destination normalization, both-sides-unsupported, etc.) belong
/// in the `mods.yaml` parser.
Map<String, LockedFileEntry> _parseLockFilesSection(
  dynamic raw,
  String filePath,
) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw _err('$filePath: files must be a mapping.');
  }
  final result = <String, LockedFileEntry>{};
  raw.forEach((key, value) {
    final dest = key?.toString();
    if (dest == null || dest.isEmpty) {
      throw _err('$filePath: files has an empty destination key.');
    }
    if (value is! Map) {
      throw _err('$filePath: files/$dest must be a mapping.');
    }
    final m = _toPlainMap(value);
    final pathRaw = m['path'];
    if (pathRaw is! String || pathRaw.isEmpty) {
      throw _err('$filePath: files/$dest path must be a non-empty string.');
    }
    final client = _parseSideEnv(
      m['client'] ?? 'required',
      'files/$dest',
      'client',
      filePath,
    );
    final server = _parseSideEnv(
      m['server'] ?? 'required',
      'files/$dest',
      'server',
      filePath,
    );
    final preserve = m['preserve'] == true;
    result[dest] = LockedFileEntry(
      destination: dest,
      sourcePath: pathRaw,
      client: client,
      server: server,
      preserve: preserve,
      sha512: (m['sha512'] as String?)?.toLowerCase(),
    );
  });
  return result;
}

Map<String, LockedEntry> _parseLockSection(
  dynamic raw,
  String sectionName,
  String filePath,
) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw _err('$filePath: $sectionName must be a mapping.');
  }
  final result = <String, LockedEntry>{};
  raw.forEach((key, value) {
    final slug = key?.toString();
    if (slug == null || slug.isEmpty) {
      throw _err('$filePath: $sectionName has an empty key.');
    }
    if (value is! Map) {
      throw _err('$filePath: $sectionName/$slug must be a mapping.');
    }
    final m = _toPlainMap(value);
    final sourceKind = _parseLockSourceKind(
      m['source'],
      sectionName,
      slug,
      filePath,
    );
    final client = _parseSideEnv(
      m['client'] ?? 'required',
      '$sectionName/$slug',
      'client',
      filePath,
    );
    final server = _parseSideEnv(
      m['server'] ?? 'required',
      '$sectionName/$slug',
      'server',
      filePath,
    );
    final dependency = _parseLockDependencyKind(m['dependency'], m['auto']);
    LockedFile? file;
    final fileRaw = m['file'];
    if (fileRaw != null) {
      if (fileRaw is! Map) {
        throw _err('$filePath: $sectionName/$slug file must be a mapping.');
      }
      final fm = _toPlainMap(fileRaw);
      file = LockedFile(
        name: (fm['name'] as String?) ?? '',
        url: fm['url'] as String?,
        sha1: (fm['sha1'] as String?)?.toLowerCase(),
        sha512: (fm['sha512'] as String?)?.toLowerCase(),
        size: fm['size'] is int
            ? fm['size'] as int
            : (fm['size'] as num?)?.toInt(),
      );
    }
    final gameVersionsRaw = m['game-versions'];
    final gameVersions = gameVersionsRaw is List
        ? List<String>.unmodifiable(gameVersionsRaw.map((v) => v.toString()))
        : const <String>[];
    final acceptsMcRaw = m['accepts-mc'];
    final acceptsMc = acceptsMcRaw is List
        ? List<String>.unmodifiable(acceptsMcRaw.map((v) => v.toString()))
        : const <String>[];
    result[slug] = LockedEntry(
      slug: slug,
      sourceKind: sourceKind,
      version: m['version'] as String?,
      projectId: m['project-id'] as String?,
      versionId: m['version-id'] as String?,
      file: file,
      path: m['path'] as String?,
      client: client,
      server: server,
      dependency: dependency,
      gameVersions: gameVersions,
      acceptsMc: acceptsMc,
    );
  });
  return result;
}

LockedSourceKind _parseLockSourceKind(
  dynamic raw,
  String sectionName,
  String slug,
  String filePath,
) {
  switch (raw?.toString()) {
    case 'modrinth':
      return LockedSourceKind.modrinth;
    case 'url':
      return LockedSourceKind.url;
    case 'path':
      return LockedSourceKind.path;
    default:
      throw _err(
        '$filePath: $sectionName/$slug source "$raw" must be one of '
        'modrinth, url, path.',
      );
  }
}

/// Permissive — `dependency:` is the new field, `auto: true/false` is
/// the legacy one. Either may appear; neither presence is required
/// (default is `direct`). Lock parser stays permissive per the
/// project's "permissive lock parser" rule.
LockedDependencyKind _parseLockDependencyKind(
  dynamic dependencyRaw,
  dynamic legacyAutoRaw,
) {
  if (dependencyRaw is String) {
    return dependencyRaw == 'transitive'
        ? LockedDependencyKind.transitive
        : LockedDependencyKind.direct;
  }
  if (legacyAutoRaw == true) return LockedDependencyKind.transitive;
  return LockedDependencyKind.direct;
}

Map<String, ModEntry> _parseSection(
  dynamic raw,
  String sectionName,
  String filePath,
  Section section,
) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw _err('$filePath: $sectionName must be a mapping.');
  }
  final result = <String, ModEntry>{};
  raw.forEach((key, value) {
    final slug = key?.toString();
    if (slug == null || slug.isEmpty) {
      throw _err('$filePath: $sectionName has an empty key.');
    }
    result[slug] = _parseEntry(slug, value, sectionName, filePath, section);
  });
  return result;
}

ModEntry _parseEntry(
  String slug,
  dynamic raw,
  String sectionName,
  String filePath,
  Section section,
) {
  final defaults = defaultSidesFor(section);
  // Short forms: null (latest), a channel token, or a scalar version constraint.
  if (raw == null) {
    return ModEntry(
      slug: slug,
      constraintRaw: null,
      client: defaults.client,
      server: defaults.server,
    );
  }
  if (raw is String || raw is num || raw is bool) {
    final asText = raw.toString();
    final channelFromShorthand = parseChannelToken(asText);
    if (channelFromShorthand != null) {
      return ModEntry(
        slug: slug,
        constraintRaw: null,
        channel: channelFromShorthand,
        client: defaults.client,
        server: defaults.server,
      );
    }
    return ModEntry(
      slug: slug,
      constraintRaw: asText,
      client: defaults.client,
      server: defaults.server,
    );
  }
  if (raw is! Map) {
    throw _err(
      '$filePath: $sectionName/$slug must be a scalar version or a mapping.',
    );
  }
  final m = _toPlainMap(raw);
  final hosted = m['hosted'];
  final url = m['url'];
  final path = m['path'];
  final sourceCount =
      (hosted == null ? 0 : 1) + (url == null ? 0 : 1) + (path == null ? 0 : 1);
  if (sourceCount > 1) {
    throw _err(
      '$filePath: $sectionName/$slug declares more than one of '
      'hosted/url/path. Choose at most one.',
    );
  }
  if (hosted != null) {
    throw const UserError(
      'hosted source is deferred; use a default-Modrinth slug, url:, or path:.',
    );
  }
  EntrySource source = const ModrinthEntrySource();
  if (url != null) {
    if (url is! String || url.isEmpty) {
      throw _err(
        '$filePath: $sectionName/$slug url must be a non-empty string.',
      );
    }
    source = UrlEntrySource(url: url);
  } else if (path != null) {
    if (path is! String || path.isEmpty) {
      throw _err(
        '$filePath: $sectionName/$slug path must be a non-empty string.',
      );
    }
    source = PathEntrySource(path: path);
  }

  // `version:` accepts the same union the short form does: a channel
  // token (`release`/`beta`/`alpha`) routes to `channel` with no
  // version constraint, anything else is the constraint string. This
  // matches the schema's `modVersion` definition and keeps round-trips
  // through `add` consistent.
  final versionRaw = m['version'];
  String? constraintRaw;
  Channel? channelFromVersion;
  if (versionRaw != null) {
    final asText = versionRaw.toString();
    channelFromVersion = parseChannelToken(asText);
    if (channelFromVersion == null) {
      constraintRaw = asText;
    }
  }
  final channelExplicit = _parseChannelField(
    m['channel'],
    filePath,
    '$sectionName/$slug',
  );
  if (channelFromVersion != null && channelExplicit != null) {
    throw _err(
      '$filePath: $sectionName/$slug declares a channel via both '
      '`version: ${versionRaw.toString().trim()}` and `channel:`. '
      'Use only one.',
    );
  }
  final channel = channelFromVersion ?? channelExplicit;

  if (m.containsKey('environment')) {
    throw _err(
      '$filePath: $sectionName/$slug uses removed `environment:` field. '
      'Use per-side `client:` / `server:` (required|optional|unsupported).',
    );
  }
  if (m.containsKey('optional')) {
    throw _err(
      '$filePath: $sectionName/$slug uses removed `optional:` field. '
      'Use per-side `client:` / `server:` (required|optional|unsupported).',
    );
  }

  var client = defaults.client;
  var server = defaults.server;
  if (m.containsKey('client')) {
    client = _parseSideEnv(
      m['client'],
      '$sectionName/$slug',
      'client',
      filePath,
    );
  }
  if (m.containsKey('server')) {
    server = _parseSideEnv(
      m['server'],
      '$sectionName/$slug',
      'server',
      filePath,
    );
  }
  if (section == Section.shaders) {
    if (server != SideEnv.unsupported) {
      throw _err(
        '$filePath: $sectionName/$slug shaders cannot run server-side; '
        '`server` must be `unsupported`.',
      );
    }
    if (client == SideEnv.unsupported) {
      throw _err(
        '$filePath: $sectionName/$slug shader entries must install on the '
        'client (`client: required` or `client: optional`).',
      );
    }
  }
  if (client == SideEnv.unsupported && server == SideEnv.unsupported) {
    throw _err(
      '$filePath: $sectionName/$slug has both sides set to `unsupported`; '
      'the entry would not install anywhere.',
    );
  }

  final acceptsMc = _parseAcceptsMc(
    m['accepts-mc'],
    '$sectionName/$slug',
    filePath,
  );

  return ModEntry(
    slug: slug,
    constraintRaw: constraintRaw,
    channel: channel,
    client: client,
    server: server,
    source: source,
    acceptsMc: acceptsMc,
  );
}

// Matches Modrinth game_version tags: releases (`1.21`, `1.21.1`),
// pre/rc (`1.21-pre1`), snapshots (`24w10a`, `24w14potato`), historical
// (`b1.7.3`, `a1.2.6`). Modrinth validates the actual tag server-side;
// the pattern just rejects obviously malformed input.
final _mcVersionPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');

List<String> _parseAcceptsMc(dynamic raw, String where, String filePath) {
  if (raw == null) return const [];
  // Accept scalar shorthand (`accepts-mc: 1.21`) and normalize to a
  // single-element list. Bool is rejected below; map/other are caught
  // by the non-list/non-scalar branch.
  final List<dynamic> items;
  if (raw is String || raw is num) {
    items = [raw];
  } else if (raw is List) {
    items = raw;
  } else {
    throw _err(
      '$filePath: $where accepts-mc must be a Minecraft version '
      'string or a list of them (e.g. `1.21` or `[1.21, 1.20.1]`).',
    );
  }
  final seen = <String>{};
  final out = <String>[];
  for (final item in items) {
    // Accept YAML scalars that stringify cleanly (`1.21` parses as
    // double). Reject booleans, maps, lists, null.
    final String asText;
    if (item is String) {
      asText = item;
    } else if (item is num) {
      asText = item.toString();
    } else {
      throw _err(
        '$filePath: $where accepts-mc entries must be Minecraft version '
        'strings; got ${item.runtimeType}.',
      );
    }
    if (!_mcVersionPattern.hasMatch(asText)) {
      throw _err(
        '$filePath: $where accepts-mc entry "$asText" is not a valid '
        'Minecraft version tag (expected forms like "1.21", "1.20.1", '
        '"24w10a", or "1.21-pre1").',
      );
    }
    if (seen.add(asText)) out.add(asText);
  }
  return out;
}

Channel? _parseChannelField(dynamic raw, String filePath, String where) {
  if (raw == null) return null;
  final parsed = parseChannelToken(raw.toString());
  if (parsed == null) {
    throw _err(
      '$filePath: $where channel "$raw" must be one of release, beta, alpha.',
    );
  }
  return parsed;
}

LoaderConfig _parseLoaderConfig(dynamic raw, String filePath) {
  if (raw == null) {
    throw _err('$filePath: loader is required.');
  }
  if (raw is! Map) {
    throw _err(
      '$filePath: loader must be an object (e.g. '
      '`loader: { mods: neoforge }`). The scalar form is no longer '
      'supported.',
    );
  }
  final map = _toPlainMap(raw);
  const allowed = {'mods', 'shaders', 'plugins'};
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw _err(
        '$filePath: loader key "$key" is not recognized '
        '(allowed: mods, shaders, plugins).',
      );
    }
  }

  final modsRaw = map['mods'];
  if (modsRaw == null) {
    throw _err('$filePath: loader.mods is required (e.g. `mods: neoforge`).');
  }
  final modsTag = _parseModLoader(modsRaw, filePath);

  ShaderLoader? shaders;
  if (map.containsKey('shaders')) {
    shaders = _parseShaderLoader(map['shaders'], filePath);
  }

  if (map.containsKey('plugins')) {
    throw _err(
      '$filePath: plugin loader support is deferred; remove '
      '`loader.plugins` until the MVP lands it.',
    );
  }

  return LoaderConfig(
    mods: modsTag.loader,
    modsVersion: modsTag.version,
    shaders: shaders,
  );
}

class _ModLoaderTag {
  final Loader loader;
  final String version;
  const _ModLoaderTag(this.loader, this.version);
}

/// Parses a `loader.mods` value of the form `<name>` or `<name>:<tag>`.
/// Bare `<name>` defaults the tag to `stable`. The tag is `stable`,
/// `latest`, or a concrete version string (validated against Modrinth at
/// resolve time, not here).
_ModLoaderTag _parseModLoader(dynamic raw, String filePath) {
  final asString = raw.toString();
  final colon = asString.indexOf(':');
  final namePart = (colon < 0 ? asString : asString.substring(0, colon))
      .toLowerCase();
  final tagPart = colon < 0 ? 'stable' : asString.substring(colon + 1);
  if (tagPart.isEmpty) {
    throw _err(
      '$filePath: loader.mods "$asString" has an empty version tag '
      '(use `<loader>` or `<loader>:<version|stable|latest>`).',
    );
  }
  if (tagPart.contains(':')) {
    throw _err(
      '$filePath: loader.mods "$asString" has more than one `:` '
      '(expected `<loader>` or `<loader>:<version|stable|latest>`).',
    );
  }
  Loader loader;
  switch (namePart) {
    case 'forge':
      loader = Loader.forge;
      break;
    case 'fabric':
      loader = Loader.fabric;
      break;
    case 'neoforge':
      loader = Loader.neoforge;
      break;
    default:
      throw _err(
        '$filePath: loader.mods "$namePart" is not supported in MVP '
        '(allowed: forge, fabric, neoforge).',
      );
  }
  return _ModLoaderTag(loader, tagPart);
}

ShaderLoader _parseShaderLoader(dynamic raw, String filePath) {
  final lower = raw.toString().toLowerCase();
  switch (lower) {
    case 'iris':
      return ShaderLoader.iris;
    case 'optifine':
      return ShaderLoader.optifine;
    case 'canvas':
      return ShaderLoader.canvas;
    case 'vanilla':
      return ShaderLoader.vanilla;
    default:
      throw _err(
        '$filePath: loader.shaders "$raw" is not recognized '
        '(allowed: iris, optifine, canvas, vanilla).',
      );
  }
}

SideEnv _parseSideEnv(
  dynamic raw,
  String where,
  String fieldName,
  String filePath,
) {
  switch (raw?.toString()) {
    case 'required':
      return SideEnv.required;
    case 'optional':
      return SideEnv.optional;
    case 'unsupported':
      return SideEnv.unsupported;
    default:
      throw _err(
        '$filePath: $where $fieldName "$raw" must be one of '
        'required, optional, unsupported.',
      );
  }
}

String _requireString(Map<String, dynamic> map, String key, String filePath) {
  final value = map[key];
  if (value == null) {
    throw _err('$filePath: missing required field "$key".');
  }
  if (value is! String || value.isEmpty) {
    throw _err('$filePath: "$key" must be a non-empty string.');
  }
  return value;
}

Map<String, dynamic> _toPlainMap(Map yaml) {
  final out = <String, dynamic>{};
  yaml.forEach((k, v) {
    out[k.toString()] = _convert(v);
  });
  return out;
}

dynamic _convert(dynamic v) {
  if (v is YamlMap) return _toPlainMap(v);
  if (v is Map) return _toPlainMap(v);
  if (v is YamlList) return v.map(_convert).toList();
  if (v is List) return v.map(_convert).toList();
  return v;
}
