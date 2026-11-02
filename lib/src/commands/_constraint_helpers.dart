import '../cli/exceptions.dart';
import '../model/resolver/constraint.dart';
import 'version_picker.dart';

String constraintForSelectedVersion(
  String version, {
  required bool exact,
  required bool pin,
}) => exact
    ? '^$version'
    : pin
    ? bareVersionForPin(version)
    : caretOrPinFallback(version);

String validatedEntryConstraint(String constraint) {
  if (parseChannelToken(constraint) == null) parseConstraint(constraint);
  return constraint;
}

Map<String, Object?> versionEntryFields(
  String version, {
  String? env,
  List<String> acceptsMc = const [],
}) {
  final fields = <String, Object?>{'version': version};
  writeSideFields(fields, env);
  if (acceptsMc.isNotEmpty) {
    fields['accepts_mc'] = acceptsMc.length == 1 ? acceptsMc.first : acceptsMc;
  }
  return fields;
}

String noCompatibleReleaseMessage(
  String slug, {
  required String? loaderName,
  required String mcVersion,
  required List<String> acceptsMc,
}) {
  final widened = acceptsMc.isEmpty
      ? ''
      : ' (widened with accepts-mc=${acceptsMc.join(",")})';
  return "No release version of '$slug' is compatible with "
      "loader=${loaderName ?? '<none>'} "
      'mc=$mcVersion$widened. '
      'Pass `@<version>` explicitly to pin an alpha/beta.';
}

/// Accepts releases, pre/rc, and snapshots; Modrinth validates the
/// actual tag server-side.
final _acceptsMcPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');

/// Validates and de-duplicates the `--accepts-mc` repeated option. Throws
/// [UserError] for any entry that doesn't look like an MC version tag.
List<String> parseAcceptsMcFlag(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final entry in raw) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    if (!_acceptsMcPattern.hasMatch(trimmed)) {
      throw UserError(
        '--accepts-mc "$trimmed" is not a valid Minecraft version tag '
        '(expected forms like "1.21", "1.20.1", "24w10a", or "1.21-pre1").',
      );
    }
    if (seen.add(trimmed)) out.add(trimmed);
  }
  return out;
}

/// Translates the `--env` flag to long-form `client`/`server` keys.
/// `both` (or null) leaves [long] untouched so the parser falls back to
/// the per-section defaults.
void writeSideFields(Map<String, Object?> long, String? envOpt) {
  if (envOpt == null || envOpt == 'both') return;
  if (envOpt == 'client') {
    long['client'] = 'required';
    long['server'] = 'unsupported';
  } else if (envOpt == 'server') {
    long['client'] = 'unsupported';
    long['server'] = 'required';
  }
}
