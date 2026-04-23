# `gitrinth` MVP

Minimal feature set for a first usable release. Each command links to
its full spec in [`cli.md`](cli.md). Flags and arguments listed here
are in scope for the MVP; anything else from `cli.md` is deferred
post-MVP.

## Commands

### [`create`](cli.md#create)

Scaffold a new modpack.

```text
gitrinth create [--loader <loader>] [--mc-version <version>]
                [--slug <slug>] [--name <name>] [--force]
                <directory>
```

- `<directory>` — target directory (required).
- `--loader <loader>` — defaults to `neoforge`.
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

Only `forge`, `fabric`, and `neoforge`. The plugin loaders (`bukkit`,
`folia`, `paper`, `spigot`) and `sponge` are deferred.

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
