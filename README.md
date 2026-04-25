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

Fabric, Forge, and NeoForge are the only supported mod loaders. Specify which loader and version you want in `mods.yaml`.

All shader loaders are supported: Iris, Optifine, Canvas, and Vanilla.

Plugin support is not yet implemented.

```yaml
mc-version: 1.21.1
loader:
  # Choose from forge, fabric, or neoforge
  # For the version, specify an exact version or use
  # "latest"/"stable" for the latest/latest stable release.
  mods: neoforge:stable

  # Choose a shader loader (Use iris for Iris/Sodium)
  shaders: iris

  # Plugin support is coming soon
  # plugins: sponge
```

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

## Contributing

### Regenerating templates and generated code

After changing any file under `assets/template/`, Dart Mappable models, or Retrofit HTTP interfaces, regenerate the constants in `lib/src/asset_strings.g.dart` and commit them alongside the asset change:

```sh
dart pub get
dart run build_runner build --delete-conflicting-outputs
```
