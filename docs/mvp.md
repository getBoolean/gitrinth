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
- [x] `pack` — implemented; emits a separate client + server `.mrpack` by default (use `--combined` for a single artifact); routes url/path artifacts into `overrides/` / `client-overrides/` / `server-overrides/` by env; `--publishable` refuses url/path mods (other sections still allowed). Recommended server installer: [mrpack-install](https://github.com/nothub/mrpack-install).

Supporting work:

- [x] `mods.yaml` read/write — done.
- [x] Modrinth API client (version lookup; project-validity check still deferred).
- [x] Resolver and `mods.lock` format.
- [x] Artifact cache (platform cache root, hash-verified download).
- [x] `.mrpack` archive builder.

Post-MVP work is tracked in [`todo.md`](todo.md).

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

Produce Modrinth `.mrpack` artifacts. By default emits a client pack at
`./build/<slug>-<version>.mrpack` plus a server pack at
`./build/<slug>-<version>-server.mrpack`, partitioned by each entry's
[`environment`](#release-channels). Install the server pack with
[mrpack-install](https://github.com/nothub/mrpack-install).

```text
gitrinth pack [--output <path>] [--combined] [--publishable]
```

- `--output <path>`, `-o` — base path; the server pack is derived by
  inserting `-server` before the `.mrpack` extension.
- `--combined` — produce a single `.mrpack` containing both client and
  server files (the older single-artifact behavior).
- `--publishable` — refuse to pack if any **mod** uses a `url:` or
  `path:` source. Resource packs, data packs, and shaders may still
  bundle non-Modrinth artifacts (Modrinth's permission policy targets
  executable code only). Without this flag, url/path artifacts are
  packed as loose files under `overrides/<subdir>/<filename>` (routed
  to `client-overrides/` / `server-overrides/` by env).

## Global options

- `-h`, `--help`
- `--version`
- `-C`, `--directory <path>`
- `-v`, `--verbose`

## Loaders

`loader` is an object keyed by section. In the MVP:

- `loader.mods` (required) — one of `forge`, `fabric`, `neoforge`.
- `loader.shaders` (required when `shaders:` has entries) — one of
  `iris`, `optifine`, `canvas`, `vanilla`.

`resource_packs` and `data_packs` each have a single valid Modrinth
loader (`minecraft`, `datapack`) and are never declared under `loader`.

## Sources

Only the default Modrinth instance, `url:`, and `path:`.

## Files

- [`mods.yaml`](cli.md#files)
- [`mods.lock`](cli.md#files)
- [`build/`](cli.md#files)
- [Cache root](cli.md#files)

## Exit codes

- [`0`, `1`, `2`, `64`](cli.md#exit-codes)
