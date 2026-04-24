# CurseForge bridge

Support CurseForge as a first-class peer to Modrinth — pack authors
can source mods from either platform, mix them in one pack, and
publish to either (or both) as a target.

This document specifies the CurseForge bridge feature. See
[`todo.md`](todo.md) for the overall planned-improvements index; the
bridge lives there as a single checklist entry that points here.

## Fetching mods from CurseForge

Every entry resolves on **both Modrinth and CurseForge by default**.
Most mods share a slug across platforms, so short-form stays terse
and packs are cross-platform without ceremony:

```yaml
mods:
  # Default: both platforms; key is the slug on each (most common)
  jei: ^19.27.0
  create: ^6.0.10+mc1.21.1
  sodium: ^0.5.13

  # Slug differs on CurseForge — override CF side only
  fabric-api:
    curseforge: fabric-api-cf-slug        # CF-specific slug
    version: ^0.102.0

  # Restrict to Modrinth only (CF excluded explicitly)
  distanthorizons:
    sources: [modrinth]
    version: ^2.3.0

  # Restrict to CurseForge only (no Modrinth project exists)
  ae2:
    sources: [curseforge]
    curseforge: applied-energistics-2
    version: ^19.0.15

  # CF-only short form sugar
  appleskin: cf:appleskin@^3.0.9

  # Numeric CF project ID (valid in short and long form)
  journeymap: cf:32274@^6.0.0
```

```text
gitrinth add jei                          # resolves on both, if available
gitrinth add cf:applied-energistics-2     # CF-only
```

The `mods:` map key is a local identifier and defaults to the slug
on each platform in the resolution set. `modrinth:` and `curseforge:`
peer fields override that platform's slug when it differs.
`sources: [...]` explicitly restricts resolution to the listed
platforms — use it when a mod only exists on one side, or when you
want to pin an entry to one platform even though the other has it.

If a declared-or-defaulted platform doesn't have the mod, that
platform gets a `not_found` marker in `mods.lock` and a warning is
emitted; the entry still succeeds as long as at least one platform
resolves. [mods-yaml.md](mods-yaml.md) needs updating to reflect the
relaxed key semantics.

The resolver uses the same `loader` + `mc-version` filters (plus
per-entry [`accepts-mc`](todo.md#accepts-mc--per-entry-mc-version-tolerance))
and the same channel floor (`release`/`beta`/`alpha`) across
platforms. Downloads hit each platform's CDN. The CF API requires a
key, managed via [`token` add curseforge.com](todo.md#token-command).

## `add` command cross-platform behavior

`gitrinth add <slug>` resolves on both platforms by default and
writes the minimal entry that captures what it found. The resolved
form depends on which platforms have the mod and whether hashes
align:

| Situation                                       | Entry written                          | Notice                                                                                            |
|-------------------------------------------------|----------------------------------------|---------------------------------------------------------------------------------------------------|
| Both resolve, hashes match                      | Short form (`slug: ^x.y.z`)            | silent                                                                                            |
| Both resolve, scan finds an older matching pair | Short form (`slug: ^x.y.z`)            | prints chosen version and each platform's latest                                                  |
| Both resolve, scan exhausts without a match     | *(nothing written)*                    | fails with remediations + `--modrinth-only` / `--curseforge-only` / `--allow-hash-mismatch` flags |
| Only Modrinth has the mod                       | Long form with `sources: [modrinth]`   | prints one-sided resolution                                                                       |
| Only CurseForge has the mod                     | Long form with `sources: [curseforge]` | prints one-sided resolution                                                                       |
| Neither platform has the mod                    | *(nothing written)*                    | fails with not-found error                                                                        |

Long-form restrictions (`sources: [modrinth]` or `sources:
[curseforge]`) are only written when the resolver confirmed one
platform is unavailable at add time. This saves future `get` calls
from re-querying the missing platform and makes one-sided entries
visible in the manifest.

`add` CLI flags:

| Flag                    | Effect                                                                                      |
|-------------------------|---------------------------------------------------------------------------------------------|
| `--modrinth-only`       | Force `sources: [modrinth]` even when CF has the mod.                                       |
| `--curseforge-only`     | Force `sources: [curseforge]` even when Modrinth has the mod.                               |
| `--allow-hash-mismatch` | Accept divergent hashes on both platforms; writes `allow-hash-mismatch: true` on the entry. |

`cf:<slug>` short-form sugar (`gitrinth add cf:applied-energistics-2`)
implies `--curseforge-only` and writes a single-platform entry
without querying Modrinth.

## Cross-platform hash verification

When an entry resolves on both platforms, gitrinth fetches each
platform's SHA1 and compares. (SHA1 is the algorithm returned by
both Modrinth's and CurseForge's file APIs; Modrinth's SHA512 is
retained for single-platform tamper detection on download.) Matching
hashes lock silently.

On a mismatch, gitrinth scans older versions on both platforms within
the entry's version constraint, looking for a hash-matching pair.
This transparently recovers when one platform's CI ships a newer
build than the other for a brief window. When a match is found,
gitrinth locks that pair and prints which version was chosen (it
will be at or below the newest constraint-satisfying version). The
scan is bounded by the per-entry `hash-scan-depth:` field (default
`10`; `0` disables the scan entirely).

If the scan runs out of candidates without finding a match,
resolution **fails** with an error listing both current hashes,
slugs, and project IDs, and three remediations: accept the
divergence with `allow-hash-mismatch: true`, restrict to one platform
via `sources: [...]`, or pin different versions per platform to align
builds.

```yaml
mods:
  # Same file on both — clean lock
  jei: ^19.27.0

  # Modrinth and CF ship different builds of the same release
  # (different CI signing keys, etc.). User has verified these are
  # the same mod and accepts the divergence.
  create:
    version: ^6.0.10+mc1.21.1
    allow-hash-mismatch: true

  # Slug collision — 'ae2' names different mods on each platform.
  # Restrict rather than override; the mismatch is a real conflict.
  ae2:
    sources: [modrinth]
    version: ^19.0.15
```

The check runs on `add`, `get`, and `upgrade`. `mods.lock` always
stores per-platform hashes, and downstream downloads verify against
each platform's own hash, so `allow-hash-mismatch` does not disable
tamper detection — it only suppresses the cross-platform equality
check at resolution time.

`allow-hash-mismatch` and `hash-scan-depth` only make sense when two
or more platform sources are declared; setting either alongside
`sources: [modrinth]` or `sources: [curseforge]` is a schema error.
`allow-hash-mismatch: true` short-circuits the scan — no point
scanning when the user is explicitly accepting divergence.

## Transitive dependencies and deduplication

Transitive dependencies from either platform are cross-deduplicated
so a mod required by both a Modrinth and a CurseForge parent
resolves to one logical entry rather than two. The same hash
identity used by
[Cross-platform hash verification](#cross-platform-hash-verification)
drives the dedup.

### Slug-table index

After top-level entries resolve, gitrinth builds a slug-to-entry
index per platform:

```text
modrinth_slug_to_entry = { 'create' → create, 'sodium' → sodium, ... }
cf_slug_to_entry       = { 'create' → create, 'sodium-fabric' → sodium, ... }
```

When a transitive dep comes up during resolution, the resolver
checks this index before creating a synthetic entry:

- **Dep slug matches a top-level entry on the same platform** —
  reuse that top-level entry. The transitive version constraint is
  merged into the top-level's constraint; a conflict errors.
- **No match on that platform** — resolve the dep on both platforms
  (same default-both rules as `add`), build a synthetic entry,
  cross-check hashes, and lock.

### Cross-platform synthetic promotion

When one path requires `flywheel` from CF and another requires
`flywheel` from Modrinth, only one synthetic entry is created:

1. Resolve `flywheel` on both platforms within the merged version
   constraint.
2. Apply the same hash check as top-level entries — match →
   dual-source synthetic; mismatch → scan; scan-exhaust → error.
3. If only one platform has it, lock the synthetic as single-source
   with a `not_found` marker on the missing platform.

### Lockfile representation

Synthetic entries live in `mods.lock`, not `mods.yaml`. Each carries
a `required-by:` list so [`deps`](todo.md#deps-command) can show the
chain:

```yaml
# mods.lock (sketch)
mods:
  create:                          # top-level, user-declared
    version: 6.0.10
    modrinth: { ... }
    curseforge: { ... }

  flywheel:                        # transitive, synthetic
    version: 1.0.5
    required-by: [create]          # from both platforms' create
    modrinth: { ... }
    curseforge: { ... }

  fabric-api:                      # transitive, synthetic
    version: 0.102.0
    required-by: [create, sodium]
    modrinth: { ... }
    curseforge: { ... }
```

User-declared top-level entries shadow synthetics: if `flywheel`
appears in `mods.yaml`, it's treated as top-level; `required-by:`
still tracks transitives but the version constraint and source
restrictions come from `mods.yaml`.

### Slug collision on transitive path

Rare but real: two transitive deps independently produce synthetic
entries with the same slug but different hashes (they're actually
different mods). The resolver can't auto-pick and errors:

```text
error: transitive dependency name collision
  - CF's 'ae2' (required by some-cf-mod) at sha1 a1b2...
  - Modrinth's 'ae2' (required by some-modrinth-mod) at sha1 deadbeef...

These appear to be different mods sharing a slug. Declare an
explicit top-level entry for 'ae2' (or one of the two) with
`sources: [...]` to disambiguate.
```

### Scenarios

| Setup                                                                                                                                  | Resolution                                                                                  |
|----------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Top-level `create: ^6.0.10`; both platforms' `create` require `flywheel`; hashes match                                                 | One dual-source synthetic `flywheel` in lock                                                |
| Top-level `create: ^6.0.10` dual-source; top-level `flywheel: ^1.0.3` also declared                                                    | Top-level `flywheel` used as-is; transitive merged into its constraint; no synthetic        |
| Top-level `my-sodium: {modrinth: sodium, curseforge: sodium-fabric, version: ^0.5}`; a CF mod transitively requires CF `sodium-fabric` | Existing top-level `my-sodium` matched via the CF slug index; no synthetic                  |
| CF mod transitively requires CF `fabric-api`; Modrinth mod transitively requires Modrinth `fabric-api`; hashes match                   | Single dual-source synthetic `fabric-api`                                                   |
| Same as above but hashes differ and scan fails                                                                                         | Error — user declares top-level `fabric-api` with `sources:` or `allow-hash-mismatch: true` |
| CF-only `ae2` transitively requires CF `some-lib`; Modrinth has no `some-lib` project                                                  | Single-source synthetic `some-lib` with `sources: [curseforge]`                             |

## Mixing CF and Modrinth in one pack

Entries coexist under the same section maps (`mods:`,
`resource_packs:`, `data_packs:`, `shaders:`). `mods.lock` records
one block per resolved source with the platform-specific
project/file identifiers plus hash; excluded or not-found platforms
get a marker instead:

```yaml
# mods.lock (sketch)
mods:
  jei:
    version: 19.27.0
    modrinth: { project_id: ..., version_id: ..., sha512: ... }
    curseforge: { project_id: 238222, file_id: ..., sha512: ... }
  distanthorizons:
    version: 2.3.0
    modrinth: { project_id: ..., version_id: ..., sha512: ... }
    # curseforge excluded via sources: [modrinth]
  some-modrinth-only-mod:
    version: 1.2.3
    modrinth: { project_id: ..., version_id: ..., sha512: ... }
    curseforge: { status: not_found }
```

[`deps`](todo.md#deps-command) surfaces per-platform source
information in its output. Transitive deps are cross-deduplicated
per
[Transitive dependencies](#transitive-dependencies-and-deduplication).

## Publishing to CurseForge

Extend [`publish_to`](mods-yaml.md#publish_to) to cover CurseForge
alongside Modrinth; a pack can target one or both in a single
[`publish`](todo.md#publish-command) run. Exact schema shape TBD
(candidates: a `publish_to_curseforge:` peer field, or promoting
`publish_to` to an object keyed by platform).

Add a CurseForge manifest emitter to the archive builder — CF packs
ship as `manifest.json` + `overrides/` in a `.zip`.
[`pack`](cli.md#pack) grows a `--curseforge` flag;
[`publish`](todo.md#publish-command) becomes platform-aware.

Mods not available on the target platform get bundled as loose
overrides (with author permission). `publish` warns; `--publishable`
on [`pack`](cli.md#pack) escalates to an error, scoped to the target
being built, and also surfaces entries with `allow-hash-mismatch:
true` because the published artifact ships only one of the two
divergent builds.

## Out of scope

- Importing existing CF packs (`gitrinth curseforge import`).
  Deferred until the Modrinth-side
  [`unpack`](todo.md#unpack-command) command lands — the two should
  share an archive-reader and `mods.yaml` emitter, so landing them
  together avoids rework.
- CurseForge desktop launcher (Overwolf client) integration.
- Automated CF-to-Modrinth (or vice versa) slug mapping during
  import. Migrating a pack across platforms is a manual,
  entry-by-entry operation.

## Implementation touches

[`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart),
[`lib/src/service/resolver.dart`](../lib/src/service/resolver.dart),
new `lib/src/service/curseforge_api.dart`, archive builder,
[`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart),
new `lib/src/commands/curseforge.dart`,
[`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml),
[`mods-yaml.md`](mods-yaml.md), [`cli.md`](cli.md).
