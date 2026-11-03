# Loader capabilities

Loader identities are lowercase strings, such as `fabric`, `quilt`, or
`future-loader`. Existing manifests and locks retain their serialized names.
Unknown identities can be parsed and inspected; each operation then checks
its required capabilities.

Modrinth discovery reads loader names and supported project types from the
selected host. CurseForge discovery preserves numeric types and version names.
An unknown CurseForge type is identified as `curseforge-type-<number>`; it does
not imply a Modrinth alias, archive token, or installer.

Discovery does not provide executable behavior. Archive dependency keys also
require explicit metadata: a loader tag alone does not define its archive key
(for example, Fabric uses `fabric-loader` in a Modrinth archive).

## User mappings

Optional mappings live in `loaders.yaml` beside the resolved user config.
Use `--loader-descriptors <path>` on a metadata-consuming command to select
another file explicitly. A project-local file is never discovered automatically.

```yaml
version: 1
loaders:
  future-loader:
    role: mod
    modrinth:
      https://api.modrinth.com/v2: future-loader
    curseforge_type: 42
    archive:
      modrinth: future-loader
      curseforge: future
    version_source: catalog
```

The numeric type and archive keys above are examples. Supply the exact values
documented by the provider; names do not establish cross-provider aliases.

```console
gitrinth get --loader-descriptors C:/Users/me/.gitrinth/loaders.yaml
gitrinth pack --offline --loader-descriptors C:/Users/me/.gitrinth/loaders.yaml
```

Version 1 accepts these descriptor fields:

| Field                | Meaning                                                           |
|----------------------|-------------------------------------------------------------------|
| `role`               | `mod`, `plugin`, `shader`, or `vanilla`.                          |
| `modrinth`           | Provider base URL to exact filter/publish tag mappings.           |
| `curseforge_type`    | Positive numeric mod-loader filter type.                          |
| `curseforge_plugins` | Whether the provider supports this plugin platform.               |
| `archive`            | Optional `modrinth` dependency key and `curseforge` loader token. |
| `version_source`     | Trusted version strategy; defaults to `catalog`.                  |
| `installer_family`   | An installed, trusted installer strategy; omitted by default.     |
| `compatible_mods`    | Mod-loader identities a plugin server can also run.               |
| `server_launch_jar`  | Plain launcher JAR filename for an explicitly mapped recipe.      |
| `server_run_script`  | Whether the trusted runtime supplies server run scripts.          |

Unknown keys, built-in identity shadowing, duplicate provider aliases, and
numeric-type collisions fail validation. Descriptors cannot contain shell
commands, scripts, arbitrary URL templates, or expressions.

Version strategies are `fabric`, `forge`, `neoforge`, `quilt`, `paper`, `sponge`,
`buildtools`, and `catalog`. Installer families are `fabric`, `forge`, `quilt`,
`paper`, `sponge`, `buildtools`, and `vanilla`. Selecting a family is an explicit
user mapping to its installed protocol; it cannot implement a new protocol.
Existing built-in mappings include the required provider-specific recipe data.

## Offline and runtime behavior

Catalog snapshots are versioned and stored under
`<cache>/loader-catalogs/<provider>/<hostSegment>/catalog.json`.
Offline resolution uses the selected host's cached snapshot or explicit user
mappings and reuses concrete locked versions. A missing capability fails
without network access. Discovery refreshes missing identities; catalog-backed
`stable` / `latest` requests refresh available provider metadata online.

A metadata-only loader can resolve and publish using its provider tags. Packing
requires archive tokens. Build and launch require an installed runtime adapter;
a missing adapter fails before changing the output directory.

Quilt uses its official installer metadata, verifies the installer SHA512, and
accepts only the canonical Quilt Maven artifact URL. Its client/server recipes
use the official positional CLI arguments. Server installation verifies that
both `quilt-server-launch.jar` and `server.jar` exist. It does not accept the
Minecraft EULA or launch the server.

Protocol references: [Modrinth loader discovery](https://docs.modrinth.com/api/operations/loaderlist/),
[Modrinth archive format](https://support.modrinth.com/en/articles/8802351-modrinth-modpack-format-mrpack),
[CurseForge REST API](https://docs.curseforge.com/rest-api/), and
[Quilt installer CLI](https://github.com/QuiltMC/quilt-installer/blob/master/src/main/java/org/quiltmc/installer/CliInstaller.java).
