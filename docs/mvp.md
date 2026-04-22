# `gitrinth` MVP

Minimal feature set for a first usable release. Each item links to
its full spec in [`cli.md`](cli.md). Anything not listed here is
deferred post-MVP.

## Commands

- [`create`](cli.md#create) — scaffold a new modpack.
- [`get`](cli.md#get) — resolve `mods.yaml`, write `mods.lock`, download artifacts.
- [`add`](cli.md#add) — add an entry to a section.
- [`remove`](cli.md#remove) — remove an entry.
- [`build`](cli.md#build) — assemble client and server distributions.
- [`pack`](cli.md#pack) — produce a `.mrpack` artifact.

## Global options

- [`-h`, `--help`](cli.md#global-options)
- [`--version`](cli.md#global-options)
- [`-C`, `--directory`](cli.md#global-options)
- [`-v`, `--verbose`](cli.md#global-options)

## Files

- [`mods.yaml`](cli.md#files)
- [`mods.lock`](cli.md#files)
- [`build/`](cli.md#files)
- [Cache root](cli.md#files)

## Exit codes

- [`0`, `1`, `2`, `64`](cli.md#exit-codes)

## Deferred

See [`cli.md`](cli.md) for the full surface. Deferred groups:
[publishing](cli.md#publishing), [cache management](cli.md#cache),
[`upgrade`](cli.md#upgrade), [`downgrade`](cli.md#downgrade),
[`outdated`](cli.md#outdated), [`deps`](cli.md#deps), and
[`unpack`](cli.md#unpack).
