import '../../model/curseforge/cf_mod_file.dart';
import '../../model/resolver/constraint.dart';

/// CF has no version-number field. Prefer the display label, then filename.
/// Keep the extracted number shared with `add` so emitted constraints resolve
/// against the same value on subsequent runs.
String? curseForgeFileVersion(ModFile file) {
  final pattern = RegExp(r'\d+\.\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?');
  for (final label in [file.displayName, file.fileName]) {
    var normalized = label;
    for (final mc in file.gameVersions.where(
      (v) => RegExp(r'^\d+\.\d+(?:\.\d+)?$').hasMatch(v),
    )) {
      normalized = normalized.replaceAllMapped(
        RegExp(
          '(^|[^0-9.])(?:mc|minecraft)?${RegExp.escape(mc)}(?=\$|[^0-9.])',
          caseSensitive: false,
        ),
        (match) => match.group(1)!,
      );
    }
    final match = pattern.firstMatch(normalized);
    if (match != null) {
      return match.group(0)!.replaceFirst(RegExp(r'\.(jar|zip)$'), '');
    }
  }
  return null;
}

bool curseForgeFileSatisfies(ModFile file, String? raw) {
  if (raw == null || raw.trim().isEmpty) return true;
  if (file.displayName == raw || file.fileName == raw) return true;
  final version = curseForgeFileVersion(file);
  if (version == null) return false;
  return parseConstraint(raw).allows(parseModrinthVersionBestEffort(version));
}
