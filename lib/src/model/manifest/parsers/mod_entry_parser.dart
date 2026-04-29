part of '../parser.dart';

Map<String, ModEntry> _parseSection(
  dynamic raw,
  String sectionName,
  String filePath,
  Section section, {
  LoaderConfig? loader,
}) {
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
    result[slug] = _parseEntry(
      slug,
      value,
      sectionName,
      filePath,
      section,
      loader: loader,
    );
  });
  return result;
}

ModEntry _parseEntry(
  String slug,
  dynamic raw,
  String sectionName,
  String filePath,
  Section section, {
  LoaderConfig? loader,
}) {
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
  final modrinthHostRaw = m['modrinth_host'];
  final url = m['url'];
  final path = m['path'];
  // `modrinth_host` co-exists with the Modrinth source kind (it's a
  // host override on `modrinth:`-style entries), but is mutually
  // exclusive with `url:` / `path:` because those select different
  // source kinds entirely. The schema's `not` clauses already enforce
  // this; mirror the check here so the parser-only path also gets a
  // clear error.
  if (modrinthHostRaw != null && (url != null || path != null)) {
    throw _err(
      '$filePath: $sectionName/$slug declares modrinth_host with '
      '${url != null ? 'url' : 'path'}; modrinth_host applies to the '
      'Modrinth source kind only.',
    );
  }
  if (url != null && path != null) {
    throw _err(
      '$filePath: $sectionName/$slug declares both url: and path:. '
      'Choose at most one.',
    );
  }
  String? modrinthHost;
  if (modrinthHostRaw != null) {
    if (modrinthHostRaw is! String || modrinthHostRaw.isEmpty) {
      throw _err(
        '$filePath: $sectionName/$slug modrinth_host must be a '
        'non-empty URL string.',
      );
    }
    modrinthHost = modrinthHostRaw;
  }
  EntrySource source = ModrinthEntrySource(host: modrinthHost);
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
  final modrinthSlug = _parseOptionalStringField(
    m,
    'modrinth',
    '$sectionName/$slug',
    filePath,
  );
  final curseforgeSlug = _parseOptionalStringField(
    m,
    'curseforge',
    '$sectionName/$slug',
    filePath,
  );
  final sourceSet = _parseSourcesField(
    m['sources'],
    '$sectionName/$slug',
    filePath,
  );

  // CurseForge eligibility check. The plan locates this with the
  // existing plugin/shader validation pass (lines around 173) so all
  // section-aware policy lives in one place. CurseForge resolution
  // proper ships in a later part of the bridge — this guard already
  // applies because `curseforge:` and `sources: curseforge` are now
  // syntactically valid.
  if (loader != null) {
    final wantsCurseforge =
        (sourceSet?.contains(SourceKind.curseforge) ?? false) ||
        curseforgeSlug != null;
    if (wantsCurseforge && !sectionAllowsCurseforge(section, loader.plugins)) {
      throw _err(
        '$filePath: $sectionName/$slug declares a CurseForge source '
        '(sources: curseforge or curseforge:) but the section/loader '
        'combination does not allow CurseForge. CurseForge plugin '
        'entries are limited to bukkit/spigot/paper. See '
        'docs/curseforge-bridge.md#source-eligibility-matrix.',
      );
    }
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
  if (section == Section.plugins) {
    if (server == SideEnv.unsupported) {
      throw _err(
        '$filePath: $sectionName/$slug plugins must install on the '
        'server (`server: required` or `server: optional`); plugins do '
        'not run client-side.',
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
    m['accepts_mc'],
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
    modrinthSlug: modrinthSlug,
    curseforgeSlug: curseforgeSlug,
    sources: sourceSet,
  );
}

String? _parseOptionalStringField(
  Map<String, dynamic> m,
  String key,
  String where,
  String filePath,
) {
  if (!m.containsKey(key)) return null;
  final raw = m[key];
  if (raw == null) return null;
  if (raw is! String || raw.isEmpty) {
    throw _err('$filePath: $where $key must be a non-empty string.');
  }
  return raw.trim();
}

Set<SourceKind>? _parseSourcesField(
  dynamic raw,
  String where,
  String filePath,
) {
  if (raw == null) return null;
  final List<dynamic> items;
  if (raw is String) {
    if (raw.trim().isEmpty) {
      throw _err(
        '$filePath: $where sources must be a non-empty platform name '
        'or list (modrinth, curseforge).',
      );
    }
    items = [raw];
  } else if (raw is List) {
    if (raw.isEmpty) {
      throw _err(
        '$filePath: $where sources must declare at least one '
        'platform when present.',
      );
    }
    items = raw;
  } else {
    throw _err(
      '$filePath: $where sources must be a platform name or a list '
      '(e.g. `modrinth`, `[modrinth, curseforge]`).',
    );
  }
  final seen = <SourceKind>{};
  for (final item in items) {
    if (item is! String) {
      throw _err(
        '$filePath: $where sources entries must be strings; got '
        '${item.runtimeType}.',
      );
    }
    final parsed = _parseSourceKind(item);
    if (parsed == null) {
      throw _err(
        '$filePath: $where sources entry "$item" is not a known platform. '
        'Use `modrinth` or `curseforge`.',
      );
    }
    if (!seen.add(parsed)) {
      throw _err(
        '$filePath: $where sources lists "${parsed.name}" more than once.',
      );
    }
  }
  return seen;
}

SourceKind? _parseSourceKind(String raw) {
  switch (raw.trim()) {
    case 'modrinth':
      return SourceKind.modrinth;
    case 'curseforge':
      return SourceKind.curseforge;
    default:
      return null;
  }
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
    final gameVersionsRaw = m['game_versions'];
    final gameVersions = gameVersionsRaw is List
        ? List<String>.unmodifiable(gameVersionsRaw.map((v) => v.toString()))
        : const <String>[];
    final acceptsMcRaw = m['accepts_mc'];
    final acceptsMc = acceptsMcRaw is List
        ? List<String>.unmodifiable(acceptsMcRaw.map((v) => v.toString()))
        : const <String>[];
    result[slug] = LockedEntry(
      slug: slug,
      sourceKind: sourceKind,
      version: m['version'] as String?,
      projectId: m['project_id'] as String?,
      versionId: m['version_id'] as String?,
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
