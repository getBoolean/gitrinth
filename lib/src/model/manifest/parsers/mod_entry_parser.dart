part of '../parser.dart';

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
