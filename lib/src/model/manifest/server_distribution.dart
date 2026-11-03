import 'package:path/path.dart' as p;

import '../loader/loader_id.dart';

const serverDistributionManifestName = 'gitrinth-server-distribution.json';
const serverDistributionArtifactType = 'gitrinth-server-distribution';

bool isSafeServerDistributionPath(String path) =>
    path.isNotEmpty &&
    !path.contains('\\') &&
    !p.posix.isAbsolute(path) &&
    !p.windows.isAbsolute(path) &&
    !path.contains(':') &&
    p.posix.normalize(path) == path &&
    !p.posix
        .split(path)
        .any((part) => part == '.' || part == '..' || part.isEmpty);

bool isPrivateServerDistributionPath(String path) {
  final parts = p.posix.split(path).map((part) => part.toLowerCase()).toList();
  const directories = {
    '.git',
    '.gitrinth',
    '.cache',
    '.ssh',
    'cache',
    'caches',
    'logs',
    'runtimes',
    'launchers',
    'assets',
    'libraries',
    'versions',
  };
  if (parts.any(directories.contains)) return true;
  final name = parts.last;
  return name == serverDistributionManifestName ||
      name == 'manifest.json' ||
      name == 'modrinth.index.json' ||
      name == 'eula.txt' ||
      name == '.env' ||
      name.startsWith('.env.') ||
      const {
        'launcher_accounts.json',
        'launcher_profiles.json',
        'usercache.json',
        'usernamecache.json',
      }.contains(name) ||
      RegExp(
        r'^(credentials?|secrets?|tokens?)(\.(json|ya?ml|toml|ini|conf|txt|properties|pem|key))?$',
      ).hasMatch(name);
}

class ServerDistributionFile {
  final String path;
  final String sha256;

  factory ServerDistributionFile({
    required String path,
    required String sha256,
  }) {
    if (!isSafeServerDistributionPath(path) ||
        isPrivateServerDistributionPath(path)) {
      throw FormatException(
        'Unsafe or private server distribution path: $path',
      );
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw FormatException(
        'Invalid SHA256 for server distribution path $path.',
      );
    }
    return ServerDistributionFile._(path, sha256);
  }
  const ServerDistributionFile._(this.path, this.sha256);
  Map<String, dynamic> toMap() => {'path': path, 'sha256': sha256};
}

/// Identifies a physical server distribution and binds its payload inventory.
class ServerDistributionManifest {
  final String slug;
  final String version;
  final String minecraft;
  final String loaderId;
  final String? loaderVersion;
  final String? pluginLoaderId;
  final String? pluginLoaderVersion;
  final List<ServerDistributionFile> files;

  factory ServerDistributionManifest({
    required String slug,
    required String version,
    required String minecraft,
    required String loaderId,
    required String? loaderVersion,
    String? pluginLoaderId,
    String? pluginLoaderVersion,
    required List<ServerDistributionFile> files,
  }) => ServerDistributionManifest.fromMap({
    'formatVersion': 1,
    'artifactType': serverDistributionArtifactType,
    'slug': slug,
    'version': version,
    'minecraft': minecraft,
    'loader': {
      'id': loaderId,
      'version': loaderVersion,
      if (pluginLoaderId != null)
        'plugins': {'id': pluginLoaderId, 'version': pluginLoaderVersion},
    },
    'runtimeBundled': false,
    'files': files.map((file) => file.toMap()).toList(),
  });

  const ServerDistributionManifest._({
    required this.slug,
    required this.version,
    required this.minecraft,
    required this.loaderId,
    required this.loaderVersion,
    required this.pluginLoaderId,
    required this.pluginLoaderVersion,
    required this.files,
  });

  factory ServerDistributionManifest.fromMap(Map<String, dynamic> data) {
    const keys = {
      'formatVersion',
      'artifactType',
      'slug',
      'version',
      'minecraft',
      'loader',
      'runtimeBundled',
      'files',
    };
    if (data.keys.any((key) => !keys.contains(key)) ||
        data['formatVersion'] != 1 ||
        data['artifactType'] != serverDistributionArtifactType ||
        data['runtimeBundled'] != false) {
      throw const FormatException('Unsupported server distribution manifest.');
    }
    String text(Map map, String key) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException(
          'Server distribution $key must be a nonempty string.',
        );
      }
      return value;
    }

    final loader = data['loader'];
    final rawFiles = data['files'];
    if (loader is! Map ||
        loader.keys.any(
          (key) => key != 'id' && key != 'version' && key != 'plugins',
        ) ||
        (loader['version'] != null && loader['version'] is! String) ||
        rawFiles is! List ||
        rawFiles.isEmpty) {
      throw const FormatException(
        'Server distribution requires loader metadata and physical files.',
      );
    }
    final plugins = loader['plugins'];
    if (plugins != null &&
        (plugins is! Map ||
            plugins.keys.any((key) => key != 'id' && key != 'version') ||
            (plugins['version'] != null && plugins['version'] is! String))) {
      throw const FormatException(
        'Invalid server distribution plugin loader metadata.',
      );
    }
    final paths = <String>{};
    final files = <ServerDistributionFile>[];
    for (final raw in rawFiles) {
      if (raw is! Map ||
          raw.keys.any((key) => key != 'path' && key != 'sha256')) {
        throw const FormatException(
          'Invalid server distribution file inventory.',
        );
      }
      final path = text(raw, 'path');
      if (!paths.add(path.toLowerCase())) {
        throw FormatException('Duplicate server distribution path: $path');
      }
      files.add(
        ServerDistributionFile(path: path, sha256: text(raw, 'sha256')),
      );
    }
    return ServerDistributionManifest._(
      slug: text(data, 'slug'),
      version: text(data, 'version'),
      minecraft: text(data, 'minecraft'),
      loaderId: LoaderId(text(loader, 'id')).name,
      loaderVersion: loader['version'] as String?,
      pluginLoaderId: plugins is Map
          ? LoaderId(text(plugins, 'id')).name
          : null,
      pluginLoaderVersion: plugins is Map
          ? plugins['version'] as String?
          : null,
      files: List.unmodifiable(files),
    );
  }

  Map<String, dynamic> toMap() => {
    'formatVersion': 1,
    'artifactType': serverDistributionArtifactType,
    'slug': slug,
    'version': version,
    'minecraft': minecraft,
    'loader': {
      'id': loaderId,
      'version': loaderVersion,
      if (pluginLoaderId != null)
        'plugins': {'id': pluginLoaderId, 'version': pluginLoaderVersion},
    },
    'runtimeBundled': false,
    'files': files.map((file) => file.toMap()).toList(),
  };
}
