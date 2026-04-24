# `gitrinth` planned improvements

Post-MVP work. Tracks planned improvements sourced from a comparison
against [packwiz](https://github.com/packwiz/packwiz) plus deferred
MVP work previously tracked in [`mvp.md`](mvp.md). Each item has a
detailed spec further down.

## Status

Planned improvements:

- [x] [`accepts-mc` — per-entry MC version tolerance](#accepts-mc--per-entry-mc-version-tolerance)
- [ ] [`migrate` command](#migrate-command)
- [ ] [Optional mods](#optional-mods)
- [ ] [`pin` / `unpin` commands](#pin--unpin-commands)
- [ ] [Shell completion](#shell-completion)
- [x] [`add` writes caret semver constraints](#add-writes-caret-semver-constraints-by-default)
- [ ] [CurseForge bridge](curseforge-bridge.md)

Deferred MVP work:

- [ ] [Modrinth slug-validity check in `create`](#modrinth-slug-validity-check-in-create)
- [ ] [Hosted source support](#hosted-source-support)
- [ ] [Plugin-loader support](#plugin-loader-support)
- [ ] [Global options: `-q`/`--quiet`, `--offline`, `--no-color`, `--config`](#deferred-global-options)
- [ ] [Loose-files override support in `.mrpack`](#loose-files-override-support)
- [ ] [`build` auto-downloads server binary](#build-auto-downloads-server-binary)
- [ ] [Automatic `:stable` / `:latest` loader tag resolution](#automatic-stable--latest-loader-tag-resolution)
- [ ] [`downgrade` command](#downgrade-command)
- [ ] [`outdated` command](#outdated-command)
- [ ] [`deps` command](#deps-command)
- [ ] [`publish` command](#publish-command)
- [ ] [`login` / `logout` commands](#login--logout-commands)
- [ ] [`token` command](#token-command)
- [ ] [`unpack` command](#unpack-command)

## `accepts-mc` — per-entry MC version tolerance

Widen the Modrinth `game_versions` query for a single entry when a mod
works on the pack's `mc-version` but the author only tagged adjacent
versions on Modrinth. The pack's `mc-version` remains the single source
of truth; `accepts-mc` is additive and query-time only.

```yaml
mods:
  appleskin:
    version: ^3.0.9+mc1.21
    accepts-mc: [1.21]
```

Semantics: additive to the pack's `mc-version`, query-time only, no
effect on pack-level `mc-version` or server binary selection. Applies to
`modSource` and `forcedEnvSource` (mods, resource_packs, data_packs,
shaders, plugins). `mods.lock` records the MC version each resolved
file was actually tagged for, so later MC bumps surface under-tagged
entries.

Touches: [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml),
[`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart),
[`lib/src/service/resolver.dart`](../lib/src/service/resolver.dart),
[`mods-yaml.md`](mods-yaml.md), [`example/mods.yaml`](../example/mods.yaml).

## `migrate` command

Bump `mc-version` or `loader.mods` in `mods.yaml` and re-resolve against
the new target in one step. Leverages the existing pubgrub resolver;
aligns with gitrinth's single-MC-version invariant (one command, one
deterministic transition).

```text
gitrinth migrate mc <version>
gitrinth migrate loader <loader>[:<tag>]
```

`--dry-run` resolves and reports the diff without writing files.
Failure policy: leave `mods.yaml` and `mods.lock` untouched if any
required entry fails to resolve; print the offending entries.

Touches: [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart),
new `lib/src/commands/migrate.dart`, [`cli.md`](cli.md).

## Optional mods

Per-entry `optional` block that survives `.mrpack` export so the
Modrinth app and Prism present a user-facing toggle. Complements the
existing `environment` field — optional mods install off by default
unless the user opts in. Preserves through the env-split path (an
optional client mod stays optional in the client `.mrpack`).

```yaml
mods:
  distanthorizons:
    version: beta
    optional:
      default: false
      description: Adds far-render LoDs. Heavy on VRAM.
```

Touches: [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml),
[`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart),
archive builder, [`mods-yaml.md`](mods-yaml.md),
[`example/mods.yaml`](../example/mods.yaml).

## `pin` / `unpin` commands

Ergonomic sugar over manual `mods.yaml` edits. `pin` rewrites an entry's
`version:` to the currently-locked version (freezing it); `unpin`
restores the previous constraint (or clears it). `--section`
disambiguates when the slug exists in multiple sections. YAML formatting
and comments are preserved via `package:yaml_edit`. The pre-pin
constraint is stored (in `mods.lock` or a sidecar) so `unpin` is
lossless.

```text
gitrinth pin <slug> [--section <section>]
gitrinth unpin <slug> [--section <section>]
```

Touches: [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart),
new `lib/src/commands/pin.dart` and `unpin.dart`, [`cli.md`](cli.md).

## Shell completion

Generate completion scripts for bash, zsh, fish, and PowerShell. Dart's
`package:args` `CommandRunner` exposes enough metadata to emit these
without hand-rolling per-shell logic. Emits to stdout; no filesystem
writes. Covers subcommand names, flag names, and known enum values
(loaders, channels, environments).

```text
gitrinth completion <bash|zsh|fish|powershell>
```

Touches: [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart),
new `lib/src/commands/completion.dart`, [`cli.md`](cli.md) (one short
install section per shell).

## Add writes caret semver constraints by default

When [`add`](cli.md#add) resolves a slug and writes the entry back to
`mods.yaml`, emit a caret-prefixed constraint (e.g. `^6.0.10`)
instead of the exact resolved version (`6.0.10+mc1.21.1`). Matches the
convention already used in [`example/mods.yaml`](../example/mods.yaml)
and lets subsequent [`get`](cli.md#get) runs pick up newer compatible
versions without re-running `add`.

Prerequisite for the [CurseForge bridge](curseforge-bridge.md): CF pack
manifests record exact file IDs, not semver constraints. The import
path translates resolved CF file versions into caret constraints, and
routing that through the same constraint-writing path keeps one
canonical shape for written entries.

`--exact` is available for users who want to retain the resolved
version's build metadata inside the caret (`^6.0.10+mc1.21.1`).

Touches: [`lib/src/commands/add.dart`](../lib/src/commands/add.dart),
[`cli.md`](cli.md) (document `--exact`).

## Modrinth slug-validity check in `create`

[`create`](cli.md#create) currently scaffolds without verifying the
target slug is available on Modrinth. Wire up the
[Modrinth project-validity endpoint](https://docs.modrinth.com/api/operations/checkprojectvalidity/)
so `create` refuses to run when the slug is malformed or already taken.

Touches: [`lib/src/commands/create.dart`](../lib/src/commands/create.dart),
[`lib/src/service/modrinth_api.dart`](../lib/src/service/modrinth_api.dart),
[`cli.md`](cli.md).

## Hosted source support

Long-form entries may declare `hosted: <url>` pointing at a
Modrinth-compatible server; resolution and download are deferred
pending the [`token` command](#token-command) (needed to authenticate
against non-modrinth.com servers). Once tokens are in place, `hosted:`
entries resolve identically to default Modrinth entries, just against
the declared server URL.

Touches: [`lib/src/service/modrinth_api.dart`](../lib/src/service/modrinth_api.dart),
[`lib/src/service/resolver.dart`](../lib/src/service/resolver.dart),
[`mods-yaml.md`](mods-yaml.md).

## Plugin-loader support

Add `bukkit`, `folia`, `paper`, `spigot` to `loader.mods`, and ship the
`plugins:` section. Under plugin loaders, `mods` ship client-only
regardless of `environment`, `plugins` ship server-only, and shaders
stay client-only. The schema already permits `loader.plugins`; the
parser currently rejects these values.

Touches: [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart),
archive builder, [`mods-yaml.md`](mods-yaml.md).

## Deferred global options

Four deferred flags on the top-level CLI:

| Option            | Description                                                                             |
|-------------------|-----------------------------------------------------------------------------------------|
| `-q`, `--quiet`   | Suppress informational output; errors still print. Mutually exclusive with `--verbose`. |
| `--offline`       | Never hit the network. Fails if the cache is missing a required mod.                    |
| `--no-color`      | Disable ANSI colour. Also respected via `NO_COLOR`.                                     |
| `--config <path>` | Use an alternate user config file.                                                      |

`--config` implies a companion `GITRINTH_CONFIG` environment variable
and a platform user-config location (where stored tokens live — see
[`login` / `logout`](#login--logout-commands) and
[`token`](#token-command)).

Touches: [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart),
[`cli.md`](cli.md).

## Loose-files override support

Modrinth `.mrpack` archives permit a loose-file override tree (for
config files, scripts, etc.) separate from the `files[]` array.
[`pack`](cli.md#pack) currently only routes `url:` / `path:` artifacts
into `overrides/`. Generalize to first-class config-file overrides: the
user drops files into `overrides/`, `client-overrides/`, or
`server-overrides/` under the pack root, and `pack` preserves them in
the archive.

Touches: archive builder, [`mods-yaml.md`](mods-yaml.md),
[`cli.md`](cli.md) (document the override tree layout).

## `build` auto-downloads server binary

[`build`](cli.md#build)'s server distribution needs the matching server
binary for [`loader.mods`](mods-yaml.md#loader) +
[`mc-version`](mods-yaml.md#mc-version). Fabric works today via
`meta.fabricmc.net`; Forge and NeoForge require the user to supply the
installer by hand. Wire up the corresponding upstream APIs so `build`
fetches the server installer automatically.

Touches: [`lib/src/commands/build.dart`](../lib/src/commands/build.dart),
new upstream-API clients for Forge and NeoForge.

## Automatic `:stable` / `:latest` loader tag resolution

[`loader.mods`](mods-yaml.md#loader) accepts a docker-image-style tag:
`<loader>:stable` (default, latest stable loader), `<loader>:latest`
(newest of any stability), or a concrete version string. Stable/latest
resolution is implemented for Fabric (via `meta.fabricmc.net`) but not
for Forge or NeoForge — users must specify a concrete tag (e.g.
`forge:52.0.45`, `neoforge:21.1.50`). Wire up the Forge and NeoForge
upstream APIs.

Touches: [`lib/src/service/resolver.dart`](../lib/src/service/resolver.dart),
new upstream-API clients.

## `downgrade` command

Resolve to the **oldest** version compatible with each constraint.

```text
gitrinth downgrade [<slug>...] [--dry-run]
```

## `outdated` command

Report entries whose `mods.lock` version is behind the newest allowed
by the loader/Minecraft pair. Read-only.

```text
gitrinth outdated [--json]
```

| Option   | Description                          |
|----------|--------------------------------------|
| `--json` | Emit a machine-readable JSON report. |

## `deps` command

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

## `publish` command

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

Requires a token stored via [`login`](#login--logout-commands) or
[`token`](#token-command). Consumes `GITRINTH_TOKEN` if set; it
overrides any stored token. Adds exit code `4` (authentication
failure).

## `login` / `logout` commands

Store and clear a Modrinth personal-access token for the default
server (modrinth.com) in the user config. The token is never echoed
and can be piped over stdin.

```text
gitrinth login
gitrinth logout
```

## `token` command

Manage tokens for additional Modrinth-compatible servers — anything
other than modrinth.com. Use [`login` / `logout`](#login--logout-commands)
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

## `unpack` command

Unpack a modpack into a new project directory and reconstruct
`mods.yaml` by resolving each file's Modrinth URL back to its slug and
version. The source is either a Modrinth project slug (in which case
the matching `.mrpack` is downloaded from Modrinth or the server given
by `--hosted` first) or a path to a local `.mrpack` file. Loose
override files from the archive are preserved inside the output
directory. Inverse of [`pack`](cli.md#pack).

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
| `--no-resolve`   | Skip the implicit [`get`](cli.md#get) that normally runs after unpacking.                                                            |
