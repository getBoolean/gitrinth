part of '../parser.dart';

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
        ? _parseSideEnv(
            m['client'],
            'files/$dest',
            'client',
            filePath,
            allowOptional: false,
          )
        : SideEnv.required;
    final server = m.containsKey('server')
        ? _parseSideEnv(
            m['server'],
            'files/$dest',
            'server',
            filePath,
            allowOptional: false,
          )
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
