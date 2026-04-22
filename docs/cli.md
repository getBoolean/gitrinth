# The `gitrinth` CLI

**gitrinth** manages a modpack declared in [`mods.yaml`](mods-yaml.md).
It resolves entries against [Modrinth](https://modrinth.com) (or the
sources declared in the file), locks resolved versions to `mods.lock`,
assembles client and server distributions, and publishes the modpack.

The CLI is modelled on Dart's [`pub`](https://dart.dev/tools/pub/cmd):
the verbs, flag names, and surrounding ergonomics track `pub` wherever
the underlying operation maps cleanly. Modpack-specific operations
(build, pack, scaffold) are additions; everything else mirrors a `pub`
subcommand.

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
| `-v`, `--verbose`          | Emit progress and resolution detail. Repeat (`-vv`) for HTTP-level tracing.             |
| `-q`, `--quiet`            | Suppress informational output; errors still print. Mutually exclusive with `--verbose`. |
| `-C`, `--directory <path>` | Run as if invoked from `<path>`.                                                        |
| `--offline`                | Never hit the network. Fails if the cache is missing a required mod.                    |
| `--no-color`               | Disable ANSI colour. Also respected via `NO_COLOR`.                                     |
| `--config <path>`          | Use an alternate user config file. Default under [Files](#files).                       |

## Commands

Grouped by purpose. The "`pub` analogue" column shows the
corresponding Dart command; commands with no analogue are
modpack-specific extensions.

### Dependencies

| Command                   | `pub` analogue  | Purpose                                                       |
|---------------------------|-----------------|---------------------------------------------------------------|
| [`get`](#get)             | `pub get`       | Resolve entries, write `mods.lock`, download into the cache.  |
| [`upgrade`](#upgrade)     | `pub upgrade`   | Re-resolve to the newest versions allowed by each constraint. |
| [`downgrade`](#downgrade) | `pub downgrade` | Re-resolve to the oldest versions allowed by each constraint. |
| [`outdated`](#outdated)   | `pub outdated`  | Report entries behind the newest compatible version.          |
| [`add`](#add)             | `pub add`       | Add an entry to a section.                                    |
| [`remove`](#remove)       | `pub remove`    | Remove an entry.                                              |
| [`deps`](#deps)           | `pub deps`      | Print the resolved dependency tree.                           |

### Publishing

| Command               | `pub` analogue | Purpose                                                   |
|-----------------------|----------------|-----------------------------------------------------------|
| [`publish`](#publish) | `pub publish`  | Upload the modpack to Modrinth.                           |
| [`login`](#login)     | `pub login`    | Store a Modrinth token.                                   |
| [`logout`](#logout)   | `pub logout`   | Clear the stored token.                                   |
| [`token`](#token)     | `pub token`    | Manage tokens for additional Modrinth-compatible servers. |

### Cache

| Command           | `pub` analogue | Purpose                                    |
|-------------------|----------------|--------------------------------------------|
| [`cache`](#cache) | `pub cache`    | Inspect, clean, or repair the local cache. |

### Modpack-specific

| Command             | Purpose                                                       |
|---------------------|---------------------------------------------------------------|
| [`create`](#create) | Scaffold a new modpack directory.                             |
| [`build`](#build)   | Assemble the client and/or server distribution into `build/`. |
| [`pack`](#pack)     | Produce a Modrinth `.mrpack` artifact.                        |
| [`unpack`](#unpack) | Scaffold a modpack directory from an existing `.mrpack`.      |

## Command details

### `get`

Analogue of [`pub get`](https://dart.dev/tools/pub/cmd/pub-get).
Resolve every entry in `mods.yaml`, apply
[`overrides`](mods-yaml.md#overrides), write `mods.lock`, and download
artifacts into the cache. Does not upgrade entries already locked to a
satisfying version — use [`upgrade`](#upgrade) for that.

```text
gitrinth get [--dry-run] [--enforce-lockfile] [--offline]
```

| Option               | Description                                                                                                    |
|----------------------|----------------------------------------------------------------------------------------------------------------|
| `--dry-run`          | Resolve without writing. Exits non-zero if the lockfile would change. Matches `pub get --dry-run`.             |
| `--enforce-lockfile` | Fail if `mods.lock` would change. Also forbids missing lockfile entries. Matches `pub get --enforce-lockfile`. |
| `--offline`          | Shortcut for the global `--offline` flag.                                                                      |

```console
$ gitrinth get
Resolving 12 mods, 2 resource packs, 1 shader...
  + create 6.0.12+mc1.21.1
  + jei 19.27.0.340
  + iris 1.8.13+1.21.1-neoforge (client)
  + ...
Locked 15 entries to mods.lock.
Downloaded 3 new artifacts (re-used 12 from cache).
```

### `upgrade`

Analogue of [`pub upgrade`](https://dart.dev/tools/pub/cmd/pub-upgrade).
Re-resolve to the **newest** version allowed by each constraint,
updating `mods.lock`. Leaves `mods.yaml` untouched unless
`--major-versions` is passed. Pass slugs to upgrade only those entries.

```text
gitrinth upgrade [<slug>...] [--major-versions] [--dry-run]
```

| Option             | Description                                                                                                                                   |
|--------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| `--major-versions` | Ignore caret boundaries and pick the absolute newest version. Rewrites the constraint in `mods.yaml`. Matches `pub upgrade --major-versions`. |
| `--dry-run`        | Print changes without writing.                                                                                                                |

```console
$ gitrinth upgrade create jei
  ~ create 6.0.10+mc1.21.1 -> 6.0.12+mc1.21.1
  ~ jei    19.27.0.310    -> 19.27.0.340
Updated 2 entries in mods.lock.
```

### `downgrade`

Analogue of
[`pub downgrade`](https://dart.dev/tools/pub/cmd/pub-downgrade).
Resolve to the **oldest** version compatible with each constraint.

```text
gitrinth downgrade [<slug>...] [--dry-run]
```

### `outdated`

Analogue of
[`pub outdated`](https://dart.dev/tools/pub/cmd/pub-outdated). Report
entries whose `mods.lock` version is behind the newest allowed by the
loader/Minecraft pair. Read-only.

```text
gitrinth outdated [--json]
```

| Option   | Description                          |
|----------|--------------------------------------|
| `--json` | Emit a machine-readable JSON report. |

```console
$ gitrinth outdated
Slug     Current              Latest-matching     Latest-overall
create   6.0.10+mc1.21.1      6.0.12+mc1.21.1     6.1.0+mc1.21.1
jei      19.27.0.310          19.27.0.340         19.28.0.000
2 entries have updates available.
```

### `add`

Analogue of [`pub add`](https://dart.dev/tools/pub/cmd/pub-add). Add an
entry to [`mods`](mods-yaml.md#mods),
[`resource_packs`](mods-yaml.md#resource_packs),
[`data_packs`](mods-yaml.md#data_packs),
[`shaders`](mods-yaml.md#shaders),
[`plugins`](mods-yaml.md#plugins), or
[`servers`](mods-yaml.md#servers), then re-resolve.

```text
gitrinth add <slug>[@<constraint>] [--env <client|server|both>]
            [--hosted <url> | --url <url> | --path <path> | --git <repo>]
            [--ref <ref>] [--subpath <path>]
            [--name <name>] [--address <host>]
            [--dry-run]
```

The target section is inferred from the slug's Modrinth project type —
mods to [`mods`](mods-yaml.md#mods), resource packs to
[`resource_packs`](mods-yaml.md#resource_packs), and so on. `url:`,
`path:`, and `git:` sources infer from the artifact's file type.

| Option      | Description                                                                                         |
|-------------|-----------------------------------------------------------------------------------------------------|
| `--env`     | Sets [`environment`](mods-yaml.md#per-mod-environment). Forces long form.                           |
| `--hosted`  | Use a [`hosted:` source](mods-yaml.md#long-form). The `pub add --hosted` analogue.                  |
| `--url`     | Use a [`url:` source](mods-yaml.md#long-form). Marks the pack non-publishable when added to `mods`. |
| `--path`    | Use a [`path:` source](mods-yaml.md#long-form). The `pub add --path` analogue.                      |
| `--git`     | Use a [`git:` source](mods-yaml.md#git-sources). The `pub add --git-url` analogue.                  |
| `--ref`     | With `--git`, pin to a branch, tag, or commit. Matches `pub add --git-ref`.                         |
| `--subpath` | With `--git`, enter a sub-path inside the repo. Matches `pub add --git-path`.                       |
| `--name`    | Server display name. Implies the [`servers`](mods-yaml.md#servers) section.                         |
| `--address` | Server address. Implies the [`servers`](mods-yaml.md#servers) section.                              |
| `--dry-run` | Print the edit without writing.                                                                     |

**Servers.** A Modrinth slug whose project type is "server" is added
to [`servers`](mods-yaml.md#servers) automatically. Passing `--name`
or `--address` also targets that section and populates the long form;
omit both to record a blank short-form entry that Modrinth resolves at
build time.

```console
$ gitrinth add jei@^19.27.0
Added jei ^19.27.0 to mods.
$ gitrinth add iris@^1.8.12 --env client
Added iris ^1.8.12 to mods (client only).
$ gitrinth add forked_jei --git example/forked_jei --ref mc-1.21.1
Added forked_jei to mods (git: example/forked_jei@mc-1.21.1).
$ gitrinth add complex-cobblemon
Added server complex-cobblemon (resolved from Modrinth at build time).
$ gitrinth add example_server --name "Example" --address play.example.com
Added server example_server "Example" (play.example.com).
```

### `remove`

Analogue of [`pub remove`](https://dart.dev/tools/pub/cmd/pub-remove).
Remove an entry and re-resolve. Identifies the target by slug.

```text
gitrinth remove <slug> [--dry-run]
```

The section is inferred from where `<slug>` currently lives in
`mods.yaml`.

### `deps`

Analogue of [`pub deps`](https://dart.dev/tools/pub/cmd/pub-deps).
Print the resolved dependency tree. Reads `mods.lock`; falls back to
resolving in memory if missing or stale.

```text
gitrinth deps [<slug>] [--env <client|server|both>]
             [--style <compact|tree|list>] [--json]
```

| Option    | Description                                                                       |
|-----------|-----------------------------------------------------------------------------------|
| `<slug>`  | Limit output to a single entry and its transitive dependencies.                   |
| `--env`   | Filter by [`environment`](mods-yaml.md#per-mod-environment).                      |
| `--style` | Output style. Matches `pub deps --style`: `compact`, `tree` (default), or `list`. |
| `--json`  | Emit a machine-readable report.                                                   |

### `publish`

Analogue of [`pub publish`](https://dart.dev/tools/pub/cmd/pub-publish).
Upload the modpack to Modrinth (or the server declared in
[`publish_to`](mods-yaml.md#publish_to)).

```text
gitrinth publish [--dry-run] [--force] [--draft]
                [--version-type <release|beta|alpha>]
                [--changelog <path>]
```

| Option           | Description                                                                                                            |
|------------------|------------------------------------------------------------------------------------------------------------------------|
| `--dry-run`      | Produce the artifact and validate the payload without uploading. Matches `pub publish --dry-run`.                      |
| `--force`        | Skip the interactive confirmation prompt. Matches `pub publish --force`.                                               |
| `--draft`        | Upload as a draft.                                                                                                     |
| `--version-type` | Modrinth version channel. Defaults to `release`; `beta` if [`version`](mods-yaml.md#version) has a pre-release suffix. |
| `--changelog`    | Markdown changelog path. Defaults to the matching section of `CHANGELOG.md`.                                           |

Requires a token stored via [`login`](#login) or [`token`](#token).

### `login`

Analogue of [`pub login`](https://dart.dev/tools/pub/cmd/pub-login).
Store a Modrinth personal-access token for the default server
(modrinth.com) in the user config. The token is never echoed and can
be piped over stdin.

```text
gitrinth login
```

```console
$ gitrinth login
Paste a Modrinth personal-access token (input hidden):
Saved token for https://modrinth.com.
```

### `logout`

Analogue of [`pub logout`](https://dart.dev/tools/pub/cmd/pub-logout).
Clear the stored token for the default server.

```text
gitrinth logout
```

### `token`

Analogue of [`pub token`](https://dart.dev/tools/pub/cmd/pub-token).
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

Analogue of [`pub cache`](https://dart.dev/tools/pub/cmd/pub-cache).
Inspect, clean, or repair the local cache — downloaded `.jar` files,
cloned git repositories for `git:` sources, and Modrinth metadata
snapshots.

```text
gitrinth cache list [--path]
gitrinth cache clean [--all | --older-than <duration>]
gitrinth cache repair
```

| Subcommand | Description                                                                                                                                |
|------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| `list`     | Print cache entries with sizes. `--path` prints only the cache root.                                                                       |
| `clean`    | Remove cache entries. `--all` clears everything; `--older-than` removes entries untouched for longer than the duration (e.g. `30d`, `6h`). |
| `repair`   | Re-verify every cached file against its Modrinth hash and re-download corrupt entries. Matches `pub cache repair`.                         |

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
| `--loader`     | Pre-fill [`loader`](mods-yaml.md#loader). Prompts if omitted.                  |
| `--mc-version` | Pre-fill [`mc-version`](mods-yaml.md#mc-version). Prompts if omitted.          |
| `--slug`       | Override the derived slug.                                                     |
| `--name`       | Override the display [`name`](mods-yaml.md#name).                              |
| `--force`      | Allow scaffolding into a non-empty directory; overwrites existing `mods.yaml`. |

Refuses to run when `<directory>` exists and is non-empty without
`--force`.

```console
$ gitrinth create --loader neoforge --mc-version 1.21.1 example_modpack
Creating example_modpack/
  example_modpack/mods.yaml
Next: cd example_modpack && gitrinth get
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
shaders and [`servers`](mods-yaml.md#servers) are client-only;
[`plugins`](mods-yaml.md#plugins) are server-only. Under plugin loaders
(`bukkit`, `folia`, `paper`, `spigot`),
[`mods`](mods-yaml.md#mods) are forced client-only;
[`resource_packs`](mods-yaml.md#resource_packs) and
[`data_packs`](mods-yaml.md#data_packs) partition normally. See
[Plugin loaders](mods-yaml.md#plugin-loaders).

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
[`overrides`](mods-yaml.md#overrides) entry uses a `url`, `path`, or
`git` source.

### `unpack`

Analogue of [`pub unpack`](https://dart.dev/tools/pub/cmd/pub-unpack).
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

| Option           | Description                                                                                                   |
|------------------|---------------------------------------------------------------------------------------------------------------|
| `<slug>`         | Modrinth project slug. Downloads the matching `.mrpack` before extracting.                                    |
| `<version>`      | Version constraint on the slug form. Defaults to the newest release on the resolved server.                   |
| `<path>`         | Path to a local `.mrpack` file. Skips the download step. Chosen when the positional resolves to a file on disk or ends in `.mrpack`. |
| `--hosted <url>` | Fetch from a Modrinth-compatible server at `<url>`. Slug form only. Mirrors the `hosted` descriptor on `pub unpack`. |
| `--output`, `-o` | Output directory. Defaults to the current directory. Matches `pub unpack --output`.                           |
| `--force`, `-f`  | Overwrite existing files in the output directory. Matches `pub unpack --force`.                               |
| `--no-resolve`   | Skip the implicit [`get`](#get) that normally runs after unpacking. Matches `pub unpack --no-resolve`.        |

```console
$ gitrinth unpack example_modpack:1.0.0 -o example_modpack
Downloading example_modpack 1.0.0 from https://modrinth.com...
Unpacking into example_modpack/
  example_modpack/mods.yaml
Resolving 15 entries...
Locked 15 entries to mods.lock.

$ gitrinth unpack ./example_modpack-1.0.0.mrpack -o example_modpack
Unpacking example_modpack-1.0.0.mrpack into example_modpack/
  example_modpack/mods.yaml
Resolving 15 entries...
Locked 15 entries to mods.lock.
```

## Working with overrides

`mods.yaml` supports an [`overrides`](mods-yaml.md#overrides) section —
the analogue of Dart's `dependency_overrides`. As in `pub`, overrides
are edited directly in the manifest; there is no CLI wrapper.

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

| Variable                     | Used by        | Purpose                                                          |
|------------------------------|----------------|------------------------------------------------------------------|
| `GITRINTH_CACHE`             | every command  | Override the cache root. Mirrors `PUB_CACHE`.                    |
| `GITRINTH_CONFIG`            | every command  | Override the user config file. Equivalent to `--config`.         |
| `GITRINTH_TOKEN`             | `publish`      | Modrinth token. Overrides any token stored by [`login`](#login). |
| `GITRINTH_MODRINTH_URL`      | every command  | Override the default Modrinth base URL. Mirrors `PUB_HOSTED_URL`.|
| `NO_COLOR`                   | every command  | Disables ANSI colour when set. Equivalent to `--no-color`.       |
| `HTTPS_PROXY` / `HTTP_PROXY` | every command  | Standard proxy variables, honoured by every HTTP request.        |
| `GIT_*`                      | `git:` sources | Passed through to the ambient `git` CLI.                         |

## Files

| Path                                                         | Purpose                                                       |
|--------------------------------------------------------------|---------------------------------------------------------------|
| `./mods.yaml`                                                | Modpack manifest. See [`mods.yaml`](mods-yaml.md).            |
| `./mods_overrides.yaml`                                      | Optional standalone overrides. See [`mods_overrides.yaml`](mods-overrides-yaml.md). |
| `./mods.lock`                                                | Resolved versions. Commit to git. Analogue of `pubspec.lock`. |
| `./build/`                                                   | Default output directory for [`build`](#build).               |
| `./<slug>-<version>.mrpack`                                  | Default output path for [`pack`](#pack).                      |
| `$XDG_CACHE_HOME/gitrinth/` (Linux)                          | Cache root. Falls back to `~/.cache/gitrinth`.                |
| `~/Library/Caches/gitrinth/` (macOS)                         | Cache root.                                                   |
| `%LOCALAPPDATA%\gitrinth\Cache\` (Windows)                   | Cache root.                                                   |
| `$XDG_CONFIG_HOME/gitrinth/config.yaml` (Linux)              | User config — stored tokens, default server URL.              |
| `~/Library/Application Support/gitrinth/config.yaml` (macOS) | User config.                                                  |
| `%APPDATA%\gitrinth\config.yaml` (Windows)                   | User config.                                                  |

## Compatibility

`gitrinth` follows semver for its CLI surface:

- **Major** — may remove or rename commands and flags.
- **Minor** — adds commands or flags; never removes.
- **Patch** — bug fixes only.

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
- [Dart `pub` command reference](https://dart.dev/tools/pub/cmd) — the
  upstream design `gitrinth` tracks.
- [Modrinth API docs](https://docs.modrinth.com) — upstream service.
