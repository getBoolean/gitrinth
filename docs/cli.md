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

| Option                     | Description                                                                             |
|----------------------------|-----------------------------------------------------------------------------------------|
| `-h`, `--help`             | Print usage. After a command name, prints that command's usage.                         |
| `--version`                | Print the `gitrinth` version and exit.                                                  |
| `--verbosity <level>`      | Set the output floor. One of `error`, `warning`, `normal` (default), `io`, `solver`, `all`. See [Verbosity levels](#verbosity-levels). |
| `-v`, `--verbose`          | Shorthand for `--verbosity=all`. Mutually exclusive with `--quiet` and `--verbosity`.   |
| `-q`, `--quiet`            | Shorthand for `--verbosity=warning`. Mutually exclusive with `--verbose` and `--verbosity`. |
| `--color` / `--no-color`   | Force ANSI colour on or off. Defaults to auto-detection (honours `NO_COLOR`).           |
| `--config <path>`          | Use an alternate user config file. Overrides `GITRINTH_CONFIG` and the platform default. |
| `-C`, `--directory <path>` | Run as if invoked from `<path>`.                                                        |

## Commands

### Dependencies

| Command                   | Purpose                                                         |
|---------------------------|-----------------------------------------------------------------|
| [`get`](#get)             | Resolve entries, write `mods.lock`, download into the cache.    |
| [`upgrade`](#upgrade)     | Re-resolve to the newest version allowed by each constraint.    |
| [`downgrade`](#downgrade) | Re-resolve to the oldest version allowed by each constraint.    |
| [`outdated`](#outdated)   | Report locked entries that are behind newer compatible versions. |
| [`deps`](#deps)           | Print the resolved dependency tree.                             |
| [`migrate`](#migrate)     | Re-target the pack to a new Minecraft version or loader.        |
| [`add`](#add)             | Add an entry to a section.                                      |
| [`remove`](#remove)       | Remove an entry.                                                |
| [`override`](#override)   | Add a sticky override to `project_overrides`.                   |
| [`pin`](#pin)             | Freeze an entry to its currently-locked version.                |
| [`unpin`](#unpin)         | Restore a caret on a pinned entry.                              |

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

## Verbosity levels

`--verbosity=<level>` sets the output floor: every category at or
below the chosen level is printed; everything above is suppressed.
Levels form a total order from quietest to loudest:

| Level     | What prints                                                                                    |
|-----------|------------------------------------------------------------------------------------------------|
| `error`   | Errors only.                                                                                   |
| `warning` | Errors and warnings.                                                                           |
| `normal`  | Adds user-facing messages (resolution headers, diffs, summaries). Default.                     |
| `io`      | Adds file writes, downloads, cache hits/misses, lockfile ops, and installer subprocess output. |
| `solver`  | Adds version-resolution steps (candidate selection, conflict detection, override application). |
| `all`     | Adds internal tracing (stack traces on failure, low-level debug).                              |

`error` and `warning` go to stderr; the rest go to stdout. `-v` /
`--verbose` is shorthand for `--verbosity=all` and `-q` / `--quiet`
is shorthand for `--verbosity=warning`. Combining `--verbosity` with
either shorthand exits with a usage error.

## Console output

Mutating commands emit a resolution header (e.g. `Resolving 12 mods, 2
resource packs, 1 shader...`), followed by per-entry lines prefixed
with `+` for additions, `~` for updates, and `-` for removals. They
finish with a summary line such as `Locked 15 entries to mods.lock.`
or `Updated 2 entries in mods.lock.`. Raise the floor with
`--verbosity=io` to see file writes and downloads, `--verbosity=solver`
to see resolver steps, or `-v` (`--verbosity=all`) to add stack traces
on failure.

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
[`project_overrides`](mods-yaml.md#project_overrides), write `mods.lock`, and download
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

When `--major-versions` is set, `upgrade` auto-recovers existing
`gitrinth:disabled-by-conflict` markers (set by an earlier `migrate`):
the marker's constraint is relaxed to `any` for one resolution
attempt, and a successful resolve rewrites the marker to `^<resolved>`.

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

### `downgrade`

Re-resolve to the **oldest** version allowed by each constraint,
updating `mods.lock`. Mirrors [`upgrade`](#upgrade) in the opposite
direction. Useful for testing minimum-supported versions or for
reproducing a bug report against older releases. Pass slugs to
downgrade only those entries; the remaining entries keep their
existing locked versions.

```text
gitrinth downgrade [<slug>...] [--dry-run] [--offline]
```

| Option      | Description                                                                                            |
|-------------|--------------------------------------------------------------------------------------------------------|
| `--dry-run` | Print the diff without writing.                                                                        |
| `--offline` | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache. |

`downgrade` honors each entry's [`channel`](mods-yaml.md#channel)
floor: a `release`-channel entry never downgrades through `beta`/`alpha`
versions. It does not rewrite `mods.yaml`. Marker entries
(`gitrinth:not-found`, `gitrinth:disabled-by-conflict`) are skipped
with a one-line note.

When run with `--offline`, gitrinth prints a warning that the cache
may not contain the truly-oldest published version.

### `outdated`

Report locked entries that are behind newer compatible versions of
the same constraint, and entries whose constraint blocks an even
newer version. Read-only — never writes `mods.lock`.

```text
gitrinth outdated [--json] [--show-all] [--no-transitive] [--offline]
```

| Option            | Description                                                                                            |
|-------------------|--------------------------------------------------------------------------------------------------------|
| `--json`          | Emit a machine-readable JSON report instead of the table.                                              |
| `--show-all`      | Include up-to-date entries in the report. Off by default.                                              |
| `--no-transitive` | Hide entries whose `dependency:` is `transitive`. On by default (transitives shown).                   |
| `--offline`       | Use cached versions only; do not hit the network.                                                      |

The report has three columns:

- **Current** — the version recorded in `mods.lock`.
- **Upgradable** — the newest version allowed by the entry's
  [version constraint](mods-yaml.md#version-constraints) and channel
  floor. Equivalent to what [`upgrade`](#upgrade) would pick.
- **Latest** — the newest version allowed by the channel floor,
  ignoring the version constraint. Equivalent to what
  [`upgrade --major-versions`](#upgrade) would pick (modulo
  graph-aware resolution).

Entries are grouped under `direct dependencies:` and
`transitive dependencies:` headings. A `*` prefix marks any version
cell that is not the row's Latest. Versions equal to the cell to
their left render in gray (e.g. Latest equals Upgradable). On
terminals where `NO_COLOR` is set or stdout is not a TTY, all colors
are dropped.

`url:` and `path:` entries are listed with their pinned
path/URL — they have no version pool. `project_overrides:` entries
are listed with `(overridden)` and the Latest column matches the
override's pinned version.

The graph-aware "Resolvable" column from comparable tools is omitted
in this version: producing it requires a full re-resolution under
relaxed constraints, which is too expensive for a report command.

### `deps`

Print the resolved dependency tree. Reads `mods.lock`. Errors out
if the lock is missing or stale — run [`get`](#get) first to
populate it.

```text
gitrinth deps [<slug>] [--style <compact|tree|list>]
              [--env <client|server|both>] [--json]
```

| Option       | Description                                                                |
|--------------|----------------------------------------------------------------------------|
| `<slug>`     | Limit output to a single direct entry and its transitive dependencies.     |
| `-s, --style`| Output style: `compact`, `tree` (default), or `list`.                      |
| `--env`      | Filter by [`environment`](mods-yaml.md#per-mod-environment). Default `both`. |
| `--json`     | Emit a machine-readable JSON report. Mutually exclusive with `--style`.    |

`tree` style indents children with `├── └── │   ` connectors when
the terminal supports unicode/ANSI; falls back to ASCII (`|--
'-- |   `) otherwise. Slugs that appear more than once in the
graph (typical for shared transitives) render as `<slug>...` in
gray on second and later occurrences.

`list` style flattens each direct entry's children one level deep
under the entry; `compact` style appends a bracketed list of
direct child slugs to each direct entry on a single line.

`--env client` skips entries whose
[`environment`](mods-yaml.md#per-mod-environment) is `unsupported`
on the client side; `--env server` does the same for the server
side. `both` (the default) shows everything.

Cold-cache transitive children (a slug whose `version.json` sidecar
hasn't been written yet) cannot be walked; gitrinth prints a
trailing footer naming how many entries were skipped and recommends
re-running [`get`](#get) once.

### `migrate`

Re-target the modpack to a new Minecraft version or mod loader and
re-resolve every entry. Always crosses caret boundaries (like
`upgrade --major-versions`).

```text
gitrinth migrate mc <version>                       [--dry-run] [--offline]
gitrinth migrate loader <loader>[:<tag>]            [--dry-run] [--offline]
```

| Option      | Description                                            |
|-------------|--------------------------------------------------------|
| `--dry-run` | Resolve and report the diff without writing files.     |
| `--offline` | Use cached versions only; skip the availability check. |

`<loader>` is `forge`, `fabric`, or `neoforge`. `:<tag>` is a concrete
version, `stable`, or `latest` (default `stable`).

If a mod has no version published for the new target, its `version:` is
rewritten to `gitrinth:not-found` and the entry is omitted from the
lock; `client`/`server`/`channel`/etc. are preserved. A later `migrate`
that finds a compatible version rewrites the marker to `^<resolved>`.
[`get`](#get), [`upgrade`](#upgrade), and `--enforce-lockfile` skip
marker entries and print a one-line count.

If the resolver finds versions but the graph is unsatisfiable, `migrate`
writes `gitrinth:disabled-by-conflict` into the `version:` field of
every user-declared mod that participates in the conflict, re-resolves
the now-shrunk pack, writes a fresh `mods.lock`, and exits 0 with a
warning naming each disabled mod. Edit `mods.yaml` to remove the marker
from any mod you want back, then re-run `migrate` (or `upgrade
--major-versions`) to retry — recovered entries are rewritten to
`^<resolved>`. If disabling the conflict roots still leaves an
unsatisfiable graph, `migrate` rolls back, writes nothing, and exits
non-zero.

`--offline` skips the availability check; marker entries stay markers.

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

`add` refuses when the picked version of `<slug>` and an existing
user mod declare each other incompatible (Modrinth `dependency_type:
incompatible`). Pin an older compatible version with
`gitrinth add <slug>@<version>`, or remove the conflicting existing
mod first.

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

### `override`

Add a sticky [`project_overrides`](mods-yaml.md#project_overrides)
entry. Override semantics differ from
[`add`](#add): the resolver pins the chosen version regardless of
constraints from other mods on the slug, and silently drops
`incompatible:` edges that touch the slug in either direction. Use
`override` to bypass a `gitrinth:disabled-by-conflict` marker when you
want a particular mod in the pack despite a declared incompatibility.

```text
gitrinth override <slug>[@<constraint>] [arguments]
```

| Option | Description |
|--------|-------------|
| `--env client\|server\|both` | Restrict the override to a side. |
| `--url <url>` | Use a `url:` source. |
| `--path <path>` | Use a `path:` source. |
| `--type mod\|resourcepack\|datapack\|shader` | Force the section used for loader filtering. Useful when the slug is purely transitive and section inference is wrong. |
| `--accepts-mc <mc-version>` | Additively widen the Minecraft version filter for this override (repeatable). |
| `--exact` | Caret-pin including build metadata. |
| `--pin` | Bare-version pin. |
| `--standalone` | Write to `project_overrides.yaml` instead of `mods.yaml`. Creates the file if it doesn't exist. |
| `--dry-run` | Report what would change without writing or resolving. |
| `--offline` | Skip Modrinth queries; use the cache only. |

With no `@<constraint>`, `override` picks the latest release matching
loader and `mc-version`. The override version is sticky — other mods'
constraints on the same slug are silently ignored.

`override` does **not** run the incompatibility-prevention check
[`add`](#add) applies. That's deliberate: bypassing an incompatibility
is the most common reason to reach for an override.

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
gitrinth create [--mod-loader <loader[:tag]>]
                [--plugin-loader <loader[:tag]>]
                [--mc-version <version>] [--slug <slug>] [--name <name>]
                [--force] [--offline] <directory>
```

(`--offline` here is the create-specific form: it skips the Modrinth
slug-availability round-trip; the cache is not consulted because
`create` does not resolve any entries.)

[`slug`](mods-yaml.md#slug) defaults to the basename of `<directory>`,
lower-cased. [`name`](mods-yaml.md#name) defaults to the slug. The
slug must be 3–64 characters from Modrinth's allowed set
(`a-zA-Z0-9!@$()` `` ` `` `.+,_"-`); pass `--slug` to override the
derived value.

| Option            | Description                                                                                                 |
|-------------------|-------------------------------------------------------------------------------------------------------------|
| `--mod-loader`   | Pre-fill [`loader.mods`](mods-yaml.md#loader). Defaults to `neoforge` when no plugin loader is specified.   |
| `--plugin-loader` | Pre-fill [`loader.plugins`](mods-yaml.md#plugin-loaders). Omit `--mod-loader` for a plugin-only scaffold. |
| `--mc-version`    | Pre-fill [`mc-version`](mods-yaml.md#mc-version). Defaults to `1.21.1`.                                     |
| `--slug`          | Override the derived slug.                                                                                  |
| `--name`          | Override the display [`name`](mods-yaml.md#name).                                                           |
| `--force`         | Allow scaffolding into a non-empty directory; overwrites existing `mods.yaml`.                              |
| `--offline`       | Skip the Modrinth slug-availability check.                                                                  |

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
gitrinth build [<client|server|both>] [--output <path>]
              [--clean] [--skip-download] [--no-prune]
              [--java <path>] [--no-managed-java] [--offline]
```

The optional positional argument selects which environment to build.
Omit it (or pass `both`) to build client and server together.

| Option              | Description                                                                                            |
|---------------------|--------------------------------------------------------------------------------------------------------|
| `--output`, `-o`    | Override the output directory. Defaults to `./build`.                                                  |
| `--clean`           | Remove the output directory before building.                                                           |
| `--skip-download`   | Fail rather than fetch missing artifacts.                                                              |
| `--no-prune`        | Skip deleting obsolete files left over from a previous build. The new state ledger is still written.   |
| `--java`            | `java` binary or JDK home. See [Java runtime selection](#java-runtime-selection).                      |
| `--no-managed-java` | Refuse the auto-download fallback. Requires `--java` or a satisfying JAVA_HOME / PATH-`java`.          |
| `--offline`         | Use cached versions only; do not hit the network. Resolution narrows to versions already in the cache. |

Partitioning follows
[`environment`](mods-yaml.md#per-mod-environment): default `both`;
shaders are client-only; [`plugins`](mods-yaml.md#plugins) are
server-only. Under `bukkit` / `folia` / `paper` / `spigot`, or
under `sponge` resolved to SpongeVanilla,
[`mods`](mods-yaml.md#mods) are forced client-only; under `sponge`
resolved to SpongeForge / SpongeNeo (i.e. `loader.mods` is `forge` or
`neoforge`), mods keep their declared per-side state because those
server distributions run Forge / NeoForge mods alongside plugins.
[`resource_packs`](mods-yaml.md#resource_packs) and
[`data_packs`](mods-yaml.md#data_packs) partition normally under
every plugin loader. See
[Plugin loaders](mods-yaml.md#plugin-loaders).

When `loader.plugins` is set, `gitrinth build server` fetches the
matching plugin server jar instead of the Forge / NeoForge / Fabric
installer: Paper / Folia from the PaperMC API, the resolved Sponge
distribution (SpongeForge / SpongeNeo / SpongeVanilla) from the
SpongePowered downloads API, and Spigot / Bukkit by running
SpigotMC's `BuildTools.jar` locally on first build (requires `git`
and Java; takes several minutes; result is cached for re-use).
Plugin loader tags in `mods.yaml` are resolved during `get` and stored
concretely in `mods.lock`; changing the tag changes the cached server
binary path and install marker.

When neither `loader.plugins` nor a real `loader.mods` is declared
(pure-vanilla pack), `gitrinth build server` downloads the official
Mojang `server.jar` for the pack's `mc-version` from
`piston-meta.mojang.com`.

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
`project_overrides.yaml` untouched (they are source-controlled inputs)
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
                       [--output <path>] [--java <path>] [--no-managed-java]
                       [--offline] [-- <extra args>]
```

| Option              | Description                                                                                            |
|---------------------|--------------------------------------------------------------------------------------------------------|
| `--accept-eula`     | Write `eula=true` into `build/server/eula.txt` before starting. You agree to the Mojang EULA.          |
| `--no-build`        | Skip the implicit `gitrinth build server`. Use when the build tree is already up to date.              |
| `--memory`, `-m`    | JVM heap size, applied as `-Xmx`/`-Xms`. Examples: `2G`, `4G`, `6144M`. Defaults to `2G`.              |
| `--output`, `-o`    | Override the build output directory. Defaults to `./build`.                                            |
| `--java`            | `java` binary or JDK home. See [Java runtime selection](#java-runtime-selection).                      |
| `--no-managed-java` | Refuse the auto-download fallback. Requires `--java` or a satisfying JAVA_HOME / PATH-`java`.          |
| `--offline`         | Forwarded to the auto-build step and to the JDK auto-download fallback (both refuse network).          |
| `-- <args>`         | Trailing args after `--` are appended to the server JVM/script invocation (e.g. `-- --port 25566`).    |

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
gitrinth launch client [--no-build] [--output <path>]
                       [--java <path>] [--no-managed-java] [--offline]
```

| Option              | Description                                                                                     |
|---------------------|-------------------------------------------------------------------------------------------------|
| `--no-build`        | Skip the implicit `gitrinth build client`. Use when the build tree is already up to date.       |
| `--output`, `-o`    | Override the build output directory. Defaults to `./build`.                                     |
| `--java`            | `java` binary or JDK home. See [Java runtime selection](#java-runtime-selection).               |
| `--no-managed-java` | Refuse the auto-download fallback. Requires `--java` or a satisfying JAVA_HOME / PATH-`java`.   |
| `--offline`         | Rejected — the launcher needs network on first run to download libraries and assets.            |

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

#### Java runtime selection

`launch server`, `launch client`, and `build server` all need a
JVM — the server's launch script, the loader installer, and the
Forge/NeoForge `--installServer` step. gitrinth picks one automatically
based on the modpack's `mc-version` so you don't have to install or
switch JDKs yourself.

##### Required JDK feature per Minecraft version

| MC version range                         | Required JDK feature |
|------------------------------------------|----------------------|
| `< 1.17`                                 | 8                    |
| `1.17 ≤ v < 1.18`                        | 16                   |
| `1.18 ≤ v < 1.20.5`                      | 17                   |
| `1.20.5 ≤ v < 26.1` (incl. 1.21.x, 26.0) | 21                   |
| `26.1 ≤ v`                               | 25                   |

(Mojang's year-based versioning lands major engine bumps in point
releases — MC 26.0 is still on Java 21, MC 26.1 is the first to need
Java 25. The table is hand-maintained; future bumps add a row.)

**Resolution chain.** The first source that satisfies the requirement
wins:

1. `--java <path>` — accepts a `java`/`java.exe` binary OR a JDK home
   directory. **Hard-fails** if the major version doesn't match — the
   resolver never silently overrides an explicit user choice.
2. `JAVA_HOME` — same probe. **Soft-fails** on version mismatch:
   logs a warning and falls through, so a stale system-wide JAVA_HOME
   doesn't block a correctly-flagged invocation. Under
   `--no-managed-java` (no auto-download escape hatch), the mismatch
   surfaces in the final remediation error.
3. **gitrinth-managed Temurin JDK** under
   `~/.gitrinth_cache/runtimes/temurin/<feature>/<os>-<arch>/`.
   Skips ahead of `PATH` because it's known-good and free (no
   `java -version` probe needed).
4. `PATH java` — the first `java[.exe]` on `PATH`. Soft-fail; falls
   through to the auto-download if the version doesn't match.
5. **Auto-download** Eclipse Temurin from the Adoptium API into the
   cache (~190 MB once per JDK feature version). Refused when
   `--no-managed-java` or `--offline` is set.
6. Nothing satisfies → `UserError` listing what was tried plus
   concrete remediation (`--java <path>`, drop `--offline`, install
   a JDK manually).

For Forge/NeoForge servers the chosen JDK's `bin/` is prepended to
`PATH` and `JAVA_HOME` is set for the spawned `run.bat`/`run.sh` —
the unmodified loader script picks up the right `java` without
patching.

**Air-gapped mirrors.** Override the metadata endpoint with
`GITRINTH_JAVA_METADATA_URL`. The placeholder shape is
`/<feature>/ga?architecture={arch}&os={os}&...`; point it at an
internal Adoptium-shaped redistributor when the public API isn't
reachable.

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

### `gitrinth modrinth login`

Store a Modrinth personal-access token (PAT) for the default server
(modrinth.com or `GITRINTH_MODRINTH_URL` if set) in the user config.
The token is validated against `GET /user` before being persisted —
an invalid token never lands on disk.

```text
gitrinth modrinth login [--token <pat>]
```

| Option         | Description                                                                                       |
|----------------|---------------------------------------------------------------------------------------------------|
| `--token <pat>`| Pass the PAT directly. Designed for headless / CI use; falls back to a hidden stdin prompt when omitted. The prompted form also accepts piped stdin (e.g. `echo $TOKEN | gitrinth modrinth login`). |

The PAT for `gitrinth modrinth publish` must include these labrinth
scopes: `USER_READ`, `PROJECT_READ`, `VERSION_CREATE`. Generate one
under *Account → Authorization* on Modrinth.

`GITRINTH_TOKEN`, when set, **overrides** the stored PAT for the
default host on every subsequent command — `login` warns when the
env var is set so the user knows the stored value will be masked.

On POSIX hosts the user config is written with mode `0600` so other
local users can't read stored tokens. On Windows ACLs are not
normalized; the file lives under the user's profile directory.

### `gitrinth modrinth logout`

Clear the stored PAT for the default server. *Does not* revoke the
token server-side — Modrinth's published auth API has no revocation
endpoint. Re-issue a new PAT and discard the old one in the
*Authorization* page if the token may have been exposed.

```text
gitrinth modrinth logout
```

### `gitrinth modrinth token`

Manage tokens for non-default Modrinth-compatible servers (a self-hosted
labrinth, a staging instance, etc.). Use `login` / `logout` for the
default server.

```text
gitrinth modrinth token add <server-url> [--token <pat>]
gitrinth modrinth token list
gitrinth modrinth token remove <server-url>
```

| Subcommand          | Description                                                                                  |
|---------------------|----------------------------------------------------------------------------------------------|
| `add <server-url>`  | Validate against `<server-url>/user` and store the PAT under the normalized URL key.         |
| `list`              | Print every stored host with its token masked (first / last 4 chars, middle elided).         |
| `remove <server-url>`| Clear the entry. Errors when no token is stored under that key.                              |

Server URLs are normalized to scheme + host + port + path before being
used as map keys, so `https://my.host/api` and `HTTPS://my.host/api/`
collapse to the same entry.

### `gitrinth modrinth publish`

Upload a built `.mrpack` as a new version on the resolved server.
Reads the artifact produced by [`pack`](#pack) (or the path given by
`--pack`), assembles the multipart payload, hashes the file locally
(sha1 + sha512), and POSTs to `/project/{slug}/version`.

```text
gitrinth modrinth publish [--dry-run] [--force] [--draft]
                          [--version-type <release|beta|alpha>]
                          [--changelog <path>] [--pack <path>]
```

| Option                         | Description                                                                                                                                |
|--------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| `--dry-run`                    | Hash the artifact and emit the JSON payload without uploading.                                                                             |
| `-f`, `--force`                | Skip the interactive `Publish <slug> v<version> to <host>? [y/N]` confirmation. Required when stdin is not a terminal.                     |
| `--draft`                      | Set `status: draft` instead of `status: listed` on the new version.                                                                        |
| `--version-type <channel>`     | Modrinth version channel. Defaults to `beta` when `mods.yaml.version` carries a pre-release suffix (e.g. `1.0.0-beta.2`), else `release`.  |
| `--changelog <path>`           | Markdown changelog. Defaults to the matching `## [<version>]` section of `CHANGELOG.md` in the project directory; absent → empty changelog.|
| `--pack <path>`                | Override the `.mrpack` location. Defaults to `build/<slug>-<version>.mrpack` (the path produced by `gitrinth pack`).                       |

The target server is resolved from `mods.yaml.publish_to` if set,
otherwise from `GITRINTH_MODRINTH_URL` / the built-in default. A
`publish_to: 'none'` disables publishing for the pack.

Authentication uses the same token resolution as the rest of the
CLI (`GITRINTH_TOKEN` → stored token for the resolved host). If
neither source has a token, `publish` exits with code `4` before
hitting the network.

### `completion`

Emit a shell-completion script for the given shell to stdout. No
filesystem writes — the user redirects or sources the output as they
prefer. See [Shell completion](#shell-completion) for per-shell install
snippets.

```text
gitrinth completion <bash|zsh|fish|powershell>
```

Covers subcommand names, flag names, and the enum values already
constrained on the argparse side (`--env`, `--mod-loader`,
`--plugin-loader`). Re-run after
upgrading `gitrinth` to refresh installed scripts.

## Working with project_overrides

`mods.yaml` supports a
[`project_overrides`](mods-yaml.md#project_overrides) section. Edit it
directly in the manifest, or use [`override`](#override) to add an
entry from the command line.

Overrides may also live in a standalone
[`project_overrides.yaml`](project-overrides-yaml.md) alongside
`mods.yaml` (`gitrinth override --standalone` writes there). Both are
merged during resolution, with `project_overrides.yaml` winning on
conflicting keys.

A `project_overrides` entry is **sticky**: the resolver pins it to
the supplied version (or the latest matching the supplied
constraint), then fits the rest of the graph around that decision.
Use it to bypass a `gitrinth:disabled-by-conflict` marker when you
want a particular mod in the pack despite a declared incompatibility.

## Exit codes

| Code | Meaning                                                                                |
|------|----------------------------------------------------------------------------------------|
| `0`  | Success.                                                                               |
| `1`  | Recoverable user-facing error.                                                         |
| `2`  | Validation or resolution failed.                                                       |
| `4`  | Authentication failure — no PAT configured, or upstream rejected the supplied token.   |
| `5`  | Cache corruption `cache repair` could not fix.                                         |
| `64` | Usage error — matches `sysexits.h` `EX_USAGE`.                                         |

## Environment variables

| Variable                                | Used by                  | Purpose                                                                                                                                                          |
|-----------------------------------------|--------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `GITRINTH_CACHE`                        | every command            | Override the cache root. Defaults to `<home>/.gitrinth/cache`.                                                                                                   |
| `GITRINTH_CONFIG`                       | every command            | Override the user config file path. `--config` wins.                                                                                                             |
| `GITRINTH_MODRINTH_URL`                 | every command            | Override the default Modrinth API base URL.                                                                                                                      |
| `GITRINTH_TOKEN`                        | every command            | Override the stored Modrinth PAT for the *default* host. Sent bare (no `Bearer` prefix) per the Modrinth auth doc. Other hosts always use the stored token.      |
| `HOME` / `USERPROFILE`                  | every command            | Resolves the default cache root and user config path. `USERPROFILE` on Windows; `HOME` elsewhere.                                                                |
| `JAVA_HOME`                             | `launch` / `build`       | Honored by the Java resolver if its major version matches the JDK required for the pack's `mc-version`.                                                          |
| `GITRINTH_JAVA_METADATA_URL`            | `launch` / `build`       | Override Adoptium metadata URL.                                                                                                                                  |
| `GITRINTH_FABRIC_META_URL`              | every command            | Override the fabric-meta loader-list URL.                                                                                                                        |
| `GITRINTH_FORGE_PROMOTIONS_URL`         | every command            | Override the Forge `promotions_slim.json` URL.                                                                                                                   |
| `GITRINTH_FORGE_VERSIONS_URL`           | every command            | Override the Forge `maven-metadata.json` URL.                                                                                                                    |
| `GITRINTH_FORGE_INSTALLER_URL`          | `build` / `launch`       | Override the Forge installer-jar URL template (`{mc}` / `{v}` placeholders).                                                                                     |
| `GITRINTH_NEOFORGE_VERSIONS_URL`        | every command            | Override the modern NeoForge versions endpoint (MC ≥ 1.20.2).                                                                                                    |
| `GITRINTH_NEOFORGE_LEGACY_VERSIONS_URL` | every command            | Override the legacy NeoForge versions endpoint (MC 1.20.1).                                                                                                      |
| `GITRINTH_NEOFORGE_INSTALLER_URL`       | `build` / `launch`       | Override the modern NeoForge installer-jar URL template.                                                                                                         |
| `GITRINTH_NEOFORGE_LEGACY_INSTALLER_URL`| `build` / `launch`       | Override the legacy NeoForge installer-jar URL template.                                                                                                         |
| `GITRINTH_LAUNCHER`                     | `launch client`          | Absolute path to the Minecraft Launcher executable; bypasses per-OS search.                                                                                      |
| `GITRINTH_LAUNCHER_SEARCH_PATHS`        | `launch client`          | Custom search paths for the Minecraft Launcher (`;`-separated on Windows, `:`-separated elsewhere). Tried before the per-OS defaults.                            |
| `NO_COLOR`                              | every command            | Disable ANSI colour. `--color` overrides; `--no-color` matches.                                                                                                  |
| `HTTPS_PROXY` / `HTTP_PROXY`            | every command            | Standard proxy variables, honoured by every HTTP request.                                                                                                        |

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
| `./project_overrides.yaml`        | Optional standalone overrides. See [`project_overrides.yaml`](project-overrides-yaml.md). |
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
- [`project_overrides.yaml` reference](project-overrides-yaml.md) —
  optional standalone overrides file.
- [`mods.schema.yaml`](../assets/schema/mods.schema.yaml) and
  [`project-overrides.schema.yaml`](../assets/schema/project-overrides.schema.yaml) —
  machine-readable schemas editors can wire up for in-file validation.
- [`todo.md`](todo.md) — planned improvements and deferred CLI surface.
- [Modrinth API docs](https://docs.modrinth.com) — upstream service.
