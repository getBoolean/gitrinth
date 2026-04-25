import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';

/// Resolves the cache root directory:
///   1. `GITRINTH_CACHE` env var if set.
///   2. `<home>/.gitrinth_cache/` (USERPROFILE on Windows, HOME elsewhere).
///   3. Otherwise throws [UserError].
String resolveCacheRoot(Map<String, String> env) {
  final fromEnv = env['GITRINTH_CACHE'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return p.normalize(p.absolute(fromEnv));
  }
  final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  if (home == null || home.isEmpty) {
    throw const UserError(
      'Unable to locate a home directory for the gitrinth cache. '
      'Set GITRINTH_CACHE to an absolute path.',
    );
  }
  return p.normalize(p.join(home, '.gitrinth_cache'));
}
