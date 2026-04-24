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

## Command details

### `get`

Resolve every entry in `mods.yaml`, apply
[`overrides`](mods-yaml.md#overrides), write `mods.lock`, and download
artifacts into the cache. Does not upgrade entries already locked to a
satisfying version — use [`upgrade`](#upgrade) for that.

```text
gitrinth get [--dry-run] [--enforce-lockfile]
```

| Option               | Description                                                              |
|----------------------|--------------------------------------------------------------------------|
| `--dry-run`          | Resolve without writing. Exits non-zero if the lockfile would change.    |
| `--enforce-lockfile` | Fail if `mods.lock` would change. Also forbids missing lockfile entries. |

### `upgrade`

Re-resolve to the **newest** version allowed by each constraint,
updating `mods.lock`. Leaves `mods.yaml` untouched unless
`--major-versions` is passed. Pass slugs to upgrade only those entries.

```text
gitrinth upgrade [<slug>...] [--major-versions] [--dry-run]
```

| Option             | Description                                                                                           |
|--------------------|-------------------------------------------------------------------------------------------------------|
| `--major-versions` | Ignore caret boundaries and pick the absolute newest version. Rewrites the constraint in `mods.yaml`. |
| `--dry-run`        | Print changes without writing.                                                                        |

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
            [--exact | --pin] [--dry-run]
```

The target section is inferred from the slug's Modrinth project type —
mods to [`mods`](mods-yaml.md#mods), resource packs to
[`resource_packs`](mods-yaml.md#resource_packs), and so on. `url:` and
`path:` sources infer from the artifact's file type. Pass `--type` to
override the inference; it is required for `--url` / `--path` entries
whose filename doesn't uniquely identify a type (non-`.jar` files).

| Option         | Description                                                                                         |
|----------------|-----------------------------------------------------------------------------------------------------|
| `--env`        | Sets [`environment`](mods-yaml.md#per-mod-environment). Forces long form.                           |
| `--url`        | Use a [`url:` source](mods-yaml.md#long-form). Marks the pack non-publishable when added to `mods`. |
| `--path`       | Use a [`path:` source](mods-yaml.md#long-form).                                                     |
| `--type`       | Override the inferred section. Accepts `mod`, `resourcepack`, `datapack`, `shader`. See below.      |
| `--accepts-mc` | Additional MC versions to tolerate for this entry. Repeatable. See below.                           |
| `--exact`      | Keep the resolved version's build metadata inside the caret. See below.                             |
| `--pin`        | Write the resolved version as a bare semver (no caret). Equivalent to `add` then [`pin`](#pin).     |
| `--dry-run`    | Print the edit without writing.                                                                     |

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

`--type` overrides section inference. For Modrinth sources it prints a
warning when it contradicts the project's inferred type, then proceeds
— user's explicit choice wins. For `--url` / `--path` sources it is the
only way to file a non-`.jar` artifact (e.g. `foo.zip` could be a
resource pack, data pack, or shader); `add` refuses to guess.

### `remove`

Remove an entry and re-resolve. Identifies the target by slug.

```text
gitrinth remove <slug> [--dry-run]
```

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
                [--name <name>] [--force] <directory>
```

[`slug`](mods-yaml.md#slug) defaults to the basename of `<directory>`
(lower-cased, `-` replaced with `_`). [`name`](mods-yaml.md#name)
defaults to the slug.

| Option         | Description                                                                    |
|----------------|--------------------------------------------------------------------------------|
| `--loader`     | Pre-fill [`loader`](mods-yaml.md#loader). Defaults to `neoforge`.              |
| `--mc-version` | Pre-fill [`mc-version`](mods-yaml.md#mc-version). Defaults to `1.21.1`.        |
| `--slug`       | Override the derived slug.                                                     |
| `--name`       | Override the display [`name`](mods-yaml.md#name).                              |
| `--force`      | Allow scaffolding into a non-empty directory; overwrites existing `mods.yaml`. |

Refuses to run when `<directory>` exists and is non-empty without
`--force`.

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
[`mc-version`](mods-yaml.md#mc-version); users currently supply the
installer by hand (see [`todo.md`](todo.md#build-auto-downloads-server-binary)).

```text
gitrinth build [--env <client|server|both>] [--output <path>]
              [--clean] [--skip-download]
```

| Option            | Description                                          |
|-------------------|------------------------------------------------------|
| `--env`           | Build only the named environment.                    |
| `--output`, `-o`  | Override the output directory. Defaults to `./build`.|
| `--clean`         | Remove the output directory before building.         |
| `--skip-download` | Fail rather than fetch missing artifacts.            |

Partitioning follows
[`environment`](mods-yaml.md#per-mod-environment): default `both`;
shaders are client-only; [`plugins`](mods-yaml.md#plugins) are
server-only. Under plugin loaders (`bukkit`, `folia`, `paper`,
`spigot`), [`mods`](mods-yaml.md#mods) are forced client-only;
[`resource_packs`](mods-yaml.md#resource_packs) and
[`data_packs`](mods-yaml.md#data_packs) partition normally. See
[Plugin loaders](mods-yaml.md#plugin-loaders).

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
gitrinth pack [--output <path>] [--combined] [--publishable]
```

| Option           | Description                                                                                                                                       |
|------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| `--output`, `-o` | Override the base output path. Defaults to `./build/<slug>-<version>.mrpack`. The server pack is derived by inserting `-server` before `.mrpack`. |
| `--combined`     | Produce a single `.mrpack` that contains both client and server files instead of a client + server pair.                                          |
| `--publishable`  | Refuse to pack if any [`mods`](mods-yaml.md#mods) entry uses a `url` or `path` source. Other sections are unaffected.                             |

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

When `pack` bundles non-Modrinth mod artifacts (default mode) it prints
a warning enumerating each offending slug and links to
[Modrinth's permissions guidance](https://support.modrinth.com/en/articles/8797527-obtaining-modpack-permissions).

### `cache`

Inspect, clean, or repair the local cache — downloaded `.jar` files
and Modrinth metadata snapshots.

```text
gitrinth cache list [--path]
gitrinth cache clean [--all | --older-than <duration>]
gitrinth cache repair
```

| Subcommand | Description                                                                                                                                |
|------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| `list`     | Print cache entries with sizes. `--path` prints only the cache root.                                                                       |
| `clean`    | Remove cache entries. `--all` clears everything; `--older-than` removes entries untouched for longer than the duration (e.g. `30d`, `6h`). |
| `repair`   | Re-verify every cached file against its Modrinth hash and re-download corrupt entries.                                                     |

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
