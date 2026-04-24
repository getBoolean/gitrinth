/// Result of [parseModrinthProjectUrl]: a Modrinth project URL resolves to a
/// [slug] and an optional [typeHint] (the URL's `/<type>/` segment — e.g.
/// `mod`, `datapack`, `resourcepack`, `shader`, `plugin`, `modpack`).
///
/// The type hint is advisory — the authoritative `project_type` still comes
/// from the Modrinth API response, which can differ (e.g. Terralith is served
/// under `/datapack/` but returns `project_type: mod` with `loaders:
/// [datapack]`).
typedef ModrinthProjectRef = ({String slug, String? typeHint});

/// Parses a Modrinth project URL into a slug + type hint, or returns `null`
/// when the input is not a URL. Plain slugs (`sodium`) return `null` so
/// callers can fall through to slug handling.
///
/// Accepted shapes:
///   - `https://modrinth.com/<type>/<slug>`
///   - `http://modrinth.com/<type>/<slug>`
///   - `modrinth.com/<type>/<slug>` (no scheme)
///   - With trailing `/version/<id>`, `/gallery`, `/changelog`, query, anchor.
///
/// Anything that parses as a URL but isn't on `modrinth.com` returns `null`
/// — the caller then emits its own error rather than silently treating it
/// like a slug.
ModrinthProjectRef? parseModrinthProjectUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // Cheap rejection for plain slugs. Anything without a slash or scheme
  // can't be a URL.
  final looksUrlish =
      trimmed.contains('://') ||
      trimmed.startsWith('//') ||
      trimmed.startsWith('modrinth.com/') ||
      trimmed.startsWith('www.modrinth.com/');
  if (!looksUrlish) return null;

  // Normalize so Uri.tryParse treats `modrinth.com/mod/sodium` the same as
  // `https://modrinth.com/mod/sodium`.
  final normalized = trimmed.contains('://')
      ? trimmed
      : (trimmed.startsWith('//') ? 'https:$trimmed' : 'https://$trimmed');

  final uri = Uri.tryParse(normalized);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();
  if (host != 'modrinth.com' && host != 'www.modrinth.com') return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2) return null;

  final typeHint = segments[0].toLowerCase();
  final slug = segments[1];
  if (slug.isEmpty) return null;

  return (slug: slug, typeHint: typeHint);
}
