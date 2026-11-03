import '../../cli/exceptions.dart';
import '../../model/loader/loader_descriptor.dart';

/// Selects only releases with applicability and promotion metadata for this game.
String resolveCatalogLoaderVersion(
  LoaderDescriptor descriptor,
  String tag,
  String mcVersion,
) {
  final catalog = descriptor.catalogVersions;
  if (catalog != null) {
    final matching = catalog.where((v) => v.gameVersion == mcVersion);
    final selected = matching
        .where(
          (v) => switch (tag) {
            'latest' => v.latest,
            'stable' => v.recommended,
            _ => v.name == tag,
          },
        )
        .firstOrNull;
    if (selected != null) return selected.name;
  } else {
    if (tag != 'stable' &&
        tag != 'latest' &&
        (descriptor.versions.isEmpty || descriptor.versions.contains(tag))) {
      return tag;
    }
    if ((tag == 'stable' || tag == 'latest') &&
        descriptor.versions.isNotEmpty) {
      return descriptor.versions.first;
    }
  }
  throw ValidationError(
    'Loader ${descriptor.id.name} has no discovered version matching $tag for Minecraft $mcVersion; supply a compatible concrete version or refresh its provider catalog.',
  );
}
