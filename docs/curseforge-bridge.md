# CurseForge bridge

Support CurseForge as a first-class peer to Modrinth — pack authors
can source mods from either platform, mix them in one pack, and
publish to either (or both) as a target.

This document specifies the CurseForge bridge feature. See
[`todo.md`](todo.md) for the overall planned-improvements index; the
bridge lives there as a single checklist entry that points here.

## Status

Seven distinct top-level tasks. The CF API client is the
foundational piece for the cross-platform work; hosted Modrinth
(labrinth) is folded in here rather than tracked separately because
it shares the same multi-host resolver and token-store refactor —
see [Reference architecture](#reference-architecture). Most tasks
depend on the CF client but can be implemented in parallel; the
hosted-Modrinth slice can land first and independently.

- [ ] [Fetching mods](#fetching-mods) — CurseForge API client, `curseforge:` / `modrinth:` peer fields, `sources: [...]` restriction (scalar or list), default-both resolution, `cf:<slug>` short-form sugar, per-entry and pack-level `modrinth-host:` override.
- [ ] [`add` command cross-platform behavior](#add-command-cross-platform-behavior) — entry-write matrix and `--[no-]modrinth` / `--[no-]curseforge` / `--allow-hash-mismatch` flags.
- [ ] [Cross-platform hash verification](#cross-platform-hash-verification) — SHA1 comparison, older-version scan bounded by `hash-scan-depth`, `allow-hash-mismatch` per-entry override.
- [ ] [Search fallback](#search-fallback) — slug-not-found and hash-mismatch triggers, hash-first ranking, `no-cross-platform-search` / `--no-search` opt-outs.
- [ ] [Transitive dependencies and deduplication](#transitive-dependencies-and-deduplication) — slug-table index, synthetic entries, cross-platform synthetic promotion, slug-divergence post-merge.
- [ ] [Publishing to CurseForge](#publishing-to-curseforge) — `publish_to` extension, CF manifest emitter, `--curseforge` flag on `pack`, platform-aware `publish`.
- [ ] [Hosted Modrinth (labrinth)](#hosted-modrinth-labrinth) — rename schema/parser `hosted:` → `modrinth-host:`, drop the deferred-source guard, thread the host through `ModrinthApi`, wire tokens via `UserConfig.tokens[host]`, accept pack-level `modrinth-host:` as a default.

The [Mixing CF and Modrinth in one pack](#mixing-cf-and-modrinth-in-one-pack)
section describes the resulting lockfile shape — it's not a task on
its own, but a consolidated view of what the seven above produce.

## Reference architecture

The bridge is not a greenfield design — substantial pieces of
infrastructure it depends on are already in the tree. New readers
should map each bridge concept onto the existing primitive before
proposing duplicate work.

| Bridge concept                           | Existing primitive                                                                                                                                                                                                                                   |
|------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Modrinth API client with swappable host  | `ModrinthApi(Dio, {baseUrl})` (retrofit-generated) — [`lib/src/service/modrinth_api.dart`](../lib/src/service/modrinth_api.dart)                                                                                                                     |
| Default Modrinth base URL                | `defaultModrinthBaseUrl` — [`lib/src/service/modrinth_url.dart`](../lib/src/service/modrinth_url.dart)                                                                                                                                               |
| Entry source variants                    | `EntrySource` sealed class with `ModrinthEntrySource`, `UrlEntrySource`, `PathEntrySource` — [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart)                                                                     |
| Per-entry `accepts-mc` and channel floor | shipped — [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart), [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml)                                                                                 |
| Token storage                            | `UserConfig.tokens: Map<String, String>` keyed by server URL — [`lib/src/service/user_config.dart`](../lib/src/service/user_config.dart); `--config` flag and `GITRINTH_CONFIG` env wired in [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart) |
| Rate-limit handling                      | `ModrinthRateLimitInterceptor` — host-scoped, applies per `baseUrl` ([`lib/src/service/modrinth_rate_limit_interceptor.dart`](../lib/src/service/modrinth_rate_limit_interceptor.dart))                                                              |
| Caret-on-add convention                  | shipped — [`add`](cli.md#add) writes `^x.y.z`                                                                                                                                                                                                        |

## Fetching mods

Every entry resolves on **both Modrinth and CurseForge by default**.
Most mods share a slug across platforms, so short-form stays terse
and packs are cross-platform without ceremony. The Modrinth side of
that resolution can be redirected at a labrinth deployment via
`modrinth-host:` (per-entry or pack-wide); the CurseForge side
always targets `api.curseforge.com`.

```yaml
# Pack-wide labrinth default — applies to every entry that doesn't
# set its own `modrinth-host:` and resolves on the Modrinth source.
modrinth-host: https://modrinth.example.com

mods:
  # Default: resolves on both platforms; the Modrinth side targets
  # the pack's modrinth-host (labrinth in this example).
  jei: ^19.27.0
  create: ^6.0.10+mc1.21.1
  sodium: ^0.5.13

  # Per-entry host override — peers a Modrinth-protocol source on
  # a different host than the pack default.
  thirdparty-mod:
    modrinth-host: https://other.example.com
    version: ^1.0.0

  # Slug differs on CurseForge — override CF side only
  fabric-api:
    curseforge: fabric-api-cf-slug        # CF-specific slug
    version: ^0.102.0

  # Restrict to Modrinth only (CF excluded explicitly)
  distanthorizons:
    sources: [modrinth]
    version: ^2.3.0

  # Equivalent scalar form for single-platform restriction
  ae2:
    sources: curseforge
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
`sources:` explicitly restricts resolution to the listed platforms —
use it when a mod only exists on one side, or when you want to pin
an entry to one platform even though the other has it. The schema
accepts both a scalar (`sources: curseforge`) and a list
(`sources: [curseforge]`) form via a `oneOf` of string-or-array; the
parser normalizes both into a single internal `Set<SourceKind>`.

If a declared-or-defaulted platform doesn't have the mod, that
platform gets a `not_found` marker in `mods.lock` and a warning is
emitted; the entry still succeeds as long as at least one platform
resolves. `mods-yaml.md` will be updated alongside this task to
document the relaxed key semantics and the new fields.

The resolver uses the same `loader` + `mc-version` filters (plus
per-entry [`accepts-mc`](todo.md#accepts-mc--per-entry-mc-version-tolerance))
and the same channel floor (`release`/`beta`/`alpha`) across
platforms. Downloads hit each platform's CDN. The CF API requires a
key, managed via [`token` add curseforge.com](todo.md#token-command);
labrinth hosts named via `modrinth-host:` look up
`UserConfig.tokens[<host>]` through the same store.

### Host overrides

`modrinth-host:` is a host override on the Modrinth source kind —
not a third platform. A labrinth deployment speaks the Modrinth API,
so cross-platform hash verification, search fallback, slug-table
deduplication, and the `discovered-via-search` audit trail all work
identically when the Modrinth side resolves against
`https://modrinth.example.com` instead of
`https://api.modrinth.com`. The `sources:` set therefore stays
`{modrinth, curseforge}` regardless of host.

Rules:

- `modrinth-host: <url>` and `modrinth: <slug>` are **not mutually
  exclusive** — `modrinth:` overrides the slug, `modrinth-host:`
  overrides the host. Both peer the same Modrinth-protocol source.
- `modrinth-host:` and `url:` / `path:` remain mutually exclusive
  (the schema already enforced this for the legacy `hosted:`
  spelling; the rename preserves the constraint).
- A top-level `modrinth-host:` field on `mods.yaml` sets the default
  Modrinth base URL for every entry that doesn't declare its own
  `modrinth-host:`. Without it, the default stays
  [`defaultModrinthBaseUrl`](../lib/src/service/modrinth_url.dart).
- Authentication: when `modrinth-host:` (or the pack-level default)
  names a non-default host, the resolver looks up
  `UserConfig.tokens[<host>]` and attaches it as the bearer token.
  Missing-token resolution against a non-default host is a hard
  error pointing at `gitrinth token add <host>` — see
  [`token`](todo.md#token-command).

## `add` command cross-platform behavior

`gitrinth add <slug>` resolves on both platforms by default and
writes the minimal entry that captures what it found. The resolved
form depends on which platforms have the mod and whether hashes
align:

| Situation                                       | Entry written                          | Notice                                                                                            |
|-------------------------------------------------|----------------------------------------|---------------------------------------------------------------------------------------------------|
| Both resolve, hashes match                      | Short form (`slug: ^x.y.z`)            | silent                                                                                            |
| Both resolve, scan finds an older matching pair | Short form (`slug: ^x.y.z`)            | prints chosen version and each platform's latest                                                  |
| Both resolve, scan exhausts without a match     | *(nothing written)*                    | fails with remediations + `--[no-]modrinth` / `--[no-]curseforge` / `--allow-hash-mismatch` flags |
| Only Modrinth has the mod                       | Long form with `sources: [modrinth]`   | prints one-sided resolution                                                                       |
| Only CurseForge has the mod                     | Long form with `sources: [curseforge]` | prints one-sided resolution                                                                       |
| Neither platform has the mod                    | *(nothing written)*                    | fails with not-found error                                                                        |

Long-form restrictions (`sources: [modrinth]` or `sources:
[curseforge]`) are only written when the resolver confirmed one
platform is unavailable at add time. This saves future `get` calls
from re-querying the missing platform and makes one-sided entries
visible in the manifest.

`add` CLI flags:

| Flag                    | Effect                                                                                                     |
|-------------------------|------------------------------------------------------------------------------------------------------------|
| `--[no-]modrinth`       | Toggle Modrinth resolution. `--no-modrinth` forces `sources: [curseforge]` even when Modrinth has the mod. |
| `--[no-]curseforge`     | Toggle CurseForge resolution. `--no-curseforge` forces `sources: [modrinth]` even when CF has the mod.     |
| `--allow-hash-mismatch` | Accept divergent hashes on both platforms; writes `allow-hash-mismatch: true` on the entry.                |

`cf:<slug>` short-form sugar (`gitrinth add cf:applied-energistics-2`)
implies `--no-modrinth` and writes a single-platform entry
without querying Modrinth.

## Cross-platform hash verification

The "Modrinth side" of this comparison includes labrinth: a pack
that pairs CurseForge with `modrinth-host: https://labrinth.example`
runs hash verification identically to a pack that uses the default
modrinth.com host. `discovered-via-search`, scan-depth,
`allow-hash-mismatch`, and slug-divergence handling all apply
without modification.

When an entry resolves on both platforms, gitrinth fetches each
platform's SHA1 and compares. (SHA1 is the algorithm returned by
both Modrinth's and CurseForge's file APIs; Modrinth's SHA512 is
retained for single-platform tamper detection on download.) Matching
hashes lock silently.

On a mismatch, gitrinth first scans older versions on both platforms
within the entry's version constraint, looking for a hash-matching
pair. This transparently recovers when one platform's CI ships a
newer build than the other for a brief window. When a match is
found, gitrinth locks that pair and prints which version was chosen
(it will be at or below the newest constraint-satisfying version).
The scan is bounded by the per-entry `hash-scan-depth:` field
(default `10`; `0` disables the scan entirely).

If the scan runs out of candidates, gitrinth then searches the
mismatching platform(s) for alternative slugs that hash-match the
anchor — see [Search fallback](#search-fallback). This handles slug
collisions where the declared slug names different mods on each
platform.

If neither scan nor search finds a hash-matching candidate,
resolution **fails** with an error listing both current hashes,
slugs, project IDs, and any near-match candidates from search, plus
three remediations: accept the divergence with
`allow-hash-mismatch: true`, restrict to one platform via
`sources: [...]`, or pin different versions per platform to align
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

## Search fallback

When a declared-or-defaulted platform returns no project for the
declared slug, gitrinth runs a search on that platform before marking
it `not_found`. This handles the common case where a mod exists on
both platforms but the CurseForge project carries a different slug
than the Modrinth one — e.g., Modrinth `fabric-api` vs CurseForge
`fabric-api-0-102-0`.

### When search runs

Used by `add`, `get`, and `upgrade`. Search triggers on two paths:

- **Slug-not-found path** — the platform's slug lookup returns no
  project. Search looks for the mod under an alternative slug.
- **Hash-mismatch path** — the declared slug exists on both
  platforms but the [hash scan](#cross-platform-hash-verification)
  exhausts without finding a matching pair. Search looks for
  alternative slugs on the mismatching platform(s) that might be
  the correct mod (useful when a short slug like `jei` happens to
  name different mods across platforms).

Both paths additionally require:

- The other platform resolved the entry successfully (providing a
  hash anchor to match against), AND
- The entry isn't restricted to a single platform via
  `sources: [...]` and doesn't set `no-cross-platform-search: true`,
  AND
- The global `--no-search` flag isn't set.

### How results are ranked

Search queries the platform with the missing slug as the query
string, filtered by `loader` + `mc-version` + `accepts-mc`. Results
are scored using the already-resolved platform's entry as the anchor:

1. **SHA1 match** against the anchor's locked hash (using the same
   `hash-scan-depth` window). A unique hash match auto-locks.
2. **Project title** fuzzy match against the anchor's title.
3. **Author** match against the anchor's author.
4. **Category** compatibility.

A hash match is definitive. Without a hash match, behavior depends
on the triggering path:

- **Slug-not-found path** — at least one of name or author must
  align for auto-lock; otherwise fail with a candidate list.
- **Hash-mismatch path** — auto-lock requires a hash match.
  Name/author matches are listed as candidates in the error output
  but never auto-applied, because a declared slug already matches
  (just with divergent content) and silently switching to a
  different slug based on fuzzy signals is too risky.

### Outcomes

**Hash match found** — locks the discovered slug and prints a
notice:

```text
fabric-api: resolved on CurseForge via search as
'fabric-api-0-102-0' (hash match with Modrinth). Consider adding
`curseforge: fabric-api-0-102-0` to mods.yaml to skip search on
future runs.
```

`mods.lock` records `discovered-via-search: true` on the affected
source block so the user can audit which entries relied on search:

```yaml
mods:
  fabric-api:
    version: 0.102.0
    modrinth: { project_id: ..., sha512: ... }
    curseforge:
      project_id: ...
      file_id: ...
      sha512: ...
      discovered-via-search: true
```

**Candidates found, no hash match** — fails with the top candidates
listed (project title, author, latest compatible version each). User
resolves via explicit `curseforge:` override, `sources: [...]`
restriction, or `allow-hash-mismatch: true`.

**Search returns nothing** — falls through to the existing
`not_found` behavior: the missing platform gets the marker, the
entry succeeds as long as at least one platform resolved, and a
warning is emitted.

### Transitive deps

Search runs for transitive deps on the same terms. Combined with
[Cross-platform slug divergence](#cross-platform-slug-divergence)
post-merge, this means diverged-slug transitives resolve
automatically in two ways: search finds the diverged slug up-front
when one platform's parent lists it, and the post-merge pass
deduplicates when the two platforms' parents each resolve to their
own-platform-slugged dep independently.

### Per-entry and global opt-out

```yaml
mods:
  some-proprietary-mod:
    curseforge: 12345
    version: ^1.0.0
    no-cross-platform-search: true    # don't search Modrinth for a twin
```

`no-cross-platform-search: true` suppresses search even when
cross-platform is in scope. Mostly redundant with `sources: [...]`
(which already skips search for the excluded platform) — use it when
you want the other platform checked for slug presence but never
searched for adjacent candidates.

Global `--no-search` on `get` / `add` / `upgrade` disables the
fallback for the entire run, useful on locked-down networks or when
debugging resolver behavior.

### Performance

Search adds at most one API call per platform per not-found slug.
Results are cached in the gitrinth cache keyed by `(host, platform,
query, loader, mc-version)` for the resolution session, so repeated
`get`/`upgrade` runs don't re-query and labrinth queries don't
pollute the modrinth.com cache (or vice versa). To avoid search entirely at
scale, migrate discovered slugs into explicit `modrinth:` /
`curseforge:` overrides in `mods.yaml`; gitrinth's notice output
includes the exact override to paste.

## Transitive dependencies and deduplication

Transitive dependencies from either platform are cross-deduplicated
so a mod required by both a Modrinth and a CurseForge parent
resolves to one logical entry rather than two. The same hash
identity used by
[Cross-platform hash verification](#cross-platform-hash-verification)
drives the dedup.

### Slug-table index

After top-level entries resolve, gitrinth builds a slug-to-entry
index per `(platform, host)` pair — not just per platform.
`flywheel` resolved on modrinth.com and `flywheel` resolved on a
labrinth instance are not automatically the same logical mod; they
go through the same hash-based merge logic that already covers
slug divergence (in practice they will hash-match and merge
silently, but the resolver doesn't conflate them by name alone).
For packs without `modrinth-host:` the index collapses to one entry
per platform, matching the original shape:

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

### Cross-platform slug divergence

When a top-level entry uses different `modrinth:` and `curseforge:`
slugs, the slug-table index already covers both sides (one key per
platform pointing at the same entry). Transitive deps requiring
either slug match that top-level entry automatically.

The gap is when a mod appears only transitively *and* its slugs
diverge across platforms — e.g., Modrinth `create` declares a dep on
`flywheel` while CF `create` declares a dep on `flywheel-forge`
(hypothetical). Slug-based lookup misses the identity, so the
resolver initially produces two synthetics:

- Modrinth synthetic `flywheel`
- CF synthetic `flywheel-forge`

A post-resolution merge pass compares hashes (with the same
`hash-scan-depth` window used by top-level verification) between
every Modrinth-only synthetic and every CF-only synthetic. When
hashes match, the two merge into one dual-source synthetic:

- **Canonical key**: the Modrinth slug (Modrinth is the primary
  platform, so its slug wins).
- **CF-side slug** is recorded as a `curseforge:` override field on
  the merged synthetic.
- Both platforms' `required-by:` lists are unioned.

If no hash match is found in the scan window, the two synthetics
stay separate and an info-level message points the user at an
explicit remediation:

```text
info: transitive dependency 'flywheel' (Modrinth) and
'flywheel-forge' (CurseForge) may refer to the same logical mod but
no hash-matching version was found within hash-scan-depth.

If they are the same mod, add a top-level entry to declare the
cross-platform identity:

  mods:
    flywheel:
      modrinth: flywheel
      curseforge: flywheel-forge
      version: ^1.0.0

Otherwise they remain two separate entries.
```

This keeps the "one logical mod, one entry" invariant intact while
only merging on concrete hash evidence — no fuzzy name/author
heuristics that could silently bundle wrong mods.

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

## Hosted Modrinth (labrinth)

Folded in alongside the cross-platform work because the same
multi-host resolver and token-store wiring backs both — keeping it
on a separate roadmap would mean designing the same refactor twice.
Independent of the rest, though: this slice does not require the CF
API client, so it can land first.

The schema field today is named `hosted:`; that name is ambiguous
(hosted what? where?). Rename it to `modrinth-host:` so the
protocol it speaks (the Modrinth API) is explicit and so the same
spelling can be reused as a pack-level default. Behavior described
under [Fetching mods → Host overrides](#host-overrides) covers the
runtime semantics.

Concrete work:

- Rename `hosted` → `modrinth-host` in
  [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml),
  in the parser at
  [`lib/src/model/manifest/parser.dart`](../lib/src/model/manifest/parser.dart)
  (today's `hosted` handling around the source-count check), and in
  the existing `mods-yaml.md` examples.
- Drop the parser's "hosted source is deferred" guard — the same
  block, post-rename — and parse the field through to the model.
- Extend `ModrinthEntrySource` with an optional host (or add a
  peer source variant) so the resolver carries the override to the
  `ModrinthApi` factory call.
- Add a top-level `modrinth-host:` field to the manifest schema and
  to the pack-level model.
- Replace the single shared `ModrinthApi` instance with a
  host-keyed factory; reuse the existing
  `ModrinthRateLimitInterceptor` per host because rate-limit
  budgets are per-IP-per-host.
- Look up bearer tokens from `UserConfig.tokens[<host>]`. Document
  `gitrinth token add <host>` in the
  [`token`](todo.md#token-command) command spec — both directions
  cross-link.

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

| Path                                                                                                                                                                      | Status | Role in bridge                                                                                                                                                                                                             |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart)                                                                                       | exists | Add `modrinth:` / `curseforge:` slug overrides, `sources:` (scalar or list), hash flags; grow `ModrinthEntrySource` with an optional host (or add a peer); add pack-level `modrinth-host:` to the top-level manifest model |
| [`lib/src/model/manifest/parser.dart`](../lib/src/model/manifest/parser.dart)                                                                                             | exists | Rename `hosted` → `modrinth-host`, drop the deferred-source guard, parse the new entry and pack-level fields                                                                                                               |
| [`lib/src/model/manifest/mods_lock.dart`](../lib/src/model/manifest/mods_lock.dart)                                                                                       | exists | Per-source hash blocks, `not_found` markers, `discovered-via-search`, `required-by:`                                                                                                                                       |
| [`lib/src/service/resolve_and_sync.dart`](../lib/src/service/resolve_and_sync.dart) and [`lib/src/model/resolver/resolver.dart`](../lib/src/model/resolver/resolver.dart) | exists | Multi-source branching; today's single-source `if (entry.source is! ModrinthEntrySource)` early-out (in both files) becomes the dispatch point                                                                             |
| [`lib/src/service/modrinth_api.dart`](../lib/src/service/modrinth_api.dart)                                                                                               | exists | Already supports per-call `baseUrl`; needs a host-keyed factory so each labrinth host gets its own client + rate-limit budget                                                                                              |
| `lib/src/service/curseforge_api.dart`                                                                                                                                     | new    | Retrofit client mirroring `ModrinthApi` shape                                                                                                                                                                              |
| [`lib/src/service/user_config.dart`](../lib/src/service/user_config.dart)                                                                                                 | exists | Token lookup by host already supported via `tokens: Map<String, String>`                                                                                                                                                   |
| [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart)                                                                                                                   | exists | Wire new commands                                                                                                                                                                                                          |
| [`lib/src/commands/add_command.dart`](../lib/src/commands/add_command.dart)                                                                                               | exists | `cf:` short form, `--[no-]modrinth` / `--[no-]curseforge` / `--allow-hash-mismatch` flags                                                                                                                                  |
| `lib/src/commands/curseforge.dart`                                                                                                                                        | new    | Hosts CF-specific subcommands if any survive design                                                                                                                                                                        |
| `lib/src/commands/token_command.dart`                                                                                                                                     | new    | `token add` / `list` / `remove` (also referenced from [`todo.md`](todo.md#token-command))                                                                                                                                  |
| [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml)                                                                                                     | exists | Rename `hosted` → `modrinth-host`; add new entry fields; add pack-level `modrinth-host:`                                                                                                                                   |
| [`docs/mods-yaml.md`](mods-yaml.md)                                                                                                                                       | exists | Update `hosted:` → `modrinth-host:` in docs and examples; document new entry shape; remove "Modrinth-only" framing where it's no longer accurate                                                                           |
| [`docs/cli.md`](cli.md)                                                                                                                                                   | exists | `cf:` short form, new `add` flags, `token` subcommands, `--curseforge` on `pack`                                                                                                                                           |
