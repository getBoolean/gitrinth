# CurseForge bridge

Support CurseForge as a first-class peer to Modrinth — pack authors
can source entries from either platform, mix them in one pack, and
publish to either (or both) as a target. "Entries" covers the existing
section maps: `mods:`, `resource_packs:`, `data_packs:`, `shaders:`,
and `plugins:`.

CurseForge plugin support is intentionally narrower than Modrinth
plugin support: CurseForge only contributes Bukkit/Spigot/Paper
compatible plugins. Sponge plugins remain Modrinth-only, and Folia
plugin entries are Modrinth-only because CurseForge does not support
Folia plugins.

This document specifies the CurseForge bridge feature. See
[`todo.md`](todo.md) for the overall planned-improvements index; the
bridge lives there as a single checklist entry that points here.

## Status

Implementation is split into distinct parts so the bridge can land
incrementally. The CF API client is the foundational piece for the
cross-platform work; hosted Modrinth (labrinth) is folded in here
rather than tracked separately because it shares the same multi-host
resolver and token-store refactor — see
[Reference architecture](#reference-architecture). Most resolver,
CLI, and publishing parts depend on the CF client but can be built
against fakes in parallel. The hosted-Modrinth slice can land first
and independently.

- [x] [Part 1: Foundation and hosted Modrinth](#part-1-foundation-and-hosted-modrinth) — normalize hyphenated manifest fields to underscores, rename schema/parser `hosted:` → `modrinth_host:`, drop the deferred-source guard, thread the host through `ModrinthApi`, wire tokens via `UserConfig.tokens[host]`, accept pack-level `modrinth_host:` as a default.
- [x] [Part 2: Manifest source model](#part-2-manifest-source-model) — `curseforge:` / `modrinth:` peer fields, `sources: [...]` restriction (scalar or list), top-level `gitrinth:` block (with `gitrinth.version` semver constraint plus `gitrinth.modrinth` / `gitrinth.curseforge` defaults — replaces the old `tooling:` block), `cf:<slug>` short-form sugar, section-aware source eligibility, plugin source limits.
- [ ] [Part 3: CurseForge API client](#part-3-curseforge-api-client) — typed client, token lookup for `curseforge.com`, content-type filters, loader/version filters, file/hash/dependency models, cache boundaries.
- [ ] [Part 4: Resolver and lockfile](#part-4-resolver-and-lockfile) — multi-source resolution, per-platform lock blocks, `not_found` markers, plugin lock behavior, cross-platform SHA1 verification, `hash_scan_depth`, `allow_hash_mismatch`.
- [ ] [Part 5: Search fallback](#part-5-search-fallback) — slug-not-found and hash-mismatch triggers, hash-first ranking, section-aware search filters, `no_cross_platform_search` / `--no-search` opt-outs.
- [ ] [Part 6: Transitive dependencies and deduplication](#part-6-transitive-dependencies-and-deduplication) — slug-table index, synthetic entries, cross-platform synthetic promotion, slug-divergence post-merge.
- [ ] [Part 7: CLI integration](#part-7-cli-integration) — `add` entry-write matrix, `--[no-]modrinth` / `--[no-]curseforge` / `--allow-hash-mismatch` flags, `cf:` handling, token commands.
- [ ] [Part 8: Pack and publish](#part-8-pack-and-publish) — `publish_to` target selector/config map, CF manifest emitter, `--curseforge` flag on `pack`, platform-aware `publish`, plugin publishing constraints.

The [Mixing CF and Modrinth in one pack](#mixing-cf-and-modrinth-in-one-pack)
section describes the resulting lockfile shape — it's not a task on
its own, but a consolidated view of what the parts above produce.

## Implementation plan

### Part 1: Foundation and hosted Modrinth

Shipped. The foundational refactor lands the multi-host resolver, the
underscore field rename, and the `modrinth_host:` per-entry / pack
default. Details live in [Hosted Modrinth (labrinth)](#hosted-modrinth-labrinth).

What landed:

- `hosted:` is renamed to `modrinth_host:` in schema, parser, docs,
  and examples; the parser also accepts a top-level `modrinth_host:`
  as the pack-wide default.
- Hyphenated manifest fields are normalized to underscore form:
  `mc-version` → `mc_version`, `accepts-mc` → `accepts_mc`,
  plus the lockfile-only fields `project-id` → `project_id`,
  `version-id` → `version_id`, and `game-versions` →
  `game_versions`. Old hyphenated keys stop parsing — fixtures and
  example packs were updated in the same change. (The bridge spec's
  remaining hyphenated fields — `hash-scan-depth`,
  `allow-hash-mismatch`, `no-cross-platform-search`,
  `discovered-via-search`, `required-by` — land underscored when their
  parts ship.)
- The resolver dispatches against a host-keyed `ModrinthApiFactory`
  with one `Dio` + rate-limit interceptor per host. The cache layout
  is host-segmented: `<modrinthRoot>/<hostSegment>/<projectId>/<versionId>/...`
  (default host renders to a stable segment so the layout is
  uniform).
- `ModrinthAuthInterceptor` already handled per-host token lookup;
  the factory wires one auth interceptor per host instance so
  `GITRINTH_TOKEN` continues to apply only to the default host.
- Default-host Modrinth behavior is unchanged on the wire — the
  cache layout is a one-time break (existing caches are re-fetched
  on first run after upgrade).

### Part 2: Manifest source model

Shipped. The cross-platform grammar is parsed today even though the
CurseForge resolver itself lands later — manifests can be authored
ahead of CF resolver support. Details live in [Fetching mods](#fetching-mods)
and [Host overrides](#host-overrides).

What landed:

- Entries accept `modrinth:` / `curseforge:` peer slug fields and
  `sources:` (scalar or list); the parser normalizes both source
  forms into a single internal `Set<SourceKind>`. Empty lists,
  duplicates, and unknown enum values fail at parse time.
- The legacy `tooling:` block is replaced by a top-level `gitrinth:`
  block. `gitrinth.version` carries the semver constraint formerly
  written as `tooling.gitrinth`; `gitrinth.modrinth` and
  `gitrinth.curseforge` toggle default participation for each
  platform (Modrinth enabled, CurseForge disabled). Examples and
  the schema were updated in the same change.
- Local section keys are treated as opaque identifiers; the model
  already used `Map<String, ModEntry>` keys generically, and the
  docs were tightened to call them out as identifiers rather than
  slugs.
- Source eligibility is enforced at parse time: `plugins:` entries
  with `sources: curseforge` (or a `curseforge:` peer) require
  `loader.plugins ∈ {bukkit, spigot, paper}` and otherwise throw a
  manifest error pointing at the
  [Source eligibility matrix](#source-eligibility-matrix).
- The `cf:<slug>[@<version>]` short-form sugar is intentionally an
  `add` CLI feature only — it lands with Part 7 and the parser
  never sees raw `cf:` strings as values.

### Part 3: CurseForge API client

Build a typed client and adapter layer that returns resolver-friendly
project/version/file/dependency data. Keep CurseForge details out of
the manifest parser.

Done means:

- `lib/src/service/curseforge_api.dart` can look up projects by slug
  or numeric project ID.
- The adapter can list compatible files by Minecraft version,
  section, loader, and channel floor.
- File models expose SHA1 and any dependency relation data needed by
  [Transitive dependencies](#transitive-dependencies-and-deduplication).
- CF requests use the configured CurseForge token and have cache keys
  separated from Modrinth/labrinth hosts.

### Part 4: Resolver and lockfile

Turn the existing single-source resolver into a platform-dispatching
resolver. Details live in
[Cross-platform hash verification](#cross-platform-hash-verification)
and [Mixing CF and Modrinth in one pack](#mixing-cf-and-modrinth-in-one-pack).

Done means:

- Each requested eligible source resolves independently, with
  `not_found` recorded when a declared or `gitrinth`-enabled default
  source is missing.
- Dual-source entries compare SHA1, scan older compatible versions,
  and respect `allow_hash_mismatch`.
- `mods.lock` records per-platform IDs and hashes for every section,
  including `plugins:`.
- Lockfile source states are explicit: resolved, `not_found`, or
  omitted because the source was excluded, ineligible, or not
  requested.
- Unsupported source/section combinations fail early with manifest
  errors instead of surfacing as resolver misses.

### Part 5: Search fallback

Implement search only after deterministic resolution and hash
verification are in place. Details live in
[Search fallback](#search-fallback).

Done means:

- Slug-not-found and hash-mismatch paths can search the missing or
  mismatching platform.
- Search is filtered by section, Minecraft version, loader, and
  source eligibility.
- Hash matches auto-lock; fuzzy-only matches become candidate output.
- `no_cross_platform_search` and global `--no-search` suppress the
  fallback consistently.

### Part 6: Transitive dependencies and deduplication

Layer graph behavior on top of stable source resolution. Details live
in
[Transitive dependencies and deduplication](#transitive-dependencies-and-deduplication).

Done means:

- Top-level entries are indexed by source/host/slug.
- Transitive dependencies are assigned to lockfile sections by the
  dependency project's platform content type.
- Synthetic entries are created only when no top-level entry matches.
- Cross-platform synthetics merge only on hash evidence.
- `required_by:` is retained for `deps` output.

### Part 7: CLI integration

Expose the new behavior through commands after parser and resolver
semantics are stable. Details live in
[`add` command cross-platform behavior](#add-command-cross-platform-behavior)
and the command docs linked from
[Implementation touches](#implementation-touches).

Done means:

- `gitrinth add` writes the minimal source shape for one-sided or
  dual-source entries.
- `cf:<slug>` is supported for all CF-eligible sections.
- `--[no-]modrinth`, `--[no-]curseforge`,
  `--allow-hash-mismatch`, and `--no-search` are wired.
- `gitrinth curseforge enable/disable` and
  `gitrinth modrinth enable/disable` edit the matching `gitrinth`
  platform toggle in `mods.yaml`.
- `token add/list/remove` can manage both host URLs and
  `curseforge.com`.

### Part 8: Pack and publish

Finish with archive output and remote upload behavior. Details live
in [Publishing to CurseForge](#publishing-to-curseforge).

Done means:

- `pack --curseforge` emits a CF-compatible archive.
- `publish` can target Modrinth, CurseForge, or both.
- `publish_to` can select targets in scalar/list shorthand or as a
  target config map; `publish_to.modrinth` can carry a
  Modrinth-compatible publishing host independently from
  `modrinth_host:`. When `publish_to` is unset, publish targets
  follow the enabled `gitrinth` platforms.
- Entries unavailable on a target are handled as target-scoped
  overrides or publish errors according to command flags.
- Plugin publishing is limited to Bukkit/Spigot/Paper-compatible
  plugin entries; Sponge and Folia plugin entries are excluded from
  the CurseForge target unless represented as loose overrides.

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
| Section maps and lock sections           | `Section` covers `mods`, `resource_packs`, `data_packs`, `shaders`, and `plugins` — [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart)                                                                              |
| Plugin-loader vocabulary                 | `PluginLoader` covers `bukkit`, `folia`, `paper`, `spigot`, and Sponge's resolved variants — [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart)                                                                     |
| Per-entry `accepts_mc` and channel floor | shipped — [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart), [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml)                                                                                 |
| Token storage                            | `UserConfig.tokens: Map<String, String>` keyed by server URL — [`lib/src/service/user_config.dart`](../lib/src/service/user_config.dart); `--config` flag and `GITRINTH_CONFIG` env wired in [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart) |
| Rate-limit handling                      | `ModrinthRateLimitInterceptor` — host-scoped, applies per `baseUrl` ([`lib/src/service/modrinth_rate_limit_interceptor.dart`](../lib/src/service/modrinth_rate_limit_interceptor.dart))                                                              |
| Caret-on-add convention                  | shipped — [`add`](cli.md#add) writes `^x.y.z`                                                                                                                                                                                                        |

## Source eligibility matrix

This matrix is the canonical source policy for parser validation,
`add`, resolution, search, transitive dependencies, and publishing.
Other sections should reference it rather than restating policy.

| Section / loader context | Default sources       | Explicit `sources: curseforge` / `cf:` | CF search/transitives | CF publish |
|--------------------------|-----------------------|----------------------------------------|-----------------------|------------|
| `mods:`                  | enabled platforms     | valid                                  | yes                   | yes        |
| `resource_packs:`        | enabled platforms     | valid                                  | yes                   | yes        |
| `data_packs:`            | enabled platforms     | valid                                  | yes                   | yes        |
| `shaders:`               | enabled platforms     | valid                                  | yes                   | yes        |
| `plugins:` with `bukkit` | enabled platforms     | valid                                  | yes                   | yes        |
| `plugins:` with `spigot` | enabled platforms     | valid                                  | yes                   | yes        |
| `plugins:` with `paper`  | enabled platforms     | valid                                  | yes                   | yes        |
| `plugins:` with `folia`  | enabled Modrinth only | manifest error                         | no                    | no         |
| `plugins:` with `sponge` | enabled Modrinth only | manifest error                         | no                    | no         |

"Enabled platforms" are controlled by `gitrinth.modrinth` and
`gitrinth.curseforge`. Modrinth defaults to `enabled`; CurseForge
defaults to `disabled`. Explicit entry-level `sources: curseforge`
or `cf:<slug>` opts that entry into CurseForge without changing the
pack-wide CurseForge default, as long as the section and loader are
CurseForge-eligible.

Folia is unsupported by CurseForge. When `loader.plugins: folia`,
plugin entries are sourced only from Modrinth or from manual `url:` /
`path:` entries. The bridge must not treat Paper-compatible
CurseForge plugins as Folia-compatible.

## Lockfile source states

Each source block in `mods.lock` has one of these meanings:

- **Resolved** — serialized as the platform-specific project/file ID
  and hash block.
- **Not found** — serialized as `{ status: not_found }` only when an
  eligible declared or `gitrinth`-enabled default platform was queried,
  including any allowed search fallback, and no compatible
  project/file was found.
- **Omitted** — used when the platform was excluded by `sources:`,
  ineligible under the [Source eligibility matrix](#source-eligibility-matrix),
  or never requested.

Explicitly requesting an ineligible source is a manifest error, not a
lockfile state. For example, `sources: curseforge` on a Folia
`plugins:` entry fails before resolution.

## Platform toggles (`gitrinth:` block)

The bridge keeps the expanded `mods.yaml` source grammar available
while leaving CurseForge off by default. Platform defaults and the
`gitrinth` CLI semver constraint live under a top-level `gitrinth:`
block:

```yaml
gitrinth:
  version: ^1.0.0
  modrinth: enabled
  curseforge: disabled
```

Both platform fields accept only `enabled` or `disabled`. Missing
fields use the defaults above: Modrinth enabled, CurseForge disabled.
These toggles affect implicit platform participation only. They do
not make an otherwise invalid source valid, and they do not block an
entry from explicitly selecting a platform with `sources:` or `cf:`.
Peer slug fields such as `curseforge:` only override the slug after
that platform is selected by `gitrinth` defaults, `sources:`, or `cf:`.

`gitrinth curseforge enable` writes `gitrinth.curseforge: enabled`.
`gitrinth curseforge disable` writes `gitrinth.curseforge: disabled`.
`gitrinth modrinth enable` writes `gitrinth.modrinth: enabled`.
`gitrinth modrinth disable` writes `gitrinth.modrinth: disabled`.
The command writers preserve any existing `gitrinth.version`
constraint.

## Fetching mods

Every platform-backed entry resolves on the enabled sources that
support that entry's section and loader according to the
[Source eligibility matrix](#source-eligibility-matrix). With no
`gitrinth` overrides, this means Modrinth only. When
`gitrinth.curseforge: enabled` is present, eligible entries also
resolve on CurseForge by default. The Modrinth side of that
resolution can be redirected at a labrinth deployment via
`modrinth_host:` (per-entry or pack-wide); the CurseForge side always
targets `api.curseforge.com`.

The examples below use `mods:`, but the same source grammar applies
to `resource_packs:`, `data_packs:`, `shaders:`, and supported
`plugins:` entries.

```yaml
# Pack-wide labrinth default — applies to every entry that doesn't
# set its own `modrinth_host:` and resolves on the Modrinth source.
modrinth_host: https://modrinth.example.com

mods:
  # Default: resolves on Modrinth; the Modrinth side targets
  # the pack's modrinth_host (labrinth in this example).
  jei: ^19.27.0
  create: ^6.0.10+mc1.21.1
  sodium: ^0.5.13

  # Per-entry host override — peers a Modrinth-protocol source on
  # a different host than the pack default.
  thirdparty-mod:
    modrinth_host: https://other.example.com
    version: ^1.0.0

  # Slug differs on CurseForge — override CF side only when
  # CurseForge participates for this entry.
  fabric-api:
    curseforge: fabric-api-cf-slug        # CF-specific slug
    version: ^0.102.0

  # Explicit Modrinth-only entry.
  distanthorizons:
    sources: [modrinth]
    version: ^2.3.0

  # Explicit CurseForge-only entry; works even when
  # gitrinth.curseforge is disabled globally.
  ae2:
    sources: curseforge
    curseforge: applied-energistics-2
    version: ^19.0.15

  # CF-only short form sugar
  appleskin: cf:appleskin@^3.0.9

  # Numeric CF project ID (valid in short and long form)
  journeymap: cf:32274@^6.0.0
```

```yaml
# CurseForge-backed plugins are only in scope for Bukkit/Spigot/Paper
# compatible plugin packs.
loader:
  plugins: paper

plugins:
  # Default: resolves on Modrinth unless gitrinth.curseforge is enabled.
  luckperms: ^5.5.17

  # Slug differs on CurseForge — override CF side only when
  # CurseForge participates for this entry.
  worldedit:
    curseforge: worldedit-bukkit
    version: ^7.4.2

  # Stay Modrinth-only even though the loader is CF-eligible.
  server-utilities:
    sources: modrinth
    version: ^2.0.0
```

```text
gitrinth add jei                          # resolves on Modrinth by default
gitrinth add cf:applied-energistics-2     # CF-only
```

The section map key is a local identifier and defaults to the slug
on each platform in the resolution set. `modrinth:` and `curseforge:`
peer fields override that platform's slug when it differs.
`sources:` explicitly restricts resolution to the listed platforms —
use it when an entry only exists on one side, or when you want to pin
an entry to one platform even though another enabled source has it.
Explicit `sources: curseforge` opts that entry into CurseForge even
when `gitrinth.curseforge` is disabled. The schema accepts both a
scalar (`sources: curseforge`) and a list
(`sources: [curseforge]`) form via a `oneOf` of string-or-array; the
parser normalizes both into a single internal `Set<SourceKind>`.

If a declared or `gitrinth`-enabled default platform doesn't have the
entry, that platform gets a `not_found` marker in the matching
`mods.lock` section and a warning is emitted; the entry still
succeeds as long as at least one platform resolves. `mods-yaml.md`
will be updated alongside this task to document the relaxed key
semantics and the new fields.

The resolver uses the same `loader` + `mc_version` filters (plus
per-entry [`accepts_mc`](todo.md#accepts-mc--per-entry-mc-version-tolerance))
and the same channel floor (`release`/`beta`/`alpha`) across
platforms. Downloads hit each platform's CDN. The CF API requires a
key, managed via [`token` add curseforge.com](todo.md#token-command);
labrinth hosts named via `modrinth_host:` look up
`UserConfig.tokens[<host>]` through the same store.

### Plugin source eligibility

CurseForge plugin entries are only eligible when the pack has
`loader.plugins: bukkit`, `loader.plugins: spigot`, or
`loader.plugins: paper`. These map to CurseForge's
Bukkit/Spigot/Paper-compatible plugin universe. For these loaders,
`plugins:` entries can use CurseForge when it is enabled globally or
explicitly selected on the entry.

`loader.plugins: sponge` stays Modrinth-only for `plugins:` entries.
Sponge plugins have a different runtime/API contract, and the
CurseForge bridge must not silently search Bukkit-family plugins for
a Sponge server. A plugin entry under Sponge may still use `url:` or
`path:` for manually supplied jars.

`loader.plugins: folia` is also Modrinth-only. Folia is unsupported by
CurseForge, so the bridge does not search or publish CurseForge
plugins for Folia packs.

Rules:

- In a CF-eligible plugin pack, `plugins:` accepts the same
  `modrinth:`, `curseforge:`, `sources:`, and `cf:<slug>` syntax as
  `mods:`.
- In a CF-ineligible plugin pack, `sources: curseforge`,
  `sources: [curseforge]`, `cf:<slug>`, or a `curseforge:` peer on a
  `plugins:` entry is a manifest error. The user must either remove
  the CF source, change `loader.plugins` to `bukkit` / `spigot` /
  `paper`, or supply the jar through `url:` / `path:`.
- Search, transitive dependency resolution, hash checks, and publish
  behavior only include CurseForge for `plugins:` after this
  eligibility check passes.

### Host overrides

`modrinth_host:` is a host override on the Modrinth source kind —
not a third platform. A labrinth deployment speaks the Modrinth API,
so cross-platform hash verification, search fallback, slug-table
deduplication, and the `discovered_via_search` audit trail all work
identically when the Modrinth side resolves against
`https://modrinth.example.com` instead of
`https://api.modrinth.com`. The `sources:` set therefore stays
`{modrinth, curseforge}` regardless of host.

Rules:

- `modrinth_host: <url>` and `modrinth: <slug>` are **not mutually
  exclusive** — `modrinth:` overrides the slug, `modrinth_host:`
  overrides the host. Both peer the same Modrinth-protocol source.
- `modrinth_host:` and `url:` / `path:` remain mutually exclusive
  (the schema already enforced this for the legacy `hosted:`
  spelling; the rename preserves the constraint).
- A top-level `modrinth_host:` field on `mods.yaml` sets the default
  Modrinth base URL for every entry that doesn't declare its own
  `modrinth_host:`. Without it, the default stays
  [`defaultModrinthBaseUrl`](../lib/src/service/modrinth_url.dart).
- Authentication: when `modrinth_host:` (or the pack-level default)
  names a non-default host, the resolver looks up
  `UserConfig.tokens[<host>]` and attaches it as the bearer token.
  Missing-token resolution against a non-default host is a hard
  error pointing at `gitrinth token add <host>` — see
  [`token`](todo.md#token-command).

## `add` command cross-platform behavior

`gitrinth add <slug>` resolves on every enabled, eligible platform by
default and writes the minimal entry that captures what it found. With
no `gitrinth` overrides, this means Modrinth only. When
`gitrinth.curseforge: enabled` is present, most sections resolve on
both Modrinth and CurseForge. For `plugins:`, CurseForge is eligible
only under `loader.plugins: bukkit`, `spigot`, or `paper`; Sponge and
Folia plugin packs default to Modrinth only. The resolved form depends
on which requested platforms have the entry and whether hashes align:

| Situation                                       | Entry written                          | Notice                                                                                            |
|-------------------------------------------------|----------------------------------------|---------------------------------------------------------------------------------------------------|
| Both resolve, hashes match                      | Short form (`slug: ^x.y.z`)            | silent                                                                                            |
| Both resolve, scan finds an older matching pair | Short form (`slug: ^x.y.z`)            | prints chosen version and each platform's latest                                                  |
| Both resolve, scan exhausts without a match     | *(nothing written)*                    | fails with remediations + `--[no-]modrinth` / `--[no-]curseforge` / `--allow-hash-mismatch` flags |
| Only Modrinth has the entry                     | Long form with `sources: [modrinth]`   | prints one-sided resolution                                                                       |
| Only CurseForge has the entry                   | Long form with `sources: [curseforge]` | prints one-sided resolution                                                                       |
| Neither eligible platform has the entry         | *(nothing written)*                    | fails with not-found error                                                                        |

For automatic multi-platform adds, long-form restrictions
(`sources: [modrinth]` or `sources: [curseforge]`) are written when
the resolver confirmed one requested platform is unavailable at add
time. Explicit one-sided inputs such as `cf:<slug>` or
`--no-modrinth` also write the matching `sources:` restriction. This
saves future `get` calls from re-querying excluded platforms and
makes one-sided entries visible in the manifest.

`add` CLI flags:

| Flag                    | Effect                                                                                                                                                                                            |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `--[no-]modrinth`       | Toggle Modrinth resolution. `--no-modrinth` forces `sources: [curseforge]` even when Modrinth has the entry.                                                                                      |
| `--[no-]curseforge`     | Toggle CurseForge resolution for this add. `--curseforge` opts into CF without changing `gitrinth.curseforge`; `--no-curseforge` forces `sources: [modrinth]` when CF would otherwise participate. |
| `--allow-hash-mismatch` | Accept divergent hashes on both platforms; writes `allow_hash_mismatch: true` on the entry.                                                                                                       |

`cf:<slug>` short-form sugar (`gitrinth add cf:applied-energistics-2`)
implies `--no-modrinth` and writes a single-platform entry with
`sources: curseforge` for the mod entry, without querying Modrinth or
enabling pack-wide CurseForge support. For example:

```yaml
mods:
  applied-energistics-2:
    sources: curseforge
    version: ^19.0.15
```

In the `plugins:` section, `cf:<slug>` is accepted only for
Bukkit/Spigot/Paper plugin packs; using it under Sponge or Folia
fails before any network request with the same eligibility error as
`sources: curseforge`.

## Cross-platform hash verification

The "Modrinth side" of this comparison includes labrinth: a pack
that pairs CurseForge with `modrinth_host: https://labrinth.example`
runs hash verification identically to a pack that uses the default
modrinth.com host. `discovered_via_search`, scan depth,
`allow_hash_mismatch`, and slug-divergence handling all apply
without modification.

Hash verification is section-agnostic once both source blocks are
eligible. That includes Bukkit/Spigot/Paper `plugins:` entries, but
excludes Sponge and Folia plugin entries because those can never
receive a CurseForge source.

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
The scan is bounded by the per-entry `hash_scan_depth:` field
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
`allow_hash_mismatch: true`, restrict to one platform via
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
    allow_hash_mismatch: true

  # Slug collision — 'ae2' names different mods on each platform.
  # Restrict rather than override; the mismatch is a real conflict.
  ae2:
    sources: [modrinth]
    version: ^19.0.15
```

The check runs on `add`, `get`, and `upgrade`. `mods.lock` always
stores per-platform hashes, and downstream downloads verify against
each platform's own hash, so `allow_hash_mismatch` does not disable
tamper detection — it only suppresses the cross-platform equality
check at resolution time.

`allow_hash_mismatch` and `hash_scan_depth` only make sense when two
or more platform sources are declared; setting either alongside
`sources: [modrinth]` or `sources: [curseforge]` is a schema error.
`allow_hash_mismatch: true` short-circuits the scan — no point
scanning when the user is explicitly accepting divergence.

## Search fallback

When a declared or `gitrinth`-enabled default eligible platform returns
no project for the declared slug, gitrinth runs a search on that
platform before marking it `not_found`. This handles the common case
where an entry exists on both platforms but the CurseForge project
carries a different slug than the Modrinth one — e.g., Modrinth
`fabric-api` vs CurseForge `fabric-api-0-102-0`.

### When search runs

Used by `add`, `get`, and `upgrade`. Search triggers on two paths:

- **Slug-not-found path** — the platform's slug lookup returns no
  project. Search looks for the entry under an alternative slug.
- **Hash-mismatch path** — the declared slug exists on both
  platforms but the [hash scan](#cross-platform-hash-verification)
  exhausts without finding a matching pair. Search looks for
  alternative slugs on the mismatching platform(s) that might be
  the correct entry (useful when a short slug like `jei` happens to
  name different projects across platforms).

Both paths additionally require:

- The other platform resolved the entry successfully (providing a
  hash anchor to match against), AND
- The entry isn't restricted to a single platform via
  `sources: [...]` and doesn't set `no_cross_platform_search: true`,
  AND
- The section/loader combination allows the target platform. For
  `plugins:`, CurseForge search only runs under Bukkit/Spigot/Paper,
  AND
- The global `--no-search` flag isn't set.

### How results are ranked

Search queries the platform with the missing slug as the query
string, filtered by section, `loader`, `mc_version`, and
`accepts_mc`. For `plugins:`, CurseForge search additionally filters
to Bukkit/Spigot/Paper-compatible plugin projects. Results are
scored using the already-resolved platform's entry as the anchor:

1. **SHA1 match** against the anchor's locked hash (using the same
   `hash_scan_depth` window). A unique hash match auto-locks.
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

`mods.lock` records `discovered_via_search: true` on the affected
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
      discovered_via_search: true
```

**Candidates found, no hash match** — fails with the top candidates
listed (project title, author, latest compatible version each). User
resolves via explicit `curseforge:` override, `sources: [...]`
restriction, or `allow_hash_mismatch: true`.

**Search returns nothing** — falls through to the existing
`not_found` behavior: the missing platform gets the marker, the
entry succeeds as long as at least one platform resolved, and a
warning is emitted.

### Transitive deps

Search runs for transitive deps on the same terms when the platform
API exposes dependency relation data for that section. Combined with
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
    no_cross_platform_search: true    # don't search Modrinth for a twin
```

`no_cross_platform_search: true` suppresses search even when
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
query, loader, mc_version)` for the resolution session, so repeated
`get`/`upgrade` runs don't re-query and labrinth queries don't
pollute the modrinth.com cache (or vice versa). To avoid search entirely at
scale, migrate discovered slugs into explicit `modrinth:` /
`curseforge:` overrides in `mods.yaml`; gitrinth's notice output
includes the exact override to paste.

## Transitive dependencies and deduplication

Transitive dependencies from either platform are cross-deduplicated
so an entry required by both a Modrinth and a CurseForge parent
resolves to one logical entry rather than two. The same hash
identity used by
[Cross-platform hash verification](#cross-platform-hash-verification)
drives the dedup.

This is section-aware. Plugin dependency data participates when the
source API exposes it and the plugin source is eligible; CurseForge
plugin dependency resolution is limited to Bukkit/Spigot/Paper
plugin entries.

Synthetic transitive entries are placed in the lockfile section that
matches the dependency project's platform content type, not
necessarily the parent entry's section. If Modrinth and CurseForge
resolve the same transitive identity to different content types, the
resolver fails and asks the user to declare a top-level entry in the
intended section.

### Slug-table index

After top-level entries resolve, gitrinth builds a slug-to-entry
index per `(section, platform, host)` tuple — not just per platform.
`flywheel` resolved on modrinth.com and `flywheel` resolved on a
labrinth instance are not automatically the same logical mod; they
go through the same hash-based merge logic that already covers
slug divergence (in practice they will hash-match and merge
silently, but the resolver doesn't conflate them by name alone).
For packs without `modrinth_host:` the index collapses to one entry
per `(section, platform)`, matching the original shape:

```text
modrinth_slug_to_entry = { 'create' → create, 'sodium' → sodium, ... }
cf_slug_to_entry       = { 'create' → create, 'sodium-fabric' → sodium, ... }
```

When a transitive dep comes up during resolution, the resolver
maps the dependency's content type to a section and checks that
section's index before creating a synthetic entry:

- **Dep slug matches a top-level entry on the same platform** —
  reuse that top-level entry. The transitive version constraint is
  merged into the top-level's constraint; a conflict errors.
- **No match on that platform** — resolve the dep on the same
  requested platform set as `add`, build a synthetic entry,
  cross-check hashes when more than one platform participates, and
  lock.

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
`hash_scan_depth` window used by top-level verification) between
Modrinth-only and CF-only synthetics in the same section. When hashes
match, the two merge into one dual-source synthetic:

- **Canonical key**: the Modrinth slug (Modrinth is the primary
  platform, so its slug wins).
- **CF-side slug** is recorded as a `curseforge:` override field on
  the merged synthetic.
- Both platforms' `required_by:` lists are unioned.

If no hash match is found in the scan window, the two synthetics
stay separate and an info-level message points the user at an
explicit remediation:

```text
info: transitive dependency 'flywheel' (Modrinth) and
'flywheel-forge' (CurseForge) may refer to the same logical mod but
no hash-matching version was found within hash_scan_depth.

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
a `required_by:` list so [`deps`](todo.md#deps-command) can show the
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
    required_by: [create]          # from both platforms' create
    modrinth: { ... }
    curseforge: { ... }

  fabric-api:                      # transitive, synthetic
    version: 0.102.0
    required_by: [create, sodium]
    modrinth: { ... }
    curseforge: { ... }
```

User-declared top-level entries shadow synthetics: if `flywheel`
appears in `mods.yaml`, it's treated as top-level; `required_by:`
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
| Same as above but hashes differ and scan fails                                                                                         | Error — user declares top-level `fabric-api` with `sources:` or `allow_hash_mismatch: true` |
| CF-only `ae2` transitively requires CF `some-lib`; Modrinth has no `some-lib` project                                                  | Single-source synthetic `some-lib` with `sources: [curseforge]`                             |

## Mixing CF and Modrinth in one pack

Entries coexist under the same section maps (`mods:`,
`resource_packs:`, `data_packs:`, `shaders:`, `plugins:`).
`mods.lock` records one block per resolved source with the
platform-specific project/file identifiers plus hash. Missing and
omitted source blocks follow
[Lockfile source states](#lockfile-source-states).

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

plugins:
  # In a Paper/Bukkit/Spigot plugin pack, plugins can be dual-source.
  luckperms:
    version: 5.5.17
    modrinth: { project_id: ..., version_id: ..., sha512: ... }
    curseforge: { project_id: ..., file_id: ..., sha512: ... }
```

[`deps`](todo.md#deps-command) surfaces per-platform source
information in its output. Transitive deps are cross-deduplicated
per
[Transitive dependencies](#transitive-dependencies-and-deduplication).
For `plugins:`, a CurseForge source block can only appear when the
resolved plugin loader is Bukkit, Spigot, or Paper.

## Publishing to CurseForge

Redefine [`publish_to`](mods-yaml.md#publish_to) as a publish-target
selector rather than a Modrinth host field. `modrinth_host:` remains
the default Modrinth/labrinth source host for resolving entries; it
does not opt the pack into publishing and does not select the
Modrinth publish destination. When `publish_to` is unset, publishing
targets the enabled platform set from the `gitrinth:` block (Modrinth
only by default). Explicit `publish_to` values can target one or both
platforms in a single
[`publish`](todo.md#publish-command) run.

Accepted `publish_to` values:

| Value                                   | Meaning                                                 |
|-----------------------------------------|---------------------------------------------------------|
| unset / `null`                          | Publish to enabled platforms; Modrinth only by default. |
| `none`                                  | Disable publishing for this pack.                       |
| `modrinth`                              | Publish to Modrinth only, default host.                 |
| `curseforge`                            | Publish to CurseForge only.                             |
| `[modrinth]`                            | Publish to Modrinth only, default host.                 |
| `[curseforge]`                          | Publish to CurseForge only.                             |
| `[modrinth, curseforge]`                | Publish to both platforms, default hosts.               |
| `{ modrinth: <url>, curseforge: null }` | Publish to both; custom Modrinth host.                  |
| `{ modrinth: <url> }`                   | Publish to Modrinth only; custom host.                  |
| `{ curseforge: null }`                  | Publish to CurseForge only.                             |

The parser normalizes scalar, list, and map forms into a unique target
set with optional per-target config. Empty lists, duplicate list
targets, invalid target names, and `none` inside a list or map are
schema errors. In map form, the presence of a platform key enables
that target; a `true` value is not required. `modrinth` may be set to
a URL string to select a non-default Modrinth-compatible publishing
host. `curseforge` currently has no config, so use `null` (or an empty
mapping if future config fields are needed). URL strings are no longer
accepted as the top-level `publish_to` scalar. Explicit
`publish_to: curseforge`, `[curseforge]`, or a `curseforge:` map key
opts that publish operation into CurseForge even when
`gitrinth.curseforge` is disabled by default.

```yaml
# Resolve Modrinth-source entries against a labrinth instance by
# default, but publish only to CurseForge.
modrinth_host: https://labrinth.internal.example
publish_to: curseforge

# Publish to a non-default Modrinth-compatible host.
publish_to:
  modrinth: https://modrinth.example.com

# Publish to both, with an explicit Modrinth publishing host.
publish_to:
  modrinth: https://modrinth.example.com
  curseforge:
```

Add a CurseForge manifest emitter to the archive builder — CF packs
ship as `manifest.json` + `overrides/` in a `.zip`.
[`pack`](cli.md#pack) grows a `--curseforge` flag;
[`publish`](todo.md#publish-command) becomes platform-aware.

Entries not available on the target platform get bundled as loose
overrides (with author permission). `publish` warns; `--publishable`
on [`pack`](cli.md#pack) escalates to an error, scoped to the target
being built, and also surfaces entries with
`allow_hash_mismatch: true` because the published artifact ships only
one of the two divergent builds.

Plugin publishing follows the same eligibility rule as resolution:
CurseForge can publish or reference only Bukkit/Spigot/Paper-compatible
plugin entries. A `plugins:` entry in a Sponge or Folia pack is not a
CurseForge project reference; for a CurseForge target it must either be
excluded, bundled as a loose override with permission, or make the
publishable build fail. The archive writer must keep the target path
server-side (`plugins/<jar>`) even when the entry is emitted as a loose
override rather than a CF addon reference.

## Hosted Modrinth (labrinth)

Folded in alongside the cross-platform work because the same
multi-host resolver and token-store wiring backs both — keeping it
on a separate roadmap would mean designing the same refactor twice.
Independent of the rest, though: this slice does not require the CF
API client, so it can land first.

The schema field today is named `hosted:`; that name is ambiguous
(hosted what? where?). Rename it to `modrinth_host:` so the protocol
it speaks (the Modrinth API) is explicit and so the same spelling can
be reused as a pack-level default. Behavior described
under [Fetching mods → Host overrides](#host-overrides) covers the
runtime semantics.

Concrete work:

- Rename `hosted` → `modrinth_host` in
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
- Add a top-level `modrinth_host:` field to the manifest schema and
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

| Path                                                                                                                                                                      | Status | Role in bridge                                                                                                                                                                                                                                                                                                                                                   |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`lib/src/model/manifest/mods_yaml.dart`](../lib/src/model/manifest/mods_yaml.dart)                                                                                       | exists | Add `modrinth:` / `curseforge:` slug overrides, `sources:` (scalar or list), hash flags, source eligibility helpers, and `gitrinth.modrinth` / `gitrinth.curseforge` platform toggles; grow `ModrinthEntrySource` with an optional host (or add a peer); add pack-level `modrinth_host:` and normalized `publish_to` target config to the top-level manifest model |
| [`lib/src/model/manifest/parser.dart`](../lib/src/model/manifest/parser.dart)                                                                                             | exists | Rename `hosted` → `modrinth_host`, normalize hyphenated fields to underscores, drop the deferred-source guard, parse the new entry and pack-level fields plus the top-level `gitrinth:` block (with `gitrinth.version` semver constraint and `gitrinth.modrinth` / `gitrinth.curseforge` platform toggles, replacing the old `tooling:` block), reject CurseForge plugin sources outside Bukkit/Spigot/Paper loaders                                                                                                   |
| [`lib/src/model/manifest/mods_lock.dart`](../lib/src/model/manifest/mods_lock.dart)                                                                                       | exists | Per-source hash blocks for every section, `not_found` markers, `discovered_via_search`, `required_by:`, plugin lock blocks                                                                                                                                                                                                                                       |
| [`lib/src/service/resolve_and_sync.dart`](../lib/src/service/resolve_and_sync.dart) and [`lib/src/model/resolver/resolver.dart`](../lib/src/model/resolver/resolver.dart) | exists | Multi-source branching; today's single-source `if (entry.source is! ModrinthEntrySource)` early-out (in both files) becomes the dispatch point; apply section-aware source eligibility before network resolution                                                                                                                                                 |
| [`lib/src/service/modrinth_api.dart`](../lib/src/service/modrinth_api.dart)                                                                                               | exists | Already supports per-call `baseUrl`; needs a host-keyed factory so each labrinth host gets its own client + rate-limit budget                                                                                                                                                                                                                                    |
| `lib/src/service/curseforge_api.dart`                                                                                                                                     | new    | Retrofit client mirroring `ModrinthApi` shape, including content-type filters and Bukkit/Spigot/Paper plugin compatibility filters                                                                                                                                                                                                                               |
| [`lib/src/service/user_config.dart`](../lib/src/service/user_config.dart)                                                                                                 | exists | Token lookup by host already supported via `tokens: Map<String, String>`                                                                                                                                                                                                                                                                                         |
| [`lib/src/cli/runner.dart`](../lib/src/cli/runner.dart)                                                                                                                   | exists | Wire new commands, including `gitrinth curseforge enable/disable` and `gitrinth modrinth enable/disable`                                                                                                                                                                                                                                                         |
| [`lib/src/commands/add_command.dart`](../lib/src/commands/add_command.dart)                                                                                               | exists | `cf:` short form that writes `sources: curseforge` without enabling pack-wide CF, `--[no-]modrinth` / `--[no-]curseforge` / `--allow-hash-mismatch` flags, plugin-source eligibility errors                                                                                                                                                                      |
| [`lib/src/commands/pack_assembler.dart`](../lib/src/commands/pack_assembler.dart) and [`lib/src/commands/pack_command.dart`](../lib/src/commands/pack_command.dart)       | exists | Add CF archive/manifest output, target-scoped publishability checks, and `plugins/<jar>` override paths for plugin entries                                                                                                                                                                                                                                       |
| `lib/src/commands/curseforge.dart`                                                                                                                                        | new    | Hosts CF-specific subcommands, starting with `enable` / `disable` for `gitrinth.curseforge`                                                                                                                                                                                                                                                                       |
| `lib/src/commands/token_command.dart`                                                                                                                                     | new    | `token add` / `list` / `remove` (also referenced from [`todo.md`](todo.md#token-command))                                                                                                                                                                                                                                                                        |
| [`assets/schema/mods.schema.yaml`](../assets/schema/mods.schema.yaml)                                                                                                     | exists | Rename `hosted` → `modrinth_host`; normalize hyphenated fields to underscores; add new entry fields; add `gitrinth.modrinth` / `gitrinth.curseforge` enum toggles; add pack-level `modrinth_host:` and `publish_to` target config; express plugin-source eligibility where schema can, leaving loader-dependent checks to the parser                               |
| [`docs/mods-yaml.md`](mods-yaml.md)                                                                                                                                       | exists | Update `hosted:` → `modrinth_host:` in docs and examples; document renamed underscore fields; document new entry shape; remove "Modrinth-only" framing where it's no longer accurate; document CurseForge plugin limits                                                                                                                                          |
| [`docs/cli.md`](cli.md)                                                                                                                                                   | exists | `cf:` short form, new `add` flags, platform enable/disable commands, plugin-source errors, `token` subcommands, `--curseforge` on `pack`                                                                                                                                                                                                                         |
