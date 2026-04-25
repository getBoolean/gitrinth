import 'package:pub_semver/pub_semver.dart';

/// Parses an MC version string into a [Version]. Two-component shorthand
/// like `1.21` or `26.1` is canonicalized to `<major>.<minor>.0` before
/// delegation to [Version.parse], which otherwise rejects two-component
/// strings.
///
/// MC-scoped on purpose: regular `Version.parse` callers parse mod
/// versions, which obey strict semver — relaxing the global parse rule
/// would mask malformed mod metadata.
Version parseMcVersion(String mc) {
  final canonical = RegExp(r'^\d+\.\d+$').hasMatch(mc) ? '$mc.0' : mc;
  return Version.parse(canonical);
}
