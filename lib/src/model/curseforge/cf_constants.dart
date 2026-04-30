import '../manifest/mods_yaml.dart';

/// CurseForge `gameId` for Minecraft.
const int kCurseForgeGameIdMinecraft = 432;

/// Maps a [Section] to its CurseForge `classId`.
///
/// IDs come from `GET /v1/categories?gameId=432`. Confirm the values
/// against the live category list when the constants drift — CF's
/// taxonomy is occasionally renamed.
extension SectionCfMapping on Section {
  int get cfClassId => switch (this) {
    Section.mods => 6,
    Section.resourcePacks => 12,
    Section.dataPacks => 6945,
    Section.shaders => 6552,
    Section.plugins => 5,
  };
}

/// Maps a [ModLoader] to its CurseForge `modLoaderType` enum value.
///
/// Reference: CurseForge ModLoaderType — 1=Forge, 4=Fabric, 5=Quilt,
/// 6=NeoForge. The Quilt mapping is documented for completeness even
/// though [ModLoader] does not currently have a `quilt` variant; if one
/// is added later, return `5` here to keep the wire-format mapping
/// centralised.
extension ModLoaderCfMapping on ModLoader {
  int get cfModLoaderType => switch (this) {
    ModLoader.forge => 1,
    ModLoader.fabric => 4,
    ModLoader.neoforge => 6,
    ModLoader.vanilla => throw StateError(
      'ModLoader.vanilla has no CurseForge modLoaderType — callers '
      'should not pass a mod-loader filter when the pack does not '
      'declare a mod runtime.',
    ),
  };
}

/// Returns the set of CurseForge `releaseType` values admitted by a
/// channel floor. Mirrors `allowedVersionTypes(Channel)` so the two
/// helpers stay in sync structurally.
///
/// CurseForge releaseType: 1=release, 2=beta, 3=alpha. The floor is
/// inclusive — `Channel.beta` admits release+beta, `Channel.alpha`
/// admits everything.
Set<int> cfReleaseTypesFor(Channel channel) => switch (channel) {
  Channel.release => const {1},
  Channel.beta => const {1, 2},
  Channel.alpha => const {1, 2, 3},
};

/// True when [loader] is a CurseForge-eligible plugin loader. Delegates
/// to [sectionAllowsCurseforge] so the source-eligibility rule has a
/// single source of truth.
bool pluginLoaderEligibleForCurseforge(PluginLoader loader) =>
    sectionAllowsCurseforge(Section.plugins, loader);
