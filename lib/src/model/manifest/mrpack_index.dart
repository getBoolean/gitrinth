import 'package:dart_mappable/dart_mappable.dart';

import 'mods_yaml.dart';

part 'mrpack_index.mapper.dart';

/// Top-level `modrinth.index.json` shape.
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

/// Maps [ModLoader] to the Modrinth dependency key.
String mrpackLoaderKey(ModLoader loader) {
  switch (loader) {
    case ModLoader.forge:
      return 'forge';
    case ModLoader.neoforge:
      return 'neoforge';
    case ModLoader.fabric:
      return 'fabric-loader';
    case ModLoader.vanilla:
      throw StateError(
        'mrpackLoaderKey called for vanilla; the dependencies block '
        'must omit the mod-loader entry under vanilla (gate on '
        'LoaderConfig.hasModRuntime).',
      );
  }
}

/// Maps per-side install state to a mrpack `env` map.
Map<String, String> mrpackEnvFor(SideEnv client, SideEnv server) => {
  'client': client.name,
  'server': server.name,
};
