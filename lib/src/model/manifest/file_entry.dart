import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'file_entry.mapper.dart';

/// Loose-file declaration from `mods.yaml`'s `files:` section.
/// Copies [sourcePath] into [destination], and includes it in mrpack
/// overrides on `gitrinth pack`.
/// When [preserve] is true, build skips overwriting an existing file.
@MappableClass()
class FileEntry with FileEntryMappable {
  /// Destination path relative to the build env root.
  final String destination;

  /// Source path relative to the `mods.yaml` directory.
  final String sourcePath;

  /// Client-side install state.
  final SideEnv client;

  /// Server-side install state.
  final SideEnv server;

  /// When true, build skips overwriting an existing [destination].
  final bool preserve;

  const FileEntry({
    required this.destination,
    required this.sourcePath,
    this.client = SideEnv.required,
    this.server = SideEnv.required,
    this.preserve = false,
  });
}
