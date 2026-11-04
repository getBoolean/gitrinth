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

/// Legacy convenience mapping for built-in loader identities.
/// Service consumers use the operation's registry for user/provider mappings.
extension ModLoaderCfMapping on ModLoader {
  int get cfModLoaderType {
    final type = LoaderRegistry.builtins[this]?.curseforgeType;
    if (type == null) {
      throw StateError('Loader $name has no CurseForge modLoaderType mapping.');
    }
    return type;
  }
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
