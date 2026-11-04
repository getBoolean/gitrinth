import 'loader_id.dart';

enum LoaderRole { mod, plugin, shader, vanilla }

enum InstallerFamily {
  fabric,
  forge,
  quilt,
  paper,
  sponge,
  buildtools,
  vanilla,
}

enum VersionSourceFamily {
  fabric,
  forge,
  neoforge,
  quilt,
  paper,
  sponge,
  buildtools,
  catalog,
}

/// A recipe version is a path segment and a positional process argument.
bool isSafeRuntimeToken(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+\-]*$').hasMatch(value) && value != '..';

/// Provider release applicability, retained independently of its display name.
class LoaderCatalogVersion {
  final String name;
  final String? gameVersion;
  final bool latest;
  final bool recommended;
  const LoaderCatalogVersion({
    required this.name,
    this.gameVersion,
    this.latest = false,
    this.recommended = false,
  });
}

/// Immutable metadata. Discovery never grants an installer family.
class LoaderDescriptor {
  final LoaderId id;
  final LoaderRole role;
  final Map<String, String> modrinthTags;
  final int? curseforgeType;
  final bool curseforgePlugins;
  final String? modrinthArchiveKey;
  final String? curseforgeArchiveToken;
  final VersionSourceFamily? versionSource;
  final InstallerFamily? installer;
  final String? serverLaunchJar;
  final bool serverRunScript;
  final List<LoaderId> compatibleMods;
  final LoaderId? declaredId;
  final Map<String, LoaderId> variants;
  final List<String> versions;
  final List<LoaderCatalogVersion>? catalogVersions;
  final String? runtimeArtifact;

  const LoaderDescriptor._({
    required this.id,
    required this.role,
    this.modrinthTags = const {},
    this.curseforgeType,
    this.curseforgePlugins = false,
    this.modrinthArchiveKey,
    this.curseforgeArchiveToken,
    this.versionSource,
    this.installer,
    this.serverLaunchJar,
    this.serverRunScript = false,
    this.compatibleMods = const [],
    this.declaredId,
    this.variants = const {},
    this.versions = const [],
    this.catalogVersions,
    this.runtimeArtifact,
  });

  factory LoaderDescriptor({
    required LoaderId id,
    required LoaderRole role,
    Map<String, String> modrinthTags = const {},
    int? curseforgeType,
    bool curseforgePlugins = false,
    String? modrinthArchiveKey,
    String? curseforgeArchiveToken,
    VersionSourceFamily? versionSource,
    InstallerFamily? installer,
    String? serverLaunchJar,
    bool serverRunScript = false,
    List<LoaderId> compatibleMods = const [],
    LoaderId? declaredId,
    Map<String, LoaderId> variants = const {},
    List<String> versions = const [],
    List<LoaderCatalogVersion>? catalogVersions,
    String? runtimeArtifact,
  }) => LoaderDescriptor._(
    id: id,
    role: role,
    modrinthTags: Map.unmodifiable(modrinthTags),
    curseforgeType: curseforgeType,
    curseforgePlugins: curseforgePlugins,
    modrinthArchiveKey: modrinthArchiveKey,
    curseforgeArchiveToken: curseforgeArchiveToken,
    versionSource: versionSource,
    installer: installer,
    serverLaunchJar: serverLaunchJar,
    serverRunScript: serverRunScript,
    compatibleMods: List.unmodifiable(compatibleMods),
    declaredId: declaredId,
    variants: Map.unmodifiable(variants),
    versions: List.unmodifiable(versions),
    catalogVersions: catalogVersions == null
        ? null
        : List.unmodifiable(catalogVersions),
    runtimeArtifact: runtimeArtifact,
  );

  String? modrinthTag(String host) => modrinthTags[host] ?? modrinthTags['*'];
  bool get runsServerMods => compatibleMods.isNotEmpty;
  bool get canInstallClient =>
      role == LoaderRole.mod &&
      const {
        InstallerFamily.fabric,
        InstallerFamily.forge,
        InstallerFamily.quilt,
      }.contains(installer);
  bool get canInstallServer => switch (role) {
    LoaderRole.vanilla => installer == InstallerFamily.vanilla,
    LoaderRole.mod => switch (installer) {
      InstallerFamily.fabric => versionSource == VersionSourceFamily.fabric,
      InstallerFamily.forge => const {
        VersionSourceFamily.forge,
        VersionSourceFamily.neoforge,
      }.contains(versionSource),
      InstallerFamily.quilt => true,
      _ => false,
    },
    LoaderRole.plugin => const {
      InstallerFamily.paper,
      InstallerFamily.sponge,
      InstallerFamily.buildtools,
    }.contains(installer),
    LoaderRole.shader => false,
  };

  LoaderDescriptor withProvider({
    String? host,
    String? tag,
    List<String>? versions,
    List<LoaderCatalogVersion>? catalogVersions,
  }) => LoaderDescriptor(
    id: id,
    role: role,
    modrinthTags: {...modrinthTags, if (host != null && tag != null) host: tag},
    curseforgeType: curseforgeType,
    curseforgePlugins: curseforgePlugins,
    modrinthArchiveKey: modrinthArchiveKey,
    curseforgeArchiveToken: curseforgeArchiveToken,
    versionSource: versionSource,
    installer: installer,
    serverLaunchJar: serverLaunchJar,
    serverRunScript: serverRunScript,
    compatibleMods: compatibleMods,
    declaredId: declaredId,
    variants: variants,
    versions: versions ?? this.versions,
    catalogVersions: catalogVersions ?? this.catalogVersions,
    runtimeArtifact: runtimeArtifact,
  );
}

/// One immutable snapshot shared by model helpers and service consumers.
class LoaderRegistry {
  final Map<String, LoaderDescriptor> descriptors;
  const LoaderRegistry._(this.descriptors);
  factory LoaderRegistry(Iterable<LoaderDescriptor> descriptors) =>
      LoaderRegistry._(
        Map.unmodifiable({for (final d in descriptors) d.id.name: d}),
      );

  LoaderDescriptor? operator [](LoaderId? id) => descriptors[id?.name];
  LoaderRegistry merge(Iterable<LoaderDescriptor> additions) => LoaderRegistry([
    ...descriptors.values.where((d) => !additions.any((a) => a.id == d.id)),
    ...additions,
  ]);

  static const builtins = LoaderRegistry._({
    'vanilla': LoaderDescriptor._(
      id: LoaderId.vanilla,
      role: LoaderRole.vanilla,
      modrinthTags: {'*': 'vanilla'},
      installer: InstallerFamily.vanilla,
      serverLaunchJar: 'server.jar',
    ),
    'fabric': LoaderDescriptor._(
      id: LoaderId.fabric,
      role: LoaderRole.mod,
      modrinthTags: {'*': 'fabric'},
      curseforgeType: 4,
      modrinthArchiveKey: 'fabric-loader',
      curseforgeArchiveToken: 'fabric',
      versionSource: VersionSourceFamily.fabric,
      installer: InstallerFamily.fabric,
      serverLaunchJar: 'fabric-server-launch.jar',
    ),
    'forge': LoaderDescriptor._(
      id: LoaderId.forge,
      role: LoaderRole.mod,
      modrinthTags: {'*': 'forge'},
      curseforgeType: 1,
      modrinthArchiveKey: 'forge',
      curseforgeArchiveToken: 'forge',
      versionSource: VersionSourceFamily.forge,
      installer: InstallerFamily.forge,
      serverRunScript: true,
    ),
    'neoforge': LoaderDescriptor._(
      id: LoaderId.neoforge,
      role: LoaderRole.mod,
      modrinthTags: {'*': 'neoforge'},
      curseforgeType: 6,
      modrinthArchiveKey: 'neoforge',
      curseforgeArchiveToken: 'neoforge',
      versionSource: VersionSourceFamily.neoforge,
      installer: InstallerFamily.forge,
      serverRunScript: true,
    ),
    'quilt': LoaderDescriptor._(
      id: LoaderId.quilt,
      role: LoaderRole.mod,
      modrinthTags: {'*': 'quilt'},
      curseforgeType: 5,
      modrinthArchiveKey: 'quilt-loader',
      curseforgeArchiveToken: 'quilt',
      versionSource: VersionSourceFamily.quilt,
      installer: InstallerFamily.quilt,
      serverLaunchJar: 'quilt-server-launch.jar',
    ),
    'iris': LoaderDescriptor._(
      id: LoaderId.iris,
      role: LoaderRole.shader,
      modrinthTags: {'*': 'iris'},
    ),
    'optifine': LoaderDescriptor._(
      id: LoaderId.optifine,
      role: LoaderRole.shader,
      modrinthTags: {'*': 'optifine'},
    ),
    'canvas': LoaderDescriptor._(
      id: LoaderId.canvas,
      role: LoaderRole.shader,
      modrinthTags: {'*': 'canvas'},
    ),
    'paper': LoaderDescriptor._(
      id: LoaderId.paper,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'paper'},
      curseforgePlugins: true,
      versionSource: VersionSourceFamily.paper,
      installer: InstallerFamily.paper,
      runtimeArtifact: 'paper',
    ),
    'folia': LoaderDescriptor._(
      id: LoaderId.folia,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'folia'},
      versionSource: VersionSourceFamily.paper,
      installer: InstallerFamily.paper,
      runtimeArtifact: 'folia',
    ),
    'spigot': LoaderDescriptor._(
      id: LoaderId.spigot,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'spigot'},
      curseforgePlugins: true,
      versionSource: VersionSourceFamily.buildtools,
      installer: InstallerFamily.buildtools,
      runtimeArtifact: 'spigot',
    ),
    'bukkit': LoaderDescriptor._(
      id: LoaderId.bukkit,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'bukkit'},
      curseforgePlugins: true,
      versionSource: VersionSourceFamily.buildtools,
      installer: InstallerFamily.buildtools,
      runtimeArtifact: 'craftbukkit',
    ),
    'sponge': LoaderDescriptor._(
      id: LoaderId.sponge,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'sponge'},
      variants: {
        'forge': LoaderId.spongeforge,
        'neoforge': LoaderId.spongeneo,
        'vanilla': LoaderId.spongevanilla,
        'fabric': LoaderId.spongevanilla,
        'quilt': LoaderId.spongevanilla,
      },
    ),
    'spongeforge': LoaderDescriptor._(
      id: LoaderId.spongeforge,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'sponge'},
      versionSource: VersionSourceFamily.sponge,
      installer: InstallerFamily.sponge,
      declaredId: LoaderId.sponge,
      compatibleMods: [LoaderId.forge, LoaderId.neoforge],
      runtimeArtifact: 'spongeforge',
    ),
    'spongeneo': LoaderDescriptor._(
      id: LoaderId.spongeneo,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'sponge'},
      versionSource: VersionSourceFamily.sponge,
      installer: InstallerFamily.sponge,
      declaredId: LoaderId.sponge,
      compatibleMods: [LoaderId.forge, LoaderId.neoforge],
      runtimeArtifact: 'spongeneo',
    ),
    'spongevanilla': LoaderDescriptor._(
      id: LoaderId.spongevanilla,
      role: LoaderRole.plugin,
      modrinthTags: {'*': 'sponge'},
      versionSource: VersionSourceFamily.sponge,
      installer: InstallerFamily.sponge,
      declaredId: LoaderId.sponge,
      runtimeArtifact: 'spongevanilla',
    ),
  });
}
