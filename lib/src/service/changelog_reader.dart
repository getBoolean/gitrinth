import 'dart:io';

/// Returns the body of the heading matching [version] in [changelogFile],
/// stopping at the next `## ` heading. Returns null when the file or the
/// matching section is absent. Recognized headings:
///
///   `## [1.2.3]`   ← the most common shape
///   `## 1.2.3`
///   `## [1.2.3] - 2026-01-01`
///   `## v1.2.3`
String? readChangelogSection({
  required File changelogFile,
  required String version,
}) {
  if (!changelogFile.existsSync()) return null;
  final lines = changelogFile.readAsLinesSync();
  final pattern = RegExp(
    r'^##\s+(?:v)?\[?' + RegExp.escape(version) + r'\]?(?:\s|$)',
    caseSensitive: false,
  );
  var inSection = false;
  final body = StringBuffer();
  for (final line in lines) {
    if (pattern.hasMatch(line)) {
      inSection = true;
      continue;
    }
    if (inSection) {
      if (line.startsWith('## ')) break;
      body.writeln(line);
    }
  }
  if (!inSection) return null;
  final text = body.toString().trim();
  return text.isEmpty ? null : text;
}
