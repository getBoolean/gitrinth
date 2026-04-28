# gitrinth

Gitrinth is CLI for creating Modrinth modpacks. Instead of managing JARS for
both client and server distributions, Gitrinth creates a YAML file which
elegantly manages both and can be versioned with Git. You can add mods with
the CLI or manually edit `mods.yaml`; it is designed to be intuitive and
easy to read.

Gitrinth resolves the mod list to a lockfile, which locks the versions
until you explicitly upgrade. You can launch a local server and client
for testing, assemble it for manual distribution, and export it to a
Modrinth modpack.

## Usage

Getting started with the CLI:

```sh
# Create a modpack with the template files.
# The modpack name must be a valid Modrinth project slug (3-64 chars, URL friendly characters only)
gitrinth create my_pack
cd my_pack

# Add mods by Modrinth slug or by a direct Modrinth URL
gitrinth add sodium

# Resolve all mods and their dependencies, creates `mods.lock` and fills the cache.
gitrinth get

# Assemble the client and server distributions under `build/` for testing or manual distribution. Ensure the correct mod versions are downloaded
gitrinth build
```

Test it locally — boot the server, or open the Minecraft Launcher pointed
at the built client:

```sh
gitrinth launch server --accept-eula
gitrinth launch client
```

Both subcommands run `gitrinth build` for their side first; pass
`--no-build` to skip when the build tree is already current. `launch
server` needs `--accept-eula` once to write `eula=true` to
`build/server/eula.txt` (you agree to the [Mojang EULA](https://aka.ms/MinecraftEULA)).
A JDK matching the pack's `mc-version` is auto-downloaded into the
cache if one isn't already on the system.

Common commands:

| Command                             | Purpose                                                                       |
|-------------------------------------|-------------------------------------------------------------------------------|
| `gitrinth create <slug>`            | Scaffold a new modpack.                                                       |
| `gitrinth add <slug>`               | Add an entry and re-resolve.                                                  |
| `gitrinth remove <slug>`            | Remove an entry and re-resolve.                                               |
| `gitrinth get`                      | Resolve `mods.yaml`, write `mods.lock`, fill cache.                           |
| `gitrinth upgrade`                  | Re-resolve to the newest in-range version per entry.                          |
| `gitrinth upgrade --major-versions` | Upgrade to newest version, even when version number implies breaking changes. |
| `gitrinth downgrade`                | Re-resolve to the oldest in-range version per entry.                          |
| `gitrinth outdated`                 | Report locked entries that are behind newer compatible versions.              |
| `gitrinth deps`                     | Print the resolved dependency tree.                                           |
| `gitrinth migrate mc <version>`     | Re-target the pack to a new Minecraft version and re-resolve every entry.     |
| `gitrinth migrate loader <loader>`  | Switch the pack's mod loader and re-resolve every entry.                      |
| `gitrinth build`                    | Assemble modpack distributions for client and server.                         |
| `gitrinth pack`                     | Produce `.mrpack` artifacts under `build/`.                                   |
| `gitrinth launch server`            | Build and start the server.                                                   |
| `gitrinth launch client`            | Build and open the Minecraft Launcher.                                        |
| `gitrinth clean`                    | Delete `mods.lock` and `build/`.                                              |

Run `gitrinth <command> --help` for options. Every mutating command accepts
`--offline` to use only what's already in the cache.

### Advanced usage

* [CLI Reference](./docs/cli.md): All CLI commands and options
* [mods.yaml Reference](./docs/mods-yaml.md): Full schema of the modpack definition file

#### Loader support

Fabric, Forge, and NeoForge are the supported mod loaders. All shader
loaders are supported: Iris, Optifine, Canvas, and Vanilla.

```yaml
mc-version: 1.21.1
loader:
  # forge | fabric | neoforge. The version tag is optional; `latest` /
  # `stable` track the newest / newest-stable release.
  mods: neoforge:stable

  # iris | optifine | canvas | vanilla. Required when `shaders:` has
  # entries.
  shaders: iris
```

#### Plugin support

`loader.plugins` accepts `bukkit`, `folia`, `paper`, `spigot`, and
`sponge`, optionally with a docker-style version tag such as
`paper:187` or `sponge:stable`. Plugin entries go under a `plugins:`
section with the same syntax as `mods:`. `loader.mods` is **optional**
— omit it for plugin-only or pure-vanilla packs.

Pure plugin servers (paper / folia / bukkit / spigot, and `sponge`
when `loader.mods` is `fabric` or omitted) force every `mods:` entry
to `server: unsupported` — client modpack ships them, server jar
doesn't. `sponge` resolves at lock time to the concrete distribution
based on `loader.mods`: `forge` → SpongeForge (server-side Forge mods
load alongside plugins), `neoforge` → SpongeNeo, `fabric` or omitted
→ SpongeVanilla.

```yaml
# Plugin-only server (no mod runtime).
loader:
  plugins: paper
mc-version: 1.21.1
plugins:
  luckperms: ^5.5.17
```

```yaml
# Sponge — resolves to SpongeForge; mods alongside plugins.
loader:
  mods: forge
  plugins: sponge
mc-version: 1.21.1
mods:
  create: ^6.0.10+mc1.21.1
plugins:
  chunky: ^1.4.40
```

`build server` fetches the server jar from PaperMC / SpongePowered, or
runs SpigotMC `BuildTools.jar` locally for spigot/bukkit (needs `git`
and Java; cached after first build). `stable` / `latest` plugin tags
are resolved into concrete versions in `mods.lock`; Bukkit/Spigot
concrete tags are BuildTools Jenkins build numbers. Full spec:
[Plugin loaders](./docs/mods-yaml.md#plugin-loaders).

#### Adding mods by semantic version constraints

Add mods by their semantic version, which is resolved from the version's filename.

```yaml
mods:
  # This resolves to version 3.0.9-mc1.21.1 or later releases
  # matching the semantic version, Minecraft version, and loader.
  appleskin: ^3.0.9
```

Later released versions such as `3.1.0` will match this constraint too, but not lower versions such as `3.0.8`. The lockfile will enforce `3.0.9` is used until you explicitly upgrade using `gitrinth upgrade`.

Versions that bump the major version (e.g. `4.0.0`) will not be upgraded by default, as they may contain breaking changes. Use `gitrinth upgrade --major-versions <slug>` to allow major version bumps when upgrading.

#### Pinning to a specific version

Pin to an exact version by removing the caret (`^`). This is
mostly useful for mods that don't follow semantic versioning.

```yaml
mods:
  # This resolves to exactly version 3.0.9-mc1.21.1 and no other.
  appleskin: 3.0.9

  # You can also use the exact version name
  appleskin: 3.0.9-mc1.21.1
```

#### Long form syntax

Specify additional metadata for a mod to control which version is used and how it
is distributed.

```yaml
mods:
  appleskin:
    version: ^3.0.9
    # Allow beta releases when no stable build matches the constraint.
    channel: beta
    # Search additional Minecraft versions for compatible versions.
    # Useful if a mod supports a new release but is not declared as compatible yet.
    accepts-mc:
      - 1.21.1
    # Override the mod's declared client/server compatibility
    client: required
    server: unsupported
```

| Field        | Description                                                                                                                                                   |
|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `version`    | Mod-version constraint — exact pin, blank, or caret range. Same forms as the short syntax.                                                                    |
| `channel`    | Stability floor: `release` (only stable), `beta` (release + beta), or `alpha` (everything). Defaults to `alpha`.                                              |
| `accepts-mc` | Extra Minecraft versions to widen the search for this entry only. Scalar or list. Doesn't change the pack's `mc-version`.                                     |
| `client`     | Install state on the client. `required` (default), `optional`, or `unsupported`. `optional` exposes a launcher toggle.                                        |
| `server`     | Install state on the server. Same vocabulary as `client`. Both sides cannot be `unsupported`.                                                                 |
| `hosted`     | Base URL of a Modrinth-compatible server to fetch the mod from. Mutually exclusive with `url` and `path` (TODO: not implement yet)                            |
| `url`        | Direct `.jar` download URL. Mutually exclusive with `hosted` and `path`. Makes the modpack unpublishable to Modrinth without author permission.               |
| `path`       | Local `.jar` path relative to `mods.yaml`. Mutually exclusive with `hosted` and `url`. Makes the modpack unpublishable to Modrinth without author permission. |

See the [`mods.yaml` reference](./docs/mods-yaml.md#long-form) for the full schema.

#### Migrating to a new Minecraft version or loader

`gitrinth migrate` re-targets the pack and re-resolves every mod in one step.

```sh
# Dry run first to preview the changes without writing.
gitrinth migrate mc 1.21.4 --dry-run
# Move the pack to the target Minecraft version.
gitrinth migrate mc 1.21.4

# Upgrade or switch to a different mod loader (optionally with a tag).
gitrinth migrate loader fabric
gitrinth migrate loader neoforge:21.1.50
```

Migrating upgrades every mod/dependency to the newest compatible version
for the new target Minecraft version/loader. If a compatible version is not found, its `version:` field is
rewritten to `gitrinth:not-found`. A later `migrate` (or
`upgrade --major-versions`) that finds a compatible version rewrites the
marker back to a fresh caret version.

```yaml
mods:
  abandoned_mod: gitrinth:not-found
```

If a mod (or one of its required transitives) has no
version satisfying the new target, `migrate` marks every
mod involved as `gitrinth:disabled-by-conflict`.
A later `migrate` (or `upgrade --major-versions`) will
attempt to resolve the conflict.

```yaml
mods:
  conflicting_mod_a: gitrinth:disabled-by-conflict
  conflicting_mod_b: gitrinth:disabled-by-conflict
```

#### Project Overrides

Bypass a mod's declared incompatibilities or version constraints
using project overrides on the dependency. This is an advanced feature that may cause instability if used incorrectly, so use with caution.

```yaml
mods:
  create: ^6.0.0

project_overrides:
  # It declares Create is incompatible with itself.
  # Put in overrides to bypass it
  create_incompatible: 1.1.0
```

## Environment variables

Every variable below is read by `gitrinth` and is optional unless
noted. Test fixtures use the `*_URL` overrides to point loader /
metadata fetches at a local fake server.

### Locations & credentials

| Variable                | Used by       | Purpose                                                                                                                                                             |
|-------------------------|---------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `GITRINTH_CACHE`        | every command | Override the cache root. Defaults to `<home>/.gitrinth/cache`.                                                                                                      |
| `GITRINTH_CONFIG`       | every command | Override the user config file path. `--config` wins.                                                                                                                |
| `GITRINTH_MODRINTH_URL` | every command | Override the default Modrinth API base URL. Used to point at a self-hosted labrinth instance for the default host.                                                  |
| `GITRINTH_TOKEN`        | every command | Override the stored Modrinth PAT for the *default* host. Sent bare (no `Bearer` prefix). Other hosts always use the token stored via `gitrinth modrinth token add`. |
| `HOME` / `USERPROFILE`  | every command | Resolves the default cache root and user config path. `USERPROFILE` is consulted on Windows; `HOME` everywhere else.                                                |

### Java runtime

| Variable                     | Used by            | Purpose                                                                                                                                                                |
|------------------------------|--------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `JAVA_HOME`                  | `launch` / `build` | Honored by the Java resolver if its major version matches the JDK required for the pack's `mc-version`. Stale system-wide values fall through to the auto-managed JDK. |
| `GITRINTH_JAVA_METADATA_URL` | `launch` / `build` | Override the Adoptium feature-releases URL template used to fetch the auto-managed JDK.                                                                                |

### Loader metadata overrides

Useful for offline / mirrored / fake-test builds. All default to the
canonical upstream URLs.

| Variable                                 | Replaces                                                                  |
|------------------------------------------|---------------------------------------------------------------------------|
| `GITRINTH_FABRIC_META_URL`               | `https://meta.fabricmc.net/v2/versions/loader`                            |
| `GITRINTH_FORGE_PROMOTIONS_URL`          | `https://files.minecraftforge.net/.../promotions_slim.json`               |
| `GITRINTH_FORGE_VERSIONS_URL`            | Forge `maven-metadata.json` for concrete-tag validation.                  |
| `GITRINTH_FORGE_INSTALLER_URL`           | Forge installer-jar URL template (`{mc}` / `{v}` placeholders).           |
| `GITRINTH_NEOFORGE_VERSIONS_URL`         | Modern NeoForge versions endpoint (MC ≥ 1.20.2).                          |
| `GITRINTH_NEOFORGE_LEGACY_VERSIONS_URL`  | Legacy NeoForge versions endpoint (MC 1.20.1).                            |
| `GITRINTH_NEOFORGE_INSTALLER_URL`        | Modern NeoForge installer-jar URL template (`{v}` placeholder).           |
| `GITRINTH_NEOFORGE_LEGACY_INSTALLER_URL` | Legacy NeoForge installer-jar URL template (`{mc}` / `{v}` placeholders). |

### Minecraft launcher discovery (`launch client`)

| Variable                         | Purpose                                                                             |
|----------------------------------|-------------------------------------------------------------------------------------|
| `GITRINTH_LAUNCHER`              | Absolute path to the Minecraft Launcher executable. Bypasses the per-OS search.     |
| `GITRINTH_LAUNCHER_SEARCH_PATHS` | `;`-separated (Windows) or `:`-separated paths searched before the per-OS defaults. |

### Output / network

| Variable                     | Purpose                                                                                 |
|------------------------------|-----------------------------------------------------------------------------------------|
| `NO_COLOR`                   | Disable ANSI colour. `--color` overrides; `--no-color` matches.                         |
| `HTTPS_PROXY` / `HTTP_PROXY` | Standard proxy variables, honoured by every HTTP request through the shared Dio client. |

## Contributing

### Regenerating templates and generated code

After changing any file under `assets/template/`, Dart Mappable models, or Retrofit HTTP interfaces, regenerate the constants in `lib/src/asset_strings.g.dart` and commit them alongside the asset change:

```sh
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

## References

* [Modrinth API documentation](https://docs.modrinth.com/api-spec/)
* [Semantic versioning](https://semver.org/)
* Heavily inspired by [Dart Pub](https://dart.dev/tools/pub)
* [packwiz](https://github.com/packwiz/packwiz)
* [mrpack-install](https://github.com/nothub/mrpack-install)
