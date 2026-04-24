# `gitrinth` MVP

Minimal feature set for a first usable release. Each command links to
its full spec in [`cli.md`](cli.md). Flags and arguments listed here
are in scope for the MVP; anything else from `cli.md` is deferred
post-MVP.

## Status

Scaffolding:

- [x] `CommandRunner` with all seven MVP commands registered.
- [x] Global options (`-h`, `--help`, `--version`, `-C`, `-v`).
- [x] Exit-code mapping (`0`/`1`/`2`/`64`) via `GitrinthException` hierarchy.

Commands:

- [x] `create` — fully implemented.
- [x] `get` — fully implemented.
- [x] `add` — fully implemented.
- [x] `remove` — fully implemented.
- [x] `build` — implemented; server-binary auto-download deferred.
- [x] `clean` — fully implemented.
- [ ] `pack` — stub; exits `1`.

Supporting work:

- [x] `mods.yaml` read/write — done.
- [x] Modrinth API client (version lookup; project-validity check still deferred).
- [x] Resolver and `mods.lock` format.
- [x] Artifact cache (platform cache root, hash-verified download).
- [ ] `.mrpack` archive builder.

Deferred work:

- [ ] Modrinth slug-validity check in `create` (currently deferred).
- [ ] Hosted source support (deferred pending `hosted:` source spec and `token` command).
- [ ] Plugin-loader support (deferred pending plugin-loader spec and `plugins` section spec).
- [ ] Global options: `-q`/`--quiet`, `--offline`, `--no-color`, `--config` (deferred pending `--config` spec).
- [ ] Commands deferred post-MVP: `upgrade`, `downgrade`, `outdated`, `deps`, `unpack`, `cache`.
- [ ] Modrinth Pack support loose files override, such as configs
- [ ] `build` auto-downloads the matching server binary for `loader.mods` + `mc-version` (users currently supply it manually).

## Release channels

Each entry in `mods.yaml` may declare a release-channel floor as either
the shorthand scalar form (`some-mod: beta`) or the long form
(`channel: beta` alongside `version:`). The floor is inclusive — `beta`
admits `release` + `beta`, `alpha` admits all three. When no channel is
declared on an entry, every Modrinth `version_type` is admitted (same as
`alpha`); add `channel: release` to a single entry if you want to
exclude betas/alphas for that mod only.

## Commands

### [`create`](cli.md#create)

Scaffold a new modpack.

```text
gitrinth create [--loader <loader>] [--mc-version <version>]
                [--slug <slug>] [--name <name>] [--force]
                <directory>
```

- `<directory>` — target directory (required).
- `--loader <loader>` — pre-fills `loader.mods` in the scaffolded
  `mods.yaml`. Defaults to `neoforge`. `loader.shaders` is added by hand
  once the pack has shader entries.
- `--mc-version <version>` — defaults to `1.21.1`.
- `--slug <slug>`
- `--name <name>`
- `--force`

### [`get`](cli.md#get)

Resolve `mods.yaml`, write `mods.lock`, download artifacts.

```text
gitrinth get [--dry-run] [--enforce-lockfile]
```

- `--dry-run`
- `--enforce-lockfile`

### [`add`](cli.md#add)

Add an entry to a section.

```text
gitrinth add <slug>[@<constraint>] [--env <client|server|both>]
            [--url <url> | --path <path>] [--dry-run]
```

- `<slug>[@<constraint>]` — required.
- `--env <client|server|both>`
- `--url <url>`
- `--path <path>`
- `--dry-run`

`--hosted` is deferred with the [`hosted:` source](#sources).

### [`remove`](cli.md#remove)

Remove an entry.

```text
gitrinth remove <slug> [--dry-run]
```

- `<slug>` — required.
- `--dry-run`

### [`build`](cli.md#build)

Assemble client and/or server distributions into `build/`.

```text
gitrinth build [--env <client|server|both>] [--output <path>]
              [--clean] [--skip-download]
```

- `--env <client|server|both>`
- `--output <path>`, `-o`
- `--clean`
- `--skip-download`

### [`clean`](cli.md#clean)

Delete every file `gitrinth` generates — `mods.lock`, the build
output directory, and the default `.mrpack` artifact.

```text
gitrinth clean [--output <path>]
```

- `--output <path>`, `-o`

### [`pack`](cli.md#pack)

Produce a `.mrpack` artifact.

```text
gitrinth pack [--output <path>]
```

- `--output <path>`, `-o`

## Global options

- `-h`, `--help`
- `--version`
- `-C`, `--directory <path>`
- `-v`, `--verbose`

Deferred: `-q`/`--quiet`, `--offline`, `--no-color`, `--config`.

## Loaders

`loader` is an object keyed by section. In the MVP:

- `loader.mods` (required) — one of `forge`, `fabric`, `neoforge`.
  Plugin loaders (`bukkit`, `folia`, `paper`, `spigot`) and `sponge`
  are deferred.
- `loader.shaders` (required when `shaders:` has entries) — one of
  `iris`, `optifine`, `canvas`, `vanilla`.
- `loader.plugins` — deferred with plugin support.

`resource_packs` and `data_packs` each have a single valid Modrinth
loader (`minecraft`, `datapack`) and are never declared under `loader`.

## Sources

Only the default Modrinth instance, `url:`, and `path:`. The
[`hosted:`](cli.md#token) source for alternate Modrinth-compatible
servers is deferred.

## Files

- [`mods.yaml`](cli.md#files)
- [`mods.lock`](cli.md#files)
- [`build/`](cli.md#files)
- [Cache root](cli.md#files)

## Exit codes

- [`0`, `1`, `2`, `64`](cli.md#exit-codes)

## Deferred

See [`cli.md`](cli.md) for the full surface. Deferred groups:
[publishing](cli.md#publishing) (including the `hosted:` source and
[`token`](cli.md#token) command), [cache management](cli.md#cache),
[`upgrade`](cli.md#upgrade), [`downgrade`](cli.md#downgrade),
[`outdated`](cli.md#outdated), [`deps`](cli.md#deps),
[`unpack`](cli.md#unpack), plugin loaders (and the
[`plugins`](mods-yaml.md#plugins) section they ship), and the `sponge`
loader.
