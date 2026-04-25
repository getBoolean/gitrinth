import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';

/// Resolves the path to the official Minecraft Launcher executable. The
/// per-OS search paths can be overridden with the `GITRINTH_LAUNCHER` (a
/// single absolute path) and `GITRINTH_LAUNCHER_SEARCH_PATHS` (`;`/`:`
/// separated list) environment variables — useful for portable installs
/// and tests.
class MinecraftLauncherLocator {
  final Map<String, String> _environment;

  MinecraftLauncherLocator({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  /// First existing path among (`GITRINTH_LAUNCHER`, then
  /// `GITRINTH_LAUNCHER_SEARCH_PATHS`, then per-OS defaults). Throws
  /// [UserError] with an install hint if none resolve.
  File get launcherExecutable {
    final explicit = _environment['GITRINTH_LAUNCHER'];
    if (explicit != null && explicit.isNotEmpty) {
      final f = File(explicit);
      if (f.existsSync()) return f;
      throw UserError(
        'GITRINTH_LAUNCHER=$explicit does not exist; '
        'point it at the official Minecraft Launcher executable.',
      );
    }
    for (final candidate in _searchPaths()) {
      final f = File(candidate);
      if (f.existsSync()) return f;
    }
    throw const UserError(
      'official Minecraft Launcher not found in the usual install '
      'locations. Install it from minecraft.net or set GITRINTH_LAUNCHER '
      'to its executable path.',
    );
  }

  Iterable<String> _searchPaths() sync* {
    final overridePaths = _environment['GITRINTH_LAUNCHER_SEARCH_PATHS'];
    if (overridePaths != null) {
      // Empty string deliberately yields no paths so tests can force the
      // "not found" branch even when the host has a launcher installed.
      if (overridePaths.isEmpty) return;
      final sep = Platform.isWindows ? ';' : ':';
      yield* overridePaths.split(sep).where((s) => s.isNotEmpty);
      return;
    }
    if (Platform.isWindows) {
      final pf86 =
          _environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      final pf = _environment['ProgramFiles'] ?? r'C:\Program Files';
      final localAppData = _environment['LOCALAPPDATA'] ?? '';
      yield p.join(pf86, 'Minecraft Launcher', 'MinecraftLauncher.exe');
      yield p.join(pf, 'Minecraft Launcher', 'MinecraftLauncher.exe');
      if (localAppData.isNotEmpty) {
        yield p.join(
          localAppData,
          'Programs',
          'Minecraft Launcher',
          'MinecraftLauncher.exe',
        );
      }
    } else if (Platform.isMacOS) {
      yield '/Applications/Minecraft.app/Contents/MacOS/launcher';
    } else {
      yield '/usr/bin/minecraft-launcher';
      yield '/usr/local/bin/minecraft-launcher';
      yield '/var/lib/flatpak/exports/bin/com.mojang.Minecraft';
    }
  }
}
