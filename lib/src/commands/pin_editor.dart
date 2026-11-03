import '../model/manifest/mods_yaml.dart';
import 'entry_version_editor.dart';

/// Rewrites the constraint for `<section>.<slug>` in [yamlText] to
/// [newConstraint], preserving comments and formatting via `yaml_edit`.
///
/// Handles both short form (`slug: ^1.2.3`) and long form (`slug:\n
/// version: ^1.2.3\n ...`). Long-form entries without a `version:` key
/// (e.g. `url:` or `path:` sourced) are rejected — pinning a non-Modrinth
/// entry has no defined meaning.
String updateEntryConstraint(
  String yamlText, {
  required Section section,
  required String slug,
  required String newConstraint,
}) => rewriteEntryVersion(
  yamlText,
  section: section,
  slug: slug,
  version: newConstraint,
  missingVersionAction: '(un)pin',
);
