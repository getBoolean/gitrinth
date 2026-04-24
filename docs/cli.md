# The `gitrinth` CLI

**gitrinth** manages a modpack declared in [`mods.yaml`](mods-yaml.md).
It resolves entries against [Modrinth](https://modrinth.com) (or the
sources declared in the file), locks resolved versions to `mods.lock`,
assembles client and server distributions, and publishes the modpack.

## Synopsis

```text
gitrinth [<global-options>] <command> [<command-options>] [<arguments>]
gitrinth --help
gitrinth --version
```

Commands operate on `mods.yaml` in the current directory by default.
Use [`--directory`](#global-options) to target a different modpack.

## Global options

| Option                     | Description                                                                             |
|----------------------------|-----------------------------------------------------------------------------------------|
| `-h`, `--help`             | Print usage. After a command name, prints that command's usage.                         |
| `--version`                | Print the `gitrinth` version and exit.                                                  |
| `-v`, `--verbose`          | Emit progress and resolution detail.                                                    |
| `-q`, `--quiet`            | Suppress informational output; errors still print. Mutually exclusive with `--verbose`. |
| `-C`, `--directory <path>` | Run as if invoked from `<path>`.                                                        |
| `--offline`                | Never hit the network. Fails if the cache is missing a required mod.                    |
| `--no-color`               | Disable ANSI colour. Also respected via `NO_COLOR`.                                     |
| `--config <path>`          | Use an alternate user config file. Default under [Files](#files).                       |

## Commands

### Dependencies

| Command                   | Purpose                                                       |
|---------------------------|---------------------------------------------------------------|
| [`get`](#get)             | Resolve entries, write `mods.lock`, download into the cache.  |
| [`upgrade`](#upgrade)     | Re-resolve to the newest versions allowed by each constraint. |
| [`downgrade`](#downgrade) | Re-resolve to the oldest versions allowed by each constraint. |
| [`outdated`](#outdated)   | Report entries behind the newest compatible version.          |
| [`add`](#add)             | Add an entry to a section.                                    |
| [`remove`](#remove)       | Remove an entry.                                              |
| [`deps`](#deps)           | Print the resolved dependency tree.                           |

### Publishing

| Command               | Purpose                                                   |
|-----------------------|-----------------------------------------------------------|
| [`publish`](#publish) | Upload the modpack to Modrinth.                           |
| [`login`](#login)     | Store a Modrinth token.                                   |
| [`logout`](#logout)   | Clear the stored token.                                   |
| [`token`](#token)     | Manage tokens for additional Modrinth-compatible servers. |

### Cache

| Command           | Purpose                                    |
|-------------------|--------------------------------------------|
| [`cache`](#cache) | Inspect, clean, or repair the local cache. |

### Modpack-specific

| Command             | Purpose                                                       |
|---------------------|---------------------------------------------------------------|
| [`create`](#create) | Scaffold a new modpack directory.                             |
| [`build`](#build)   | Assemble the client and/or server distribution into `build/`. |
| [`clean`](#clean)   | Delete generated files: `build/`, `mods.lock`, `.mrpack`.     |
| [`pack`](#pack)     | Produce a Modrinth `.mrpack` artifact.                        |
| [`unpack`](#unpack) | Scaffold a modpack directory from an existing `.mrpack`.      |

## Console output

Mutating commands emit a resolution header (e.g. `Resolving 12 mods, 2
resource packs, 1 shader...`), followed by per-entry lines prefixed
with `+` for additions, `~` for updates, and `-` for removals. They
finish with a summary line such as `Locked 15 entries to mods.lock.`
or `Updated 2 entries in mods.lock.`. Read-only reports (`outdated`,
`deps`) print a table or tree to stdout. `--verbose` (`-v`) adds
resolver detail.

## Command details

### `get`

Resolve every entry in `mods.yaml`, apply
[`overrides`](mods-yaml.md#overrides), write `mods.lock`, and download
artifacts into the cache. Does not upgrade entries already locked to a
satisfying version — use [`upgrade`](#upgrade) for that.

```text
gitrinth get [--dry-run] [--enforce-lockfile] [--offline]
```

| Option               | Description                                                              |
|----------------------|--------------------------------------------------------------------------|
| `--dry-run`          | Resolve without writing. Exits non-zero if the lockfile would change.    |
| `--enforce-lockfile` | Fail if `mods.lock` would change. Also forbids missing lockfile entries. |
| `--offline`          | Shortcut for the global `--offline` flag.                                |

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

### `downgrade`

Resolve to the **oldest** version compatible with each constraint.

```text
gitrinth downgrade [<slug>...] [--dry-run]
```

### `outdated`

Report entries whose `mods.lock` version is behind the newest allowed
by the loader/Minecraft pair. Read-only.

```text
gitrinth outdated [--json]
```

| Option   | Description                          |
|----------|--------------------------------------|
| `--json` | Emit a machine-readable JSON report. |

### `add`

Add an entry to [`mods`](mods-yaml.md#mods),
[`resource_packs`](mods-yaml.md#resource_packs),
[`data_packs`](mods-yaml.md#data_packs),
[`shaders`](mods-yaml.md#shaders), or
[`plugins`](mods-yaml.md#plugins), then re-resolve.

```text
gitrinth add <slug>[@<constraint>] [--env <client|server|both>]
            [--hosted <url> | --url <url> | --path <path>]
            [--dry-run]
```

The target section is inferred from the slug's Modrinth project type —
mods to [`mods`](mods-yaml.md#mods), resource packs to
[`resource_packs`](mods-yaml.md#resource_packs), and so on. `url:` and
`path:` sources infer from the artifact's file type.

| Option      | Description                                                                                         |
|-------------|-----------------------------------------------------------------------------------------------------|
| `--env`     | Sets [`environment`](mods-yaml.md#per-mod-environment). Forces long form.                           |
| `--hosted`  | Use a [`hosted:` source](mods-yaml.md#long-form).                                                   |
| `--url`     | Use a [`url:` source](mods-yaml.md#long-form). Marks the pack non-publishable when added to `mods`. |
| `--path`    | Use a [`path:` source](mods-yaml.md#long-form).                                                     |
| `--dry-run` | Print the edit without writing.                                                                     |

### `remove`

Remove an entry and re-resolve. Identifies the target by slug.

```text
gitrinth remove <slug> [--dry-run]
```

The section is inferred from where `<slug>` currently lives in
`mods.yaml`.

### `deps`

Print the resolved dependency tree. Reads `mods.lock`; falls back to
resolving in memory if missing or stale.

```text
gitrinth deps [<slug>] [--env <client|server|both>]
             [--style <compact|tree|list>] [--json]
```

| Option    | Description                                                     |
|-----------|-----------------------------------------------------------------|
| `<slug>`  | Limit output to a single entry and its transitive dependencies. |
| `--env`   | Filter by [`environment`](mods-yaml.md#per-mod-environment).    |
| `--style` | Output style: `compact`, `tree` (default), or `list`.           |
| `--json`  | Emit a machine-readable report.                                 |

### `publish`

Upload the modpack to Modrinth (or the server declared in
[`publish_to`](mods-yaml.md#publish_to)).

```text
gitrinth publish [--dry-run] [--force] [--draft]
                [--version-type <release|beta|alpha>]
                [--changelog <path>]
```

| Option           | Description                                                                                                            |
|------------------|------------------------------------------------------------------------------------------------------------------------|
| `--dry-run`      | Produce the artifact and validate the payload without uploading.                                                       |
| `--force`        | Skip the interactive confirmation prompt.                                                                              |
| `--draft`        | Upload as a draft.                                                                                                     |
| `--version-type` | Modrinth version channel. Defaults to `release`; `beta` if [`version`](mods-yaml.md#version) has a pre-release suffix. |
| `--changelog`    | Markdown changelog path. Defaults to the matching section of `CHANGELOG.md`.                                           |

Requires a token stored via [`login`](#login) or [`token`](#token).

### `login`

Store a Modrinth personal-access token for the default server
(modrinth.com) in the user config. The token is never echoed and can
be piped over stdin.

```text
gitrinth login
```

### `logout`

Clear the stored token for the default server.

```text
gitrinth logout
```

### `token`

Manage tokens for additional Modrinth-compatible servers — anything
other than modrinth.com. Use [`login`](#login) / [`logout`](#logout)
for the default server.

```text
gitrinth token add <server-url>
gitrinth token list
gitrinth token remove <server-url>
```

| Subcommand | Description                                                                          |
|------------|--------------------------------------------------------------------------------------|
| `add`      | Prompt for a token and associate it with `<server-url>`. Accepts stdin like `login`. |
| `list`     | Print every server that currently has a stored token.                                |
| `remove`   | Clear the token for `<server-url>`.                                                  |

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
defaults to the slug. The slug is validated against the
[Modrinth project-validity endpoint](https://docs.modrinth.com/api/operations/checkprojectvalidity/)
before scaffolding; `create` refuses to run if the slug is malformed
or already taken.

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
[`mc-version`](mods-yaml.md#mc-version); `gitrinth` downloads it
automatically.

```text
gitrinth build [--env <client|server|both>] [--output <path>]
              [--clean] [--skip-download]
```

| Option            | Description                                                          |
|-------------------|----------------------------------------------------------------------|
| `--env`           | Build only the named environment.                                    |
| `--output`, `-o`  | Override the output directory. Defaults to `./build`.                |
| `--clean`         | Remove the output directory before building.                         |
| `--skip-download` | Fail rather than fetch missing artifacts. Equivalent to `--offline`. |

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
- `./<slug>-<version>.mrpack` — the default [`pack`](#pack) artifact for the current `mods.yaml`

Non-existent paths are a silent no-op. A `pack` artifact written to a
custom `--output` path must be removed manually.

### `pack`

Modpack-specific. Produce a Modrinth `.mrpack` archive. This is the
artifact [`publish`](#publish) uploads.

```text
gitrinth pack [--output <path>]
```

| Option           | Description                                                        |
|------------------|--------------------------------------------------------------------|
| `--output`, `-o` | Override the output path. Defaults to `./<slug>-<version>.mrpack`. |

Refuses to run if any [`mods`](mods-yaml.md#mods) or mod-targeting
[`overrides`](mods-yaml.md#overrides) entry uses a `url` or `path`
source.

### `unpack`

Unpack a modpack into a new project directory and reconstruct
`mods.yaml` by resolving each file's Modrinth URL back to its slug and
version. The source is either a Modrinth project slug — in which case
the matching `.mrpack` is downloaded from Modrinth (or the server
given by `--hosted`) first — or a path to a local `.mrpack` file.
Loose override files from the archive are preserved inside the output
directory. Inverse of [`pack`](#pack).

```text
gitrinth unpack <slug>[:<version>] [--hosted <url>]
               [--output <directory>] [--force] [--no-resolve]
gitrinth unpack <path>             [--output <directory>] [--force] [--no-resolve]
```

| Option           | Description                                                                                                                          |
|------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| `<slug>`         | Modrinth project slug. Downloads the matching `.mrpack` before extracting.                                                           |
| `<version>`      | Version constraint on the slug form. Defaults to the newest release on the resolved server.                                          |
| `<path>`         | Path to a local `.mrpack` file. Skips the download step. Chosen when the positional resolves to a file on disk or ends in `.mrpack`. |
| `--hosted <url>` | Fetch from a Modrinth-compatible server at `<url>`. Slug form only.                                                                  |
| `--output`, `-o` | Output directory. Defaults to the current directory.                                                                                 |
| `--force`, `-f`  | Overwrite existing files in the output directory.                                                                                    |
| `--no-resolve`   | Skip the implicit [`get`](#get) that normally runs after unpacking.                                                                  |

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
| `3`  | Network error.                                 |
| `4`  | Authentication failure during `publish`.       |
| `5`  | Cache corruption `cache repair` could not fix. |
| `64` | Usage error — matches `sysexits.h` `EX_USAGE`. |

## Environment variables

| Variable                     | Used by       | Purpose                                                          |
|------------------------------|---------------|------------------------------------------------------------------|
| `GITRINTH_CACHE`             | every command | Override the cache root.                                         |
| `GITRINTH_CONFIG`            | every command | Override the user config file. Equivalent to `--config`.         |
| `GITRINTH_TOKEN`             | `publish`     | Modrinth token. Overrides any token stored by [`login`](#login). |
| `GITRINTH_MODRINTH_URL`      | every command | Override the default Modrinth base URL.                          |
| `NO_COLOR`                   | every command | Disables ANSI colour when set. Equivalent to `--no-color`.       |
| `HTTPS_PROXY` / `HTTP_PROXY` | every command | Standard proxy variables, honoured by every HTTP request.        |

## Files

| Path                        | Purpose                                                                                |
|-----------------------------|----------------------------------------------------------------------------------------|
| `./mods.yaml`               | Modpack manifest. See [`mods.yaml`](mods-yaml.md).                                     |
| `./mods_overrides.yaml`     | Optional standalone overrides. See [`mods_overrides.yaml`](mods-overrides-yaml.md).    |
| `./mods.lock`               | Resolved versions. Commit to git.                                                      |
| `./build/`                  | Default output directory for [`build`](#build).                                        |
| `./<slug>-<version>.mrpack` | Default output path for [`pack`](#pack).                                               |
| `~/.gitrinth_cache/`        | Cache root. `~` is `$HOME` (`$USERPROFILE` on Windows). Override via `GITRINTH_CACHE`. |
| Platform config directory   | User config — stored tokens, default server URL. Override via `GITRINTH_CONFIG`.       |

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
- [Modrinth API docs](https://docs.modrinth.com) — upstream service.
