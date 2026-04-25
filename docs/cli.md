# The `gitrinth` CLI

**gitrinth** manages a modpack declared in [`mods.yaml`](mods-yaml.md).
It resolves entries against [Modrinth](https://modrinth.com) (or the
sources declared in the file), locks resolved versions to `mods.lock`,
and assembles client and server distributions.

Planned but not-yet-implemented surface — additional commands, global
options, exit codes, and features — is tracked in [`todo.md`](todo.md).

## Synopsis

```text
gitrinth [<global-options>] <command> [<command-options>] [<arguments>]
gitrinth --help
gitrinth --version
```

Commands operate on `mods.yaml` in the current directory by default.
Use [`--directory`](#global-options) to target a different modpack.

## Global options

| Option                     | Description                                                     |
|----------------------------|-----------------------------------------------------------------|
| `-h`, `--help`             | Print usage. After a command name, prints that command's usage. |
| `--version`                | Print the `gitrinth` version and exit.                          |
| `-v`, `--verbose`          | Emit progress and resolution detail.                            |
| `-C`, `--directory <path>` | Run as if invoked from `<path>`.                                |

## Commands

### Dependencies

| Command               | Purpose                                                      |
|-----------------------|--------------------------------------------------------------|
| [`get`](#get)         | Resolve entries, write `mods.lock`, download into the cache. |
| [`upgrade`](#upgrade) | Re-resolve to the newest version allowed by each constraint. |
| [`add`](#add)         | Add an entry to a section.                                   |
| [`remove`](#remove)   | Remove an entry.                                             |
| [`pin`](#pin)         | Freeze an entry to its currently-locked version.             |
| [`unpin`](#unpin)     | Restore a caret on a pinned entry.                           |

### Cache

| Command           | Purpose                                    |
|-------------------|--------------------------------------------|
| [`cache`](#cache) | Inspect, clean, or repair the local cache. |

### Modpack-specific

| Command             | Purpose                                                       |
|---------------------|---------------------------------------------------------------|
| [`create`](#create) | Scaffold a new modpack directory.                             |
| [`build`](#build)   | Assemble the client and/or server distribution into `build/`. |
| [`clean`](#clean)   | Delete generated files: `build/` and `mods.lock`.             |
| [`pack`](#pack)     | Produce a Modrinth `.mrpack` artifact.                        |
| [`launch`](#launch) | Build (when needed) and start the server to test the modpack. |

### Shell integration

| Command                     | Purpose                                             |
|-----------------------------|-----------------------------------------------------|
| [`completion`](#completion) | Emit a shell-completion script for the given shell. |

## Console output

Mutating commands emit a resolution header (e.g. `Resolving 12 mods, 2
resource packs, 1 shader...`), followed by per-entry lines prefixed
with `+` for additions, `~` for updates, and `-` for removals. They
finish with a summary line such as `Locked 15 entries to mods.lock.`
or `Updated 2 entries in mods.lock.`. `--verbose` (`-v`) adds resolver
detail.

## Offline mode

[`get`](#get), [`upgrade`](#upgrade), [`add`](#add), [`remove`](#remove),
[`build`](#build), [`pack`](#pack), and [`launch`](#launch) accept
`--offline`. When set,
the resolver narrows its candidate set to versions already present in
the local cache and skips the Modrinth game-version check; for
[`loader.mods`](mods-yaml.md#loader) tags `:stable` / `:latest`, the
concrete version recorded in `mods.lock` is reused. A slug that has
never been resolved on this system cannot be resolved offline.
[`upgrade`](#upgrade) and [`add`](#add) print a warning when run with
`--offline` to remind you the result may not include the latest
available versions. [`create`](#create) also accepts `--offline`,
where it skips the slug-availability round-trip; that's the only
network call `create` makes.

## Command details

### `get`

Resolve every entry in `mods.yaml`, apply
[`overrides`](mods-yaml.md#overrides), write `mods.lock`, and download
artifacts into the cache. Does not upgrade entries already locked to a
satisfying version — use [`upgrade`](#upgrade) for that.

```text
gitrinth get [--dry-run] [--enforce-lockfile] [--offline]
```

| Option               | Description                                                                                            |
|----------------------|--------------------------------------------------------------------------------------------------------|
| `--dry-run`          | Resolve without writing. Exits non-zero if the lockfile would change.                                  |
| `--enforce-lockfile` | Fail if `mods.lock` would change. Also forbids missing lockfile entries.                               |
| `--offline`          | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache. |

### `upgrade`

Re-resolve to the **newest** version allowed by each constraint,
updating `mods.lock`. Leaves `mods.yaml` untouched unless
`--major-versions` or `--tighten` is passed. Pass slugs to upgrade
only those entries.

```text
gitrinth upgrade [<slug>...] [--major-versions] [--tighten]
                 [--unlock-transitive] [--dry-run] [--offline]
```

| Option                | Description                                                                                                                                                  |
|-----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `--major-versions`    | Ignore caret boundaries and pick the absolute newest version. Rewrites the constraint in `mods.yaml`.                                                        |
| `--tighten`           | After resolving, raise each caret-bound entry's lower bound in `mods.yaml` to match the resolved version.                                                    |
| `--unlock-transitive` | Also re-resolve every entry transitively reachable from the named targets via `mods.lock` dependency edges.                                                  |
| `--dry-run`           | Print changes without writing.                                                                                                                               |
| `--offline`           | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache.                                                       |

`--major-versions` only rewrites entries whose resolved version isn't
already permitted by the existing constraint. `--tighten` covers the
other case: in-major bumps where the constraint already allowed the
new version but its lower bound is now stale. Combine the two when
both behaviors are wanted.

Without `--unlock-transitive`, only the named entries are unpinned;
their transitive dependencies stay at the versions already recorded
in `mods.lock`. With it, `gitrinth` walks the closure of dependency
edges in `mods.lock` and unpins every reached entry, so the resolver
picks the newest version each constraint admits.

`--unlock-transitive` is a no-op without explicit `<slug>` arguments
(the default already re-resolves everything). When the targeted
entries' `mods.lock` records have no `dependencies:` lines (legacy
lock written before this MVP item), the command warns and falls back
to unlocking only the named entries; the next `gitrinth get` /
`gitrinth upgrade` repopulates the edges.

### `add`

Add an entry to [`mods`](mods-yaml.md#mods),
[`resource_packs`](mods-yaml.md#resource_packs),
[`data_packs`](mods-yaml.md#data_packs),
[`shaders`](mods-yaml.md#shaders), or
[`plugins`](mods-yaml.md#plugins), then re-resolve.

```text
gitrinth add <slug>[@<constraint>] [--env <client|server|both>]
            [--url <url> | --path <path>]
            [--type <mod|resourcepack|datapack|shader>]
            [--accepts-mc <mc-version>]...
            [--exact | --pin] [--dry-run] [--offline]
```

The target section is inferred from the slug's Modrinth project type —
mods to [`mods`](mods-yaml.md#mods), resource packs to
[`resource_packs`](mods-yaml.md#resource_packs), and so on. `url:` and
`path:` sources infer from the artifact's file type. Pass `--type` to
override the inference; it is required for `--url` / `--path` entries
whose filename doesn't uniquely identify a type (non-`.jar` files).

| Option         | Description                                                                                            |
|----------------|--------------------------------------------------------------------------------------------------------|
| `--env`        | Sets [`environment`](mods-yaml.md#per-mod-environment). Forces long form.                              |
| `--url`        | Use a [`url:` source](mods-yaml.md#long-form). Marks the pack non-publishable when added to `mods`.    |
| `--path`       | Use a [`path:` source](mods-yaml.md#long-form).                                                        |
| `--type`       | Override the inferred section. Accepts `mod`, `resourcepack`, `datapack`, `shader`. See below.         |
| `--accepts-mc` | Additional MC versions to tolerate for this entry. Repeatable. See below.                              |
| `--exact`      | Keep the resolved version's build metadata inside the caret. See below.                                |
| `--pin`        | Write the resolved version as a bare semver (no caret). Equivalent to `add` then [`pin`](#pin).        |
| `--dry-run`    | Print the edit without writing.                                                                        |
| `--offline`    | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache. |

`--accepts-mc <mc-version>` widens the Modrinth `game_versions` query
when picking a default constraint, and persists the list under
[`accepts-mc`](mods-yaml.md#per-entry-mc-version-tolerance-accepts-mc)
on the new entry (forces long form). Use when the mod works on the
pack's [`mc-version`](mods-yaml.md#mc-version) but the author tagged
only adjacent versions on Modrinth. Incompatible with `--url` /
`--path`.

By default `add` writes a caret constraint on the resolved version's
`major.minor.patch` (`^6.0.10`), dropping any Modrinth build metadata
(`+mc1.21.1`). Both forms accept the same versions — `pub_semver`
ignores build metadata — but the stripped default keeps `mods.yaml`
readable. Pass `--exact` to preserve the full resolved version inside
the caret (`^6.0.10+mc1.21.1`) when traceability to the original
Modrinth file matters, or `--pin` to freeze the entry to the bare
`major.minor.patch` (no caret). Only applies when no `@<constraint>`
is supplied; incompatible with `--url` / `--path`. `--exact` and
`--pin` are mutually exclusive.

When Modrinth returns a non-semver version (e.g.
`release-snapshot-xyz`), `add` can't produce a caret — carets require
a semver-shaped base. In that case it falls back to writing the raw
version as an exact pin. See
[arbitrary-string version names](mods-yaml.md#arbitrary-string-version-names)
for what that implies for subsequent `get` runs.

`--type` overrides section inference. For Modrinth sources it prints a
warning when it contradicts the project's inferred type, then proceeds
— user's explicit choice wins. For `--url` / `--path` sources it is the
only way to file a non-`.jar` artifact (e.g. `foo.zip` could be a
resource pack, data pack, or shader); `add` refuses to guess.

### `remove`

Remove an entry and re-resolve. Identifies the target by slug.

```text
gitrinth remove <slug> [--dry-run] [--offline]
```

| Option      | Description                                                                                            |
|-------------|--------------------------------------------------------------------------------------------------------|
| `--dry-run` | Print the edit without writing.                                                                        |
| `--offline` | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache. |

The section is inferred from where `<slug>` currently lives in
`mods.yaml`.

### `pin`

Rewrite an entry's version constraint to the currently-locked version's
bare `major.minor.patch`, stripping any caret and any tag-style build
metadata (e.g. `+mc1.21.1`). Four-segment Modrinth versions like
`19.27.0.340` are kept intact as `19.27.0+340` — the fourth number
carries real version info, so pin preserves it as numeric build
metadata. Ergonomic sugar over manual `mods.yaml` edits. Requires an
existing `mods.lock` — run [`get`](#get) first.

```text
gitrinth pin <slug> [--type <mod|resourcepack|datapack|shader>]
                    [--dry-run]
```

| Option      | Description                                                                  |
|-------------|------------------------------------------------------------------------------|
| `--type`    | Disambiguate `<slug>` when it lives in multiple sections of `mods.yaml`.     |
| `--dry-run` | Print the edit without writing.                                              |

Only applies to Modrinth-sourced entries — `url:` / `path:` entries
have no semver to pin. Does not re-resolve: the bare version still
satisfies the existing lock.

### `unpin`

Inverse of [`pin`](#pin). Prepends `^` to a bare-semver constraint so
subsequent [`get`](#get) runs pick up newer compatible versions. Reads
only `mods.yaml`; does not touch the lock.

```text
gitrinth unpin <slug> [--type <mod|resourcepack|datapack|shader>]
                      [--dry-run]
```

| Option      | Description                                                                  |
|-------------|------------------------------------------------------------------------------|
| `--type`    | Disambiguate `<slug>` when it lives in multiple sections of `mods.yaml`.     |
| `--dry-run` | Print the edit without writing.                                              |

Errors if the constraint already has a caret, is a channel token
(`release`, `beta`, `alpha`), or isn't semver-shaped.

### `create`

Modpack-specific. Scaffold a new modpack directory with a minimal
`mods.yaml`. The final positional argument is the target directory,
created if missing.

```text
gitrinth create [--loader <loader>] [--mc-version <version>] [--slug <slug>]
                [--name <name>] [--force] [--offline] <directory>
```

(`--offline` here is the create-specific form: it skips the Modrinth
slug-availability round-trip; the cache is not consulted because
`create` does not resolve any entries.)

[`slug`](mods-yaml.md#slug) defaults to the basename of `<directory>`,
lower-cased. [`name`](mods-yaml.md#name) defaults to the slug. The
slug must be 3–64 characters from Modrinth's allowed set
(`a-zA-Z0-9!@$()` `` ` `` `.+,_"-`); pass `--slug` to override the
derived value.

| Option         | Description                                                                    |
|----------------|--------------------------------------------------------------------------------|
| `--loader`     | Pre-fill [`loader`](mods-yaml.md#loader). Defaults to `neoforge`.              |
| `--mc-version` | Pre-fill [`mc-version`](mods-yaml.md#mc-version). Defaults to `1.21.1`.        |
| `--slug`       | Override the derived slug.                                                     |
| `--name`       | Override the display [`name`](mods-yaml.md#name).                              |
| `--force`      | Allow scaffolding into a non-empty directory; overwrites existing `mods.yaml`. |
| `--offline`    | Skip the Modrinth slug-availability check.                                     |

Refuses to run when `<directory>` exists and is non-empty without
`--force`.

Before scaffolding, `create` queries Modrinth to see whether the slug
is already in use by another project. If it is, `create` prints a
warning and proceeds anyway — you can rename later or rerun with
`--slug`. If the request fails (no network, DNS error, etc.), `create`
warns and proceeds without the check; pass `--offline` to skip the
round-trip altogether.

#### Example

```console
$ gitrinth create example_modpack
Created example_modpack in example_modpack
  + example_modpack/mods.yaml
  + example_modpack/README.md
  + example_modpack/.gitignore
  + example_modpack/.modrinth_ignore
```

The resulting `example_modpack/mods.yaml`:

```yaml
slug: example_modpack
name: example_modpack
version: 0.1.0
description: A new Modrinth modpack.

loader:
  mods: neoforge
mc-version: 1.21.1

tooling:
  gitrinth: ">=0.1.0 <1.0.0"

mods:

resource_packs:

data_packs:

shaders:

plugins:
```

### `build`

Modpack-specific. Assemble distributions into `build/`. One
sub-directory per environment, laid out for drop-in use by a launcher
or server.

The server distribution includes the matching server binary for
[`loader`](mods-yaml.md#loader) and
[`mc-version`](mods-yaml.md#mc-version), fetched and installed
automatically from the upstream Maven repositories. Fabric drops in
`fabric-server-launch.jar`; Forge and NeoForge run their official
installer in `--installServer` mode against `build/server/`, so the
output tree contains `run.bat`/`run.sh`, `libraries/`, and
`user_jvm_args.txt` ready for [`launch server`](#launch).

```text
gitrinth build [--env <client|server|both>] [--output <path>]
              [--clean] [--skip-download] [--no-prune] [--offline]
```

| Option            | Description                                                                                            |
|-------------------|--------------------------------------------------------------------------------------------------------|
| `--env`           | Build only the named environment.                                                                      |
| `--output`, `-o`  | Override the output directory. Defaults to `./build`.                                                  |
| `--clean`         | Remove the output directory before building.                                                           |
| `--skip-download` | Fail rather than fetch missing artifacts.                                                              |
| `--no-prune`      | Skip deleting obsolete files left over from a previous build. The new state ledger is still written.   |
| `--offline`       | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache. |

Partitioning follows
[`environment`](mods-yaml.md#per-mod-environment): default `both`;
shaders are client-only; [`plugins`](mods-yaml.md#plugins) are
server-only. Under plugin loaders (`bukkit`, `folia`, `paper`,
`spigot`), [`mods`](mods-yaml.md#mods) are forced client-only;
[`resource_packs`](mods-yaml.md#resource_packs) and
[`data_packs`](mods-yaml.md#data_packs) partition normally. See
[Plugin loaders](mods-yaml.md#plugin-loaders).

#### Prune behavior

Each build records the set of files it wrote into a side-car ledger
at `build/<env>/.gitrinth-state.yaml`. On the next run, `build`
compares the prior ledger against the new desired set and deletes
files that are in the prior ledger but no longer wanted — typically
because a mod was removed from `mods.yaml`, a [`files:`](mods-yaml.md#files)
entry was deleted, or a per-side state changed.

What `build` will prune:

- Mod jars, pack files, shader packs, and data packs whose lock
  entries were dropped from the manifest.
- [`files:`](mods-yaml.md#files) entries that were removed from the
  manifest (including `preserve: true` entries — `preserve` is *not*
  sticky against removal).

What `build` will **never** prune:

- Files not in the prior ledger. A custom jar dropped into
  `build/<env>/mods/` by the user, or any file from a fresh `--clean`
  rebuild, is invisible to the prune pass and survives indefinitely.
- The loader installer's outputs (`build/server/libraries/`,
  `server.jar`, `run.bat`/`run.sh`, etc.). The installer runs after
  the prune pass and writes outside the ledger.
- The ledger itself and any `.gitrinth-installed-<loader>-<v>` marker.

`--clean` wipes the output directory before the build, which clears
the ledger too. `--no-prune` writes the new ledger but skips the
delete pass — useful for inspecting which files would be pruned on
the next run.

When the assemble step is about to overwrite an existing destination
that was *not* in the prior ledger, `build` logs a warning:
`overwriting unmanaged file at <path> (was not in prior ledger)`.
This catches the most common collision footgun (a custom jar with
the same filename as a managed mod) without changing the
overwrite-by-default behavior.

### `clean`

Modpack-specific. Delete every file `gitrinth` generates from
`mods.yaml`, so the next [`get`](#get) / [`build`](#build) /
[`pack`](#pack) starts from a clean slate. Leaves `mods.yaml` and
`mods_overrides.yaml` untouched (they are source-controlled inputs)
and does not touch the shared artifact cache — use
[`cache clean`](#cache) for that.

```text
gitrinth clean [--output <path>]
```

| Option           | Description                                                                            |
|------------------|----------------------------------------------------------------------------------------|
| `--output`, `-o` | Build directory to remove. Defaults to `./build`, matching [`build`](#build)'s output. |

Always removes, when present:

- `./mods.lock`
- the build output directory (`./build` by default, or `--output`)

The default [`pack`](#pack) artifact lives inside the build directory,
so it is swept up by the build-directory deletion above. A `pack`
artifact written to a custom `--output` path must be removed manually.
Non-existent paths are a silent no-op.

### `pack`

Modpack-specific. Produce Modrinth `.mrpack` archives.

```text
gitrinth pack [--output <path>] [--combined] [--publishable] [--offline]
```

| Option           | Description                                                                                                                                       |
|------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| `--output`, `-o` | Override the base output path. Defaults to `./build/<slug>-<version>.mrpack`. The server pack is derived by inserting `-server` before `.mrpack`. |
| `--combined`     | Produce a single `.mrpack` that contains both client and server files instead of a client + server pair.                                          |
| `--publishable`  | Refuse to pack if any [`mods`](mods-yaml.md#mods) entry uses a `url` or `path` source. Other sections are unaffected.                             |
| `--offline`      | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache.                                            |

By default `pack` produces two artifacts:

- `./build/<slug>-<version>.mrpack` — the client pack.
- `./build/<slug>-<version>-server.mrpack` — the server pack, with
  client-only entries stripped out.

The split uses each entry's
[`environment`](mods-yaml.md#per-mod-environment): `both` entries are
bundled in both packs, `client` entries only in the client pack, and
`server` entries only in the server pack. Shaders are always
client-only by section and land exclusively in the client pack.

**Installing the server pack.** Drop the `-server.mrpack` onto your
server host and install it with
[mrpack-install](https://github.com/nothub/mrpack-install) — a
standalone Go-based installer that fetches every file in the pack's
Modrinth CDN `files[]` array, applies the `server-overrides/` tree, and
drops in the matching server binary for your loader.

Pass `--combined` when you want the older single-artifact behavior
(useful for quick local round-trips or when a downstream tool expects
one zip). With `--combined` only `./build/<slug>-<version>.mrpack` is
written, containing every file partitioned by the per-file `env` map.

`url:` / `path:` artifacts cannot be referenced in the spec's `files[]`
list because every entry there needs a Modrinth CDN URL, so they are
packed as loose files under `overrides/<subdir>/<filename>` (routed to
`client-overrides/` / `server-overrides/` when their `environment`
narrows the side). `--publishable` gates this for the
[`mods`](mods-yaml.md#mods) section only, since per Modrinth's policy
executable mod artifacts require explicit author permission to
redistribute. Resource packs, data packs, and shaders remain free to
bundle non-Modrinth artifacts even with `--publishable`.

[`files:`](mods-yaml.md#files) entries are bundled the same way: the
destination key carries the full sub-path (e.g.
`config/sodium-options.json`) and `pack` routes the file directly to
`overrides/<destination>` / `client-overrides/<destination>` /
`server-overrides/<destination>` based on the entry's per-side state.
`files:` entries do not trip `--publishable` — Modrinth's permission
policy targets executable mod jars only, and loose configs are
explicitly permitted in publishable packs.

When `pack` bundles non-Modrinth mod artifacts (default mode) it prints
a warning enumerating each offending slug and links to
[Modrinth's permissions guidance](https://support.modrinth.com/en/articles/8797527-obtaining-modpack-permissions).

### `launch`

Modpack-specific. Build (when needed) and start the modpack so you can
test it end-to-end without leaving the CLI. Two subcommands:

- [`launch server`](#launch-server) — boot the server JVM/script in
  `build/server/` directly.
- [`launch client`](#launch-client) — install the loader into a
  per-pack workdir under the gitrinth cache, symlink the build's
  artifact dirs (`mods/`, `config/`, ...) into it, and open the
  official Minecraft Launcher there.

#### `launch server`

```text
gitrinth launch server [--accept-eula] [--no-build] [--memory <size>]
                       [--output <path>] [--offline] [-- <extra args>]
```

| Option           | Description                                                                                         |
|------------------|-----------------------------------------------------------------------------------------------------|
| `--accept-eula`  | Write `eula=true` into `build/server/eula.txt` before starting. You agree to the Mojang EULA.       |
| `--no-build`     | Skip the implicit `gitrinth build --env server`. Use when the build tree is already up to date.     |
| `--memory`, `-m` | JVM heap size, applied as `-Xmx`/`-Xms`. Examples: `2G`, `4G`, `6144M`. Defaults to `2G`.           |
| `--output`, `-o` | Override the build output directory. Defaults to `./build`.                                         |
| `--offline`      | Forwarded to the auto-build step. Refuses to launch if a Forge/NeoForge install would need network. |
| `-- <args>`      | Trailing args after `--` are appended to the server JVM/script invocation (e.g. `-- --port 25566`). |

`launch server` reads `mods.lock` to pick the right command per loader:

- Fabric — `java -Xmx<mem> -Xms<mem> -jar fabric-server-launch.jar nogui`
- Forge / NeoForge — `run.bat` (Windows) or `run.sh` (POSIX); the heap
  size is written into `user_jvm_args.txt` rather than the CLI so the
  installer's wrapper script picks it up.

The Mojang EULA at <https://aka.ms/MinecraftEULA> applies — `eula.txt`
must be `eula=true` before any vanilla server boots. `--accept-eula`
performs that flip on your behalf; without it the JVM prints the EULA
notice and exits, and you can re-run with the flag.

#### `launch client`

```text
gitrinth launch client [--no-build] [--output <path>] [--offline]
```

| Option           | Description                                                                                     |
|------------------|-------------------------------------------------------------------------------------------------|
| `--no-build`     | Skip the implicit `gitrinth build --env client`. Use when the build tree is already up to date. |
| `--output`, `-o` | Override the build output directory. Defaults to `./build`.                                     |
| `--offline`      | Rejected — the launcher needs network on first run to download libraries and assets.            |

Each modpack gets its own `.minecraft`-shaped workdir under the
gitrinth cache at `~/.gitrinth_cache/launchers/<slug>/`. The artifact
dirs inside that workdir (`mods/`, `config/`, `resourcepacks/`,
`shaderpacks/`, `datapacks/`) are directory symlinks — junctions on
Windows — pointing back at `build/client/<section>`. Everything else
the launcher writes (`versions/`, `libraries/`, `assets/`,
`launcher_profiles.json`) and everything the user accumulates
(`saves/`, `screenshots/`, `options.txt`, `servers.dat`, `logs/`,
`crash-reports/`) is a real file inside the cache workdir. Result:
`gitrinth clean` can wipe `build/` without touching the user's worlds
or installed loader. The user's real `~/.minecraft/launcher_profiles.json`
is also left untouched — the launcher reads only the workdir's copy.

The flow:

1. Builds `build/client/` (drop with `--no-build`).
2. Creates the cache workdir at
   `~/.gitrinth_cache/launchers/<slug>/` and refreshes a symlink for
   each artifact section pointing at `build/client/<section>`.
3. Fetches the loader's client installer JAR (cached at
   `~/.gitrinth_cache/loaders/<loader>/<mc>/<v>/`).
4. Runs `<installer> --installClient <cache workdir>` once per
   `(loader, mc, loader-version)` triple. This populates
   `<cache workdir>/versions/<id>/<id>.json`,
   `<cache workdir>/libraries/`, and writes a single profile entry in
   `<cache workdir>/launcher_profiles.json`.
5. Spawns `MinecraftLauncher.exe --workDir <abs path to cache workdir>`.
6. The launcher GUI offers exactly one profile; click Play. Auth +
   asset/JRE download are handled by the launcher, scoped to the cache
   workdir.

**Requirements.** This relies on the
[`--workDir`](https://minecraft.wiki/w/Minecraft_Launcher) flag of the
**legacy unified Minecraft Launcher** (`MinecraftLauncher.exe`). The
Microsoft Store / Xbox-app variant does **not** honour `--workDir` —
self-launching the JVM directly is tracked as a follow-up in
[`todo.md`](todo.md#self-launch-jvm-skip-the-official-launcher).

**Caveats.**

- Two checkouts of the same modpack share `<cache>/launchers/<slug>/`,
  including saves and `options.txt`. Rename the slug or remove the
  workdir before forking a checkout you want isolated.
- After `gitrinth clean` the artifact symlinks dangle; the next
  `gitrinth launch client` rebuilds `build/client/` and refreshes
  them automatically.
- The cache workdir is not removed by `gitrinth clean`. Delete
  `<cache>/launchers/<slug>/` manually to reclaim its disk or reset
  in-game state.

**Disk cost.** Each modpack carries its own libraries (~500 MB),
assets (~1 GB on first launch), and bundled JRE (~200 MB) inside its
cache workdir. `gitrinth clean` does not sweep them; the cache
workdir survives so worlds and tweaked options aren't lost. Hardlink
deduplication across modpacks is a future optimization.

Override the launcher locator with `GITRINTH_LAUNCHER` (single path)
or `GITRINTH_LAUNCHER_SEARCH_PATHS` (list, separated by `;` on Windows
or `:` elsewhere) — useful for portable installs and CI.

### `cache`

Inspect, clean, or repair the local cache — downloaded `.jar` files
and Modrinth metadata snapshots.

```text
gitrinth cache list
gitrinth cache clean [--force]
gitrinth cache repair
```

| Subcommand | Description                                                                                                                                                                       |
|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `list`     | Print every cached artifact as JSON: cache root, plus per-artifact filename, size, and on-disk location.                                                                          |
| `clean`    | Delete every cached artifact. Prompts for confirmation before deleting; pass `--force` (`-f`) to skip the prompt. Refuses to wipe without `--force` when stdin is not a terminal. |
| `repair`   | Re-verify every cached file against its expected hash. Re-downloads corrupt Modrinth-sourced entries; deletes corrupt url-sourced entries (the next `gitrinth get` re-fetches).   |

### `completion`

Emit a shell-completion script for the given shell to stdout. No
filesystem writes — the user redirects or sources the output as they
prefer. See [Shell completion](#shell-completion) for per-shell install
snippets.

```text
gitrinth completion <bash|zsh|fish|powershell>
```

Covers subcommand names, flag names, and the enum values already
constrained on the argparse side (`--env`, `--loader`). Re-run after
upgrading `gitrinth` to refresh installed scripts.

## Working with overrides

`mods.yaml` supports an [`overrides`](mods-yaml.md#overrides) section.
Overrides are edited directly in the manifest; there is no CLI
wrapper.

Overrides may also live in a standalone
[`mods_overrides.yaml`](mods-overrides-yaml.md) alongside
`mods.yaml`. Both are merged during resolution, with
`mods_overrides.yaml` winning on conflicting keys.

## Exit codes

| Code | Meaning                                        |
|------|------------------------------------------------|
| `0`  | Success.                                       |
| `1`  | Recoverable user-facing error.                 |
| `2`  | Validation or resolution failed.               |
| `5`  | Cache corruption `cache repair` could not fix. |
| `64` | Usage error — matches `sysexits.h` `EX_USAGE`. |

## Environment variables

| Variable                     | Used by       | Purpose                                                   |
|------------------------------|---------------|-----------------------------------------------------------|
| `GITRINTH_CACHE`             | every command | Override the cache root.                                  |
| `GITRINTH_MODRINTH_URL`      | every command | Override the default Modrinth base URL.                   |
| `HTTPS_PROXY` / `HTTP_PROXY` | every command | Standard proxy variables, honoured by every HTTP request. |

## Shell completion

[`gitrinth completion`](#completion) prints a completion script to
stdout. Redirect it into the location your shell expects, then start a
new shell (or re-source your profile). Re-run after upgrading
`gitrinth` to pick up any new commands or flags.

**bash.** User-local install into your `bash-completion` data dir:

```bash
gitrinth completion bash > ~/.local/share/bash-completion/completions/gitrinth
```

Or, to load on demand from your `~/.bashrc`:

```bash
source <(gitrinth completion bash)
```

**zsh.** Drop the script somewhere on your `$fpath` (for example, the
first directory in `$fpath`) and ensure `compinit` runs on startup:

```zsh
gitrinth completion zsh > "${fpath[1]}/_gitrinth"
```

**fish.** Fish auto-loads completions from its per-user completions
directory:

```fish
gitrinth completion fish > ~/.config/fish/completions/gitrinth.fish
```

**PowerShell.** Append the completer to your profile so it's
registered in every session:

```powershell
gitrinth completion powershell | Out-String | Invoke-Expression
```

To make it persistent, write the output to your `$PROFILE`:

```powershell
gitrinth completion powershell >> $PROFILE
```

`pwsh` is accepted as an alias for `powershell`.

## Files

| Path                              | Purpose                                                                                |
|-----------------------------------|----------------------------------------------------------------------------------------|
| `./mods.yaml`                     | Modpack manifest. See [`mods.yaml`](mods-yaml.md).                                     |
| `./mods_overrides.yaml`           | Optional standalone overrides. See [`mods_overrides.yaml`](mods-overrides-yaml.md).    |
| `./mods.lock`                     | Resolved versions. Commit to git.                                                      |
| `./build/`                        | Default output directory for [`build`](#build).                                        |
| `./build/<slug>-<version>.mrpack` | Default output path for [`pack`](#pack).                                               |
| `~/.gitrinth_cache/`              | Cache root. `~` is `$HOME` (`$USERPROFILE` on Windows). Override via `GITRINTH_CACHE`. |

## Compatibility

`gitrinth` follows semver for its CLI surface.
[`tooling.gitrinth`](mods-yaml.md#gitrinth) pins the expected
compatibility window.

## See also

- [`mods.yaml` reference](mods-yaml.md) — the manifest every command
  operates on.
- [`mods_overrides.yaml` reference](mods-overrides-yaml.md) — optional
  standalone overrides file.
- [`mods.schema.yaml`](../assets/schema/mods.schema.yaml) and
  [`mods-overrides.schema.yaml`](../assets/schema/mods-overrides.schema.yaml) —
  machine-readable schemas editors can wire up for in-file validation.
- [`todo.md`](todo.md) — planned improvements and deferred CLI surface.
- [Modrinth API docs](https://docs.modrinth.com) — upstream service.
