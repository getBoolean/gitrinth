import 'mods_yaml.dart';

/// All loader names accepted by [parseLoaderRef], in the order shown
/// to humans (CLI help, shell-completion candidates, error messages).
/// `vanilla` last because it's the no-mod-runtime sentinel rather than
/// a real loader.
const List<String> loaderRefNames = ['forge', 'fabric', 'neoforge', 'vanilla'];

/// Result of [parseLoaderRef]: the resolved [ModLoader] plus the
/// version tag the user supplied (or `null` if omitted). For
/// [ModLoader.vanilla] the tag is always `null` — the parser rejects
/// `vanilla:<anything>`.
typedef LoaderRef = (ModLoader loader, String? tag);

/// Parses a `loader` or `loader:tag` reference (the docker-image
/// style shared by `loader.mods` in `mods.yaml`, `migrate loader`,
/// and `gitrinth create --loader`).
///
/// Single source of truth for the form so the three call sites can't
/// drift on accepted spellings or error wording. Each caller supplies
/// its own [onError] to wrap the message in the appropriate exception
/// type (`ValidationError`, `UsageError`, ...) and to prepend its
/// context (file path, command name, flag name, ...). [onError] must
/// not return.
///
/// Tag handling: a missing tag returns `null` and the caller substitutes
/// its own default (the yaml parser defaults to `stable`; `migrate
/// loader` and the lockfile keep `null` until resolved).
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
