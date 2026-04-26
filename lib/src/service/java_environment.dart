import 'dart:io';

import 'package:path/path.dart' as p;

/// Picks a `java` executable when no version-aware resolver is available
/// (test paths that don't inject a `JavaResolver`). Prefers
/// `<javaHome>/bin/java[.exe]`; falls back to the bare `java`/`java.exe`
/// name so PATH lookup applies.
File resolveJava(String? javaHome) {
  if (javaHome != null && javaHome.isNotEmpty) {
    final candidate = File(
      p.join(javaHome, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    );
    if (candidate.existsSync()) return candidate;
  }
  return File(Platform.isWindows ? 'java.exe' : 'java');
}

/// Builds a child-process environment whose `PATH` is prefixed with
/// [binDir] and whose `JAVA_HOME` is the parent of [binDir]. Inherits
/// every other entry from [environment]. Use to make sure the spawned
/// installer's own forks see the same `java` selection as the parent.
Map<String, String> spawnEnvironment(
  Map<String, String> environment,
  String binDir,
) {
  final pathSep = Platform.isWindows ? ';' : ':';
  return {
    ...environment,
    'PATH': '$binDir$pathSep${environment['PATH'] ?? ''}',
    'JAVA_HOME': p.dirname(binDir),
  };
}
