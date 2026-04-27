import 'mods_yaml.dart';

/// Loader names accepted by [parseLoaderRef].
/// `vanilla` stays last because it is the no-mod-runtime sentinel.
const List<String> loaderRefNames = ['forge', 'fabric', 'neoforge', 'vanilla'];

/// Result of [parseLoaderRef].
/// For [ModLoader.vanilla], the tag is always `null`.
typedef LoaderRef = (ModLoader loader, String? tag);

/// Parses a `loader` or `loader:tag` reference.
/// Shared by `mods.yaml`, `migrate loader`, and `create --loader`.
/// Missing tags return `null`; callers choose their own default.
LoaderRef parseLoaderRef(String raw, Never Function(String message) onError) {
  final colon = raw.indexOf(':');
  final namePart = (colon < 0 ? raw : raw.substring(0, colon)).toLowerCase();
  final tagPart = colon < 0 ? null : raw.substring(colon + 1);

  if (namePart == 'vanilla') {
    if (tagPart != null) {
      onError(
        '"$raw" must not carry a version tag '
        '(write `vanilla` or omit it entirely).',
      );
    }
    return (ModLoader.vanilla, null);
  }

  if (tagPart != null) {
    if (tagPart.isEmpty) {
      onError(
        '"$raw" has an empty version tag '
        '(use `<loader>` or `<loader>:<version|stable|latest>`).',
      );
    }
    if (tagPart.contains(':')) {
      onError(
        '"$raw" has more than one `:` '
        '(expected `<loader>` or `<loader>:<version|stable|latest>`).',
      );
    }
  }

  switch (namePart) {
    case 'forge':
      return (ModLoader.forge, tagPart);
    case 'fabric':
      return (ModLoader.fabric, tagPart);
    case 'neoforge':
      return (ModLoader.neoforge, tagPart);
  }
  onError(
    '"$namePart" is not a recognized loader '
    '(allowed: forge, fabric, neoforge, vanilla).',
  );
}
