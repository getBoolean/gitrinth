import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'mrpack_index.mapper.dart';

/// Top-level shape of `modrinth.index.json` inside a `.mrpack` archive.
/// Field names match the Modrinth pack spec verbatim — they're emitted
/// as-is into the JSON.
@MappableClass()
class MrpackIndex with MrpackIndexMappable {
  final String game;
  final int formatVersion;
  final String versionId;
  final String name;
  final String summary;
  final List<MrpackFile> files;
  final Map<String, String> dependencies;

  const MrpackIndex({
    this.game = 'minecraft',
    this.formatVersion = 1,
    required this.versionId,
    required this.name,
    required this.summary,
    required this.files,
    required this.dependencies,
  });
}

@MappableClass()
class MrpackFile with MrpackFileMappable {
  final String path;
  final Map<String, String> hashes;
  final Map<String, String> env;
  final List<String> downloads;
  final int fileSize;

  const MrpackFile({
    required this.path,
    required this.hashes,
    required this.env,
    required this.downloads,
    required this.fileSize,
  });
}

/// Maps the in-tree `Loader` enum to the dependency key the Modrinth
/// pack format expects.
String mrpackLoaderKey(Loader loader) {
  switch (loader) {
    case Loader.forge:
      return 'forge';
    case Loader.neoforge:
      return 'neoforge';
    case Loader.fabric:
      return 'fabric-loader';
  }
}

/// Maps an [Environment] to the per-file `env` map used by
/// `modrinth.index.json`. Each side is `"required"`, `"optional"`, or
/// `"unsupported"`. When [optional] is true, sides that would have been
/// `"required"` become `"optional"` so the launcher presents a
/// user-facing toggle. `"unsupported"` sides are preserved (env-split
/// correctness — a server-only mod can't be optional on the client).
Map<String, String> mrpackEnv(Environment env, {bool optional = false}) {
  final included = optional ? 'optional' : 'required';
  switch (env) {
    case Environment.both:
      return {'client': included, 'server': included};
    case Environment.client:
      return {'client': included, 'server': 'unsupported'};
    case Environment.server:
      return {'client': 'unsupported', 'server': included};
  }
}
