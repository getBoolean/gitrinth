import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'file_entry.mapper.dart';

/// A loose-file declaration from `mods.yaml`'s `files:` section.
///
/// Files are copied verbatim from [sourcePath] (relative to the
/// `mods.yaml` directory) into the build env root at [destination].
/// They are also bundled into the `.mrpack` archive's overrides tree
/// when `gitrinth pack` runs.
///
/// [preserve] makes the file first-install-only: when true, the
/// build step skips overwriting an existing destination so user
/// edits survive subsequent rebuilds. Removing the entry from
/// `files:` still prunes it on the next build — preserve is not
/// sticky.
@MappableClass()
class FileEntry with FileEntryMappable {
  /// Destination path relative to the build env root, e.g.
  /// `config/sodium-options.json`. Must be relative and normalized
  /// (no `..`, no leading separator, no `./`, no `//`).
  final String destination;

  /// Source path relative to the `mods.yaml` directory.
  final String sourcePath;

  /// Install state on the client side. Only `required` and
  /// `unsupported` are supported for `files:` in v1.
  final SideEnv client;

  /// Install state on the server side. Only `required` and
  /// `unsupported` are supported for `files:` in v1.
  final SideEnv server;

  /// When true, build skips overwriting an existing file at
  /// [destination]. First-install-only behavior.
  final bool preserve;

  const FileEntry({
    required this.destination,
    required this.sourcePath,
    this.client = SideEnv.required,
    this.server = SideEnv.required,
    this.preserve = false,
  });
}
