# `gitrinth` planned improvements

Post-MVP work. Tracks planned improvements sourced from a comparison
against [packwiz](https://github.com/packwiz/packwiz) plus deferred
MVP work previously tracked in [`mvp.md`](mvp.md). Each item has a
detailed spec further down.

## Status

Planned improvements:

- [x] [`accepts-mc` — per-entry MC version tolerance](#accepts-mc--per-entry-mc-version-tolerance)
- [x] [`migrate` command](#migrate-command)
- [x] [Optional mods](#optional-mods)
- [x] [`pin` / `unpin` commands](#pin--unpin-commands)
- [x] [Shell completion](#shell-completion)
- [x] [`add` writes caret semver constraints](#add-writes-caret-semver-constraints-by-default)
- [ ] [CurseForge bridge](curseforge-bridge.md)
- [x] [Modrinth API rate-limit handling](#modrinth-api-rate-limit-handling)
- [x] Add plugin loader flag to `create` command, mod loader becomes optional in `create` (e.g. for data packs or resource packs)
- [x] Allow specifying plugin loader version

Deferred MVP work:

- [x] [Modrinth slug-validity check in `create`](#modrinth-slug-validity-check-in-create)
- [ ] [Hosted source support](curseforge-bridge.md#hosted-modrinth-labrinth)
- [x] [Plugin-loader support](#plugin-loader-support)
- [x] [Global options: `-q`/`--quiet`, `--no-color`, `--config`](#deferred-global-options) (`--offline` shipped per-command)
- [x] [Loose-files override support in `.mrpack`](#loose-files-override-support)
- [x] [`build` auto-downloads server binary](#build-auto-downloads-server-binary)
- [x] [Automatic `:stable` / `:latest` loader tag resolution](#automatic-stable--latest-loader-tag-resolution)
- [x] [Auto-fetch JDK matching `mc-version`](#auto-fetch-jdk-matching-mc-version)
- [x] [`downgrade` command](#downgrade-command)
- [x] [`outdated` command](#outdated-command)
- [x] [`deps` command](#deps-command)
- [x] `modrinth` scoped commands:
  - [x] [`publish` command](#publish-command)
  - [x] [`login` / `logout` commands](#login--logout-commands)
  - [x] [`token` command](#token-command)
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

Shipped. See [`migrate`](cli.md#migrate) in the CLI docs. Bumps
`mc-version` or `loader.mods` and re-resolves every entry, always
crossing caret boundaries.

```text
gitrinth migrate mc <version>
gitrinth migrate loader <loader>[:<tag>]
```

Soft-fail policy (departure from the original spec): when a mod has no
version published for the new target, its `version:` is rewritten to
`gitrinth:not-found` and the entry is omitted from the lock. Other
fields are preserved, [`get`](cli.md#get) and [`upgrade`](cli.md#upgrade)
skip marker entries, and a later `migrate` that finds a compatible
version rewrites the marker to `^<resolved>`.

Graph-conflict failures on `migrate` take a parallel soft-fail path:
every user-declared mod implicated in the conflict gets a
`gitrinth:disabled-by-conflict` marker, the shrunk pack is re-resolved
into a fresh `mods.lock`, and the command exits 0 with a warning. A
*cascading* conflict — disabling all conflict roots still leaves the
graph unsatisfiable — rolls back and exits non-zero.

[`upgrade --major-versions`](cli.md#upgrade) recovers existing markers
when the conflict is resolved upstream by relaxing the marker's
constraint to `any` and rewriting it to `^<resolved>` on success.
[`add`](cli.md#add) refuses when the new mod and an existing user mod
declare each other incompatible (Modrinth `dependency_type:
incompatible`). Cross-major `version_id` pins on a shared transitive
resolve to the higher floor.

Touches: [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart),
[`lib/src/commands/migrate_command.dart`](../lib/src/commands/migrate_command.dart),
[`lib/src/commands/migrate_editor.dart`](../lib/src/commands/migrate_editor.dart),
[`lib/src/commands/caret_rewriter.dart`](../lib/src/commands/caret_rewriter.dart)
(extracted from `upgrade_command.dart`),
[`lib/src/model/resolver/constraint.dart`](../lib/src/model/resolver/constraint.dart),
[`lib/src/model/resolver/resolver.dart`](../lib/src/model/resolver/resolver.dart),
[`lib/src/service/resolve_and_sync.dart`](../lib/src/service/resolve_and_sync.dart),
[`cli.md`](cli.md), [`mods-yaml.md`](mods-yaml.md).

## Optional mods

Shipped. See [Optional mods](mods-yaml.md#optional-mods) in the
mods.yaml docs. Per-entry `optional: true` flag that survives `.mrpack`
export so the Modrinth app and Prism present a user-facing toggle.
Complements the existing `environment` field; preserves through the
env-split path (an optional client mod stays optional in the client
`.mrpack`).

```yaml
mods:
  distanthorizons:
    version: beta
    optional: true
```

Implemented as a flat boolean rather than the originally sketched
`optional: { default, description }` block — the Modrinth pack format
has no fields for default-state or description (packwiz drops both on
mrpack export too), so storing them gitrinth-side without a consumer
would have been inert metadata. We can introduce a structured block
later if a consumer appears.

## `pin` / `unpin` commands

Shipped. See [`pin`](cli.md#pin) and [`unpin`](cli.md#unpin) in the CLI
docs. Implemented as a syntactic toggle over the caret on the locked
bare `major.minor.patch`: `pin` strips the caret, `unpin` re-adds it.
No pre-pin constraint is stored — `unpin` is not lossless against
arbitrary prior constraints (e.g. `release` or `^1.0.0` becomes
`^<locked-bare>`). YAML formatting and comments are preserved via
`package:yaml_edit`. `--type` disambiguates when a slug exists in
multiple sections. A [`--pin` flag on `add`](cli.md#add) writes the
bare semver directly.

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

Shipped. See [`create`](cli.md#create) in the CLI docs. Before
scaffolding, [`create`](cli.md#create) hits Modrinth's
[`/project/<slug>/check`](https://docs.modrinth.com/api/operations/checkprojectvalidity/)
endpoint. If the slug is already taken (200), `create` warns and
proceeds anyway — users can rename later or rerun with `--slug`.
Network failures degrade to a warning so offline scaffolding still
works; pass `--offline` to skip the round-trip.

The local slug regex was loosened to mirror Modrinth's own
`RE_URL_SAFE` + length 3–64, so any slug accepted locally is also
accepted by Modrinth's project-create endpoint. Malformed slugs still
fail locally with `ValidationError` (exit 2) — that's the
"refuses to run" half of the original ticket. Collisions are
warn-only rather than hard errors because the user can rename later
and a wrong server-side reading shouldn't block scaffolding.

## Hosted source support

Folded into [CurseForge bridge](curseforge-bridge.md#hosted-modrinth-labrinth).
Hosted Modrinth (labrinth) is treated there as a Modrinth-host
override (`modrinth-host: <url>`, replacing the previously
schema-defined `hosted:` field) rather than a separate source kind,
since both share the resolver multi-host refactor and the token
store. The bridge doc tracks it as a separate sub-item so it can
land independently of the CF API client.

## Plugin-loader support

Shipped. `loader.plugins` now accepts `bukkit`, `folia`, `paper`,
`spigot`, `spongeforge`, `spongeneo`, and `spongevanilla`; the
`plugins:` section routes through the parser, lock builder,
build/pack assemblers, and Modrinth filters. Under
`bukkit`/`folia`/`paper`/`spigot`/`spongevanilla` mods are coerced
to server-unsupported; under `spongeforge` / `spongeneo` mods keep
their per-side state. `gitrinth build server` fetches the matching
server jar — Paper / Folia from the PaperMC API, the three Sponge
variants from the SpongePowered downloads API, and Spigot / Bukkit
by running SpigotMC's `BuildTools.jar` locally on first build.

## Deferred global options

Shipped. See [Global options](cli.md#global-options) in the CLI docs.
Top-level flags on `gitrinth`:

| Option                   | Description                                                                      |
|--------------------------|----------------------------------------------------------------------------------|
| `--verbosity <level>`    | Set the output floor (`error` / `warning` / `normal` / `io` / `solver` / `all`). |
| `-v`, `--verbose`        | Shorthand for `--verbosity=all`.                                                 |
| `-q`, `--quiet`          | Shorthand for `--verbosity=warning`.                                             |
| `--color` / `--no-color` | Force ANSI colour on or off. Defaults to auto-detection (honours `NO_COLOR`).    |
| `--config <path>`        | Use an alternate user config file.                                               |

`--verbosity` defines a totally-ordered set of output categories;
each call site files its message at a category and the chosen floor
decides what prints. See
[Verbosity levels](cli.md#verbosity-levels) for what each level adds.
`--color`/`--no-color` ships as a negatable pair. `--config` is
gitrinth-specific. Top-level placement matches the global-flag shape.

`--offline` shipped per-command (on every command that hits HTTP) rather
than as a global flag, to match `dart pub`'s shape — `dart pub` exposes
`--offline` on each resolution-style command (`get`, `upgrade`,
`downgrade`, `add`, `remove`) rather than as a top-level flag. See
[`get`](cli.md#get), [`upgrade`](cli.md#upgrade), [`add`](cli.md#add),
[`remove`](cli.md#remove), [`build`](cli.md#build), [`pack`](cli.md#pack),
[`create`](cli.md#create), and the [Offline mode](cli.md#offline-mode)
overview.

`--config` implies a companion `GITRINTH_CONFIG` environment variable
and a platform user-config location at `<home>/.gitrinth/config.yaml`
(where stored tokens will live — see
[`login` / `logout`](#login--logout-commands) and
[`token`](#token-command)). Resolution precedence:
`--config` > `GITRINTH_CONFIG` > platform default. The file is created
lazily on first write; no command reads from it yet.

Touches: [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart),
[`lib/src/service/console.dart`](../lib/src/service/console.dart),
[`lib/src/cli/base_command.dart`](../lib/src/cli/base_command.dart),
[`lib/src/app/runner_settings.dart`](../lib/src/app/runner_settings.dart),
[`lib/src/app/providers.dart`](../lib/src/app/providers.dart),
[`lib/src/service/user_config.dart`](../lib/src/service/user_config.dart),
[`cli.md`](cli.md).

## Loose-files override support

Shipped. The new top-level [`files:`](mods-yaml.md#files) section in
`mods.yaml` declares loose files (configs, scripts, vanilla
`options.txt`, etc.) keyed by destination path. Both pipelines now
honor it:

- [`build`](cli.md#build) copies each `files:` entry to its
  destination under `build/<env>/`. A side-car ledger at
  `build/<env>/.gitrinth-state.yaml` tracks every managed path so
  re-runs prune obsolete files without touching loose user files.
  Per-entry `preserve: true` skips overwriting an existing
  destination — first-install-only behavior so user edits to
  configs survive rebuilds (preserve is **not** sticky against
  removal from the manifest).
- [`pack`](cli.md#pack) bundles each `files:` entry into the
  appropriate `.mrpack` overrides root (`overrides/`,
  `client-overrides/`, `server-overrides/`) based on per-side state.
  Loose configs do not trip `--publishable`.

The prune pass mirrors packwiz-installer's two-layer model:
authored state in `mods.yaml` + `mods.lock`, consumer-side ledger
records "what was installed and where," prune by ledger membership.

A new `--no-prune` flag on `build` skips obsolete-file deletion as a
debug escape hatch.

`optional` is reserved on `files:` entries in v1 — Modrinth's
`.mrpack` overrides tree has no env/toggle metadata, and `build` has
no UI toggle, so the flag would have no observable effect. The
reservation will lift once a real consumer-side toggle materializes.

Touches: [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml),
[`lib/src/model/manifest/file_entry.dart`](../lib/src/model/manifest/file_entry.dart),
[`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart),
[`lib/src/model/manifest/mods_lock.dart`](../lib/src/model/manifest/mods_lock.dart),
[`lib/src/model/manifest/parser.dart`](../lib/src/model/manifest/parser.dart),
[`lib/src/model/manifest/emitter.dart`](../lib/src/model/manifest/emitter.dart),
[`lib/src/model/state/build_state.dart`](../lib/src/model/state/build_state.dart),
[`lib/src/service/resolve_and_sync.dart`](../lib/src/service/resolve_and_sync.dart),
[`lib/src/commands/build_command.dart`](../lib/src/commands/build_command.dart),
[`lib/src/commands/build_orchestrator.dart`](../lib/src/commands/build_orchestrator.dart),
[`lib/src/commands/build_pruner.dart`](../lib/src/commands/build_pruner.dart),
[`lib/src/commands/pack_assembler.dart`](../lib/src/commands/pack_assembler.dart),
[`mods-yaml.md`](mods-yaml.md), [`cli.md`](cli.md).

## `build` auto-downloads server binary

Shipped. [`build server`](cli.md#build) fetches the matching
server binary for [`loader.mods`](mods-yaml.md#loader) +
[`mc-version`](mods-yaml.md#mc-version) and lays out a runnable
`build/server/` tree without user intervention:

- Fabric — `meta.fabricmc.net/v2/versions/loader/<mc>/<v>/server/jar`,
  dropped in as `fabric-server-launch.jar`.
- Forge — installer JAR from `maven.minecraftforge.net`, run in
  `--installServer` mode against `build/server/`.
- NeoForge (modern, MC ≥ 1.20.2) — installer from
  `maven.neoforged.net/.../neoforge`, run in `--installServer` mode.
- NeoForge (legacy, MC 1.20.1) — installer from
  `maven.neoforged.net/.../forge` (legacy namespace).

Installer JARs are cached under
`<gitrinth-cache>/loaders/<loader>/<mc>/<v>/` so re-builds are
network-free. A sentinel marker (`.gitrinth-installed-<loader>-<v>` in
the build output) makes the install step idempotent. `--offline`
refuses to run the Forge/NeoForge installers (which themselves fetch
libraries) unless the marker already exists.

Touches:
[`lib/src/service/loader_binary_fetcher.dart`](../lib/src/service/loader_binary_fetcher.dart),
[`lib/src/service/server_installer.dart`](../lib/src/service/server_installer.dart),
[`lib/src/commands/build_orchestrator.dart`](../lib/src/commands/build_orchestrator.dart).

## Automatic `:stable` / `:latest` loader tag resolution

Shipped. [`loader.mods`](mods-yaml.md#loader) accepts a docker-image-style
tag: `<loader>:stable`, `<loader>:latest`, or a concrete version string.
Resolution targets:

- Fabric — `meta.fabricmc.net`
- Forge — `files.minecraftforge.net/.../promotions_slim.json` for
  `stable`/`latest`; `maven-metadata.json` for concrete-tag validation
- NeoForge (modern) — `maven.neoforged.net/api/maven/versions/.../neoforge`
- NeoForge (legacy MC 1.20.1) — `maven.neoforged.net/api/maven/versions/.../forge`

Concrete tags are also validated against the upstream version list, so
typos or pins for the wrong MC version fail at resolve time rather than
install time. The lock-file fast-path skips re-validation when the pin
is unchanged from the previous run; `--offline` skips validation entirely
and trusts the user's pin (with a stderr warning if it diverges from the
lock).

Touches:
[`lib/src/service/mod_loader_version_resolver.dart`](../lib/src/service/mod_loader_version_resolver.dart),
[`lib/src/service/resolve_and_sync.dart`](../lib/src/service/resolve_and_sync.dart).

## Auto-fetch JDK matching `mc-version`

Shipped. See [Java runtime selection](cli.md#java-runtime-selection) in
the CLI docs. `gitrinth launch server`, `launch client`, and
`build --env server` resolve a JDK that satisfies the modpack's
`mc-version` (1.20.5+ → 21, 1.21.x → 21, 26.1+ → 25, etc.) using a
five-step chain: `--java <path>` → `JAVA_HOME` → cached gitrinth
Temurin → `PATH java` → auto-download from Adoptium. `--java` and
`JAVA_HOME` hard-fail on version mismatch; `PATH` soft-falls; the
auto-download is refused under `--offline` or `--no-managed-java`.

For Forge/NeoForge servers the chosen JDK's `bin/` is prepended to
`PATH` and `JAVA_HOME` is set in the spawn environment, so the
unmodified `run.bat`/`run.sh` picks up the right `java` without
patching the loader's wrapper script.

Cache layout:
`~/.gitrinth_cache/runtimes/temurin/<feature>/<os>-<arch>/<jdk-dir>/`
with a `.gitrinth-installed-temurin-<full-version>` JSON sentinel for
inspector and prune integration.

Touches:
[`lib/src/util/host_platform.dart`](../lib/src/util/host_platform.dart),
[`lib/src/util/mc_version.dart`](../lib/src/util/mc_version.dart),
[`lib/src/service/cache.dart`](../lib/src/service/cache.dart),
[`lib/src/service/java_runtime_fetcher.dart`](../lib/src/service/java_runtime_fetcher.dart),
[`lib/src/service/java_runtime_resolver.dart`](../lib/src/service/java_runtime_resolver.dart),
[`lib/src/service/server_installer.dart`](../lib/src/service/server_installer.dart),
[`lib/src/service/loader_client_installer.dart`](../lib/src/service/loader_client_installer.dart),
[`lib/src/commands/launch_command.dart`](../lib/src/commands/launch_command.dart),
[`lib/src/commands/build_command.dart`](../lib/src/commands/build_command.dart),
[`lib/src/commands/build_orchestrator.dart`](../lib/src/commands/build_orchestrator.dart),
[`lib/src/app/providers.dart`](../lib/src/app/providers.dart).

## `downgrade` command

Shipped. See [`gitrinth downgrade`](cli.md#downgrade) in the CLI
reference. Resolves every Modrinth-source entry (or the named
subset) to the oldest version compatible with its constraint;
honors the entry's `channel` floor; supports `--dry-run` and
`--offline`. Implementation reuses the same resolver path as
`get`/`upgrade` via a `SolveType.downgrade` enum threaded through
`PubGrubSolver`.

## `outdated` command

Shipped. See [`gitrinth outdated`](cli.md#outdated) in the CLI
reference. Reports `Current` / `Upgradable` / `Latest` columns per
locked entry; supports `--json`, `--show-all`, `--no-transitive`,
and `--offline`. The report-only "Resolvable" column from
comparable tools is omitted in this version (would require a full
re-resolve under relaxed constraints).

## `deps` command

Shipped. See [`gitrinth deps`](cli.md#deps) in the CLI reference.
Walks `mods.lock` plus the cached per-version `version.json`
sidecars to render the dependency graph in `tree` (default),
`list`, or `compact` style. Supports `--env`, `--json`, and an
optional positional slug. Errors out when `mods.lock` is missing
or stale (run `gitrinth get` first); the in-memory-fallback
behavior described in the original spec is intentionally not
implemented — a "report" command should not silently mutate the
cache or hit the network.

## `publish` command

Shipped. See [`gitrinth modrinth publish`](cli.md#gitrinth-modrinth-publish).
Upload the modpack to Modrinth (or the server declared in
[`publish_to`](mods-yaml.md#publish_to)).

```text
gitrinth modrinth publish [--dry-run] [--force] [--draft]
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

The PAT used for publishing must carry these scopes (from
[labrinth's `pats.rs`](https://github.com/modrinth/code/blob/main/apps/labrinth/src/models/v3/pats.rs)):

| Scope            | Bit       | Required for                                      |
|------------------|-----------|---------------------------------------------------|
| `USER_READ`      | `1 << 1`  | `GET /user` (login validation)                    |
| `PROJECT_READ`   | `1 << 11` | resolving the project before upload               |
| `VERSION_CREATE` | `1 << 14` | `POST /project/{slug}/version` (the publish call) |

`VERSION_WRITE`, `VERSION_READ`, and `PROJECT_WRITE` are *not*
required by `publish` itself — leave them off for a tighter PAT.

## `login` / `logout` commands

Shipped. See [`gitrinth modrinth login`](cli.md#gitrinth-modrinth-login)
and [`gitrinth modrinth logout`](cli.md#gitrinth-modrinth-logout).
Store and clear a Modrinth personal-access token for the default
server (modrinth.com) in the user config. The token is never echoed
and can be piped over stdin or supplied via `--token`.

```text
gitrinth modrinth login
gitrinth modrinth logout
```

## `token` command

Shipped. See [`gitrinth modrinth token`](cli.md#gitrinth-modrinth-token).
Manage tokens for additional Modrinth-compatible servers — anything
other than modrinth.com. Use [`login` / `logout`](#login--logout-commands)
for the default server.

```text
gitrinth modrinth token add <server-url>
gitrinth modrinth token list
gitrinth modrinth token remove <server-url>
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
by `--modrinth-host` first) or a path to a local `.mrpack` file. Loose
override files from the archive are preserved inside the output
directory. Inverse of [`pack`](cli.md#pack).

```text
gitrinth unpack <slug>[:<version>] [--modrinth-host <url>]
               [--output <directory>] [--force] [--no-resolve]
gitrinth unpack <path>             [--output <directory>] [--force] [--no-resolve]
```

| Option                  | Description                                                                                                                                             |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| `<slug>`                | Modrinth project slug. Downloads the matching `.mrpack` before extracting.                                                                              |
| `<version>`             | Version constraint on the slug form. Defaults to the newest release on the resolved server.                                                             |
| `<path>`                | Path to a local `.mrpack` file. Skips the download step. Chosen when the positional resolves to a file on disk or ends in `.mrpack`.                    |
| `--modrinth-host <url>` | Fetch from a Modrinth-compatible server at `<url>`. Slug form only. Also written into the reconstructed `mods.yaml` as the pack-level `modrinth_host:`. |
| `--output`, `-o`        | Output directory. Defaults to the current directory.                                                                                                    |
| `--force`, `-f`         | Overwrite existing files in the output directory.                                                                                                       |
| `--no-resolve`          | Skip the implicit [`get`](cli.md#get) that normally runs after unpacking.                                                                               |

## Modrinth API rate-limit handling

Shipped. The Modrinth API caps clients at 300 requests/min/IP and
publishes the budget on every response via `X-Ratelimit-Limit`,
`X-Ratelimit-Remaining`, and `X-Ratelimit-Reset`. A Dio interceptor
scoped to the configured Modrinth host reads those headers on every
response, proactively delays outbound requests when the remaining
budget drops below 5, and on `429` sleeps for `Retry-After` (falling
back to `X-Ratelimit-Reset`, with a 1s floor) and retries up to 5
times before falling through to
[`ModrinthErrorInterceptor`](../lib/src/service/modrinth_error_interceptor.dart).
Sleeps are clamped to `[1s, 65s]`. Long waits (≥ 2s) emit a single
`Console.io` line at `--verbosity=io` and above; shorter waits stay silent.

Other upstreams (`meta.fabricmc.net`, `files.minecraftforge.net`,
`maven.neoforged.net`, Adoptium) flow through the same `Dio`
unchanged — none publish `X-Ratelimit-*` headers and none document a
per-IP cap, so the interceptor is a no-op for those hosts.

Touches:
[`lib/src/service/modrinth_rate_limit_interceptor.dart`](../lib/src/service/modrinth_rate_limit_interceptor.dart),
[`lib/src/app/providers.dart`](../lib/src/app/providers.dart).
