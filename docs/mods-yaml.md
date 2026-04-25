# The `mods.yaml` file

Every modpack managed by **gitrinth** has a `mods.yaml` file at its root. It
declares the modpack's identity, publishing metadata, target Minecraft
loader and version, and the mods that belong to it.

The `gitrinth` CLI reads `mods.yaml` to pull each declared mod from
[Modrinth](https://modrinth.com) (or another configured source), resolve a
version of every mod that satisfies its compatibility requirements, and
assemble client and server distributions.

A machine-readable schema lives alongside this document at
[mods.schema.yaml](../assets/schema/mods.schema.yaml).

## Supported fields

A `mods.yaml` file can contain the following top-level fields. The required
fields are [`slug`](#slug), [`name`](#name), [`version`](#version),
[`description`](#description), [`loader`](#loader), and
[`mc-version`](#mc-version).

| Field                               | Required | Description                                                                                                                                                                                                                            |
|-------------------------------------|----------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`slug`](#slug)                     | yes      | Modrinth project slug for the modpack.                                                                                                                                                                                                 |
| [`name`](#name)                     | yes      | Human-readable display name.                                                                                                                                                                                                           |
| [`version`](#version)               | yes      | The semver version of the modpack.                                                                                                                                                                                                     |
| [`description`](#description)       | yes      | Short, public-facing tagline.                                                                                                                                                                                                          |
| [`project`](#project)               | no       | Modrinth project metadata — links, body, license, categories, client/server compatibility. See below for the full list of sub-fields.                                                                                                  |
| [`publish_to`](#publish_to)         | no       | Where the modpack publishes to.                                                                                                                                                                                                        |
| [`loader`](#loader)                 | yes      | Per-section loaders (object). `mods` required; `shaders` required when the `shaders:` section has entries; `plugins` deferred.                                                                                                         |
| [`mc-version`](#mc-version)         | yes      | The exact Minecraft version the modpack targets (e.g. `1.21.1`).                                                                                                                                                                       |
| [`tooling`](#tooling)               | no       | Version constraints on the tooling used to build the modpack (currently just `gitrinth`).                                                                                                                                              |
| [`mods`](#mods)                     | no       | Every mod in the pack. Each entry may declare a per-mod [per-side install state](#sides-client--server) (`client`, `server`, or `both`). May be blank while the pack is being assembled.                                               |
| [`resource_packs`](#resource_packs) | no       | Resource packs to ship with the pack. Same syntax as `mods`.                                                                                                                                                                           |
| [`data_packs`](#data_packs)         | no       | Data packs to ship with the pack. Same syntax as `mods`.                                                                                                                                                                               |
| [`shaders`](#shaders)               | no       | Shader packs. Same syntax as `mods`. Defaults to `client: required, server: unsupported`; `server` cannot be set otherwise.                                                                                                            |
| [`plugins`](#plugins)               | no       | Server plugins. Same syntax as `mods`. Defaults to `client: unsupported, server: required`.                                                                                                                                            |
| [`overrides`](#overrides)           | no       | Overrides that win over matching entries in `mods`, `resource_packs`, `data_packs`, `shaders`, or `plugins`.                                                                                                                           |
| [`files`](#files)                   | no       | Loose files (configs, scripts) keyed by destination path. Copied into the build tree by `build` and bundled into the appropriate `*-overrides/` root by `pack`. Optional `preserve: true` skips overwriting existing files on rebuild. |

Unknown top-level fields are ignored by `gitrinth`, but the CLI will emit a
warning so typos don't silently disable options.

## Example

```yaml
slug: example_modpack
name: Example Modpack
version: 0.1.0
description: A short, public-facing summary of the modpack.

project:
  body: ./README.md
  source_url: https://github.com/example/modpack
  issues_url: https://github.com/example/modpack/issues
  wiki_url: https://example.com/modpack/docs
  discord_url: https://discord.gg/example
  license_id: MIT
  license_url:
  categories:
    - multiplayer
    - technology
  additional_categories:
    - magic
  client_side: required
  server_side: required

publish_to: https://modrinth.com

loader:
  mods: neoforge
  shaders: iris
mc-version: 1.21.1

tooling:
  gitrinth: ^1.0.0

mods:
  create: ^6.0.10+mc1.21.1
  create-aeronautics: ^1.1.0+mc1.21.1
  sable: ^1.1.1+mc1.21.1
  jei: ^19.27.0.340
  iris:
    version: ^1.8.12+1.21.1-neoforge
    client: required
    server: unsupported
  netherportalfix:
    version: ^21.1.1+neoforge-1.21.1
    client: unsupported
    server: required

resource_packs:
  faithful-32x: ^1.21.1

data_packs:
  terralith: ^2.5.4

shaders:
  complementary-shaders: ^4.7.2

plugins:
  luckperms: ^5.4.0

overrides:
  jei:
    version: 19.27.0.340
```

## Details

Each supported field is described in detail below.

### `slug`

**Required.** The Modrinth project slug for the modpack — the URL segment
at `modrinth.com/modpack/<slug>`. Also used in generated artifact
filenames and lockfile entries.

A valid `slug`:

- uses only lowercase ASCII letters, digits, and underscores (`a`–`z`,
  `0`–`9`, `_`);
- starts with a letter;
- is not a YAML reserved word.

```yaml
slug: example_modpack
```

### `name`

**Required.** The modpack's human-readable display name. This is what
appears on the Modrinth project page and in launcher UIs, so use whatever
casing, spacing, and punctuation reads best. Maps to Modrinth's `title`
field. Any non-empty string is accepted.

```yaml
name: Example Modpack
```

### `version`

**Required.** The version of the modpack itself (not the Minecraft version).
Must be a valid [semantic version](https://semver.org) such as `1.0.0`,
`2.1.3`, or `0.4.0-beta.1`. `gitrinth` expects the version to be incremented
with each published release.

```yaml
version: 0.1.0
```

### `description`

**Required.** A short, human-readable summary of the modpack — the
tagline shown under the project title in Modrinth listings and in
launcher UIs. Keep it concise; one or two sentences is ideal, and
Modrinth truncates long descriptions in listings. For the long-form
project body, use [`project.body`](#body).

```yaml
description: A tech-focused modpack centred around Create and its addons.
```

### `project`

**Optional.** Modrinth project metadata. Every sub-field maps 1:1 to the
corresponding field in Modrinth's [`createProject`
API](https://docs.modrinth.com/api/operations/createproject/). The whole
block may be omitted, set to `null`, or partially filled.

```yaml
project:
  body: ./README.md
  source_url: https://github.com/example/modpack
  issues_url: https://github.com/example/modpack/issues
  wiki_url: https://example.com/modpack/docs
  discord_url: https://discord.gg/example
  license_id: MIT
  license_url:
  categories:
    - multiplayer
    - technology
  additional_categories:
    - magic
  client_side: required
  server_side: required
```

#### `body`

**Optional.** Long-form project description shown on the Modrinth project
page (the short tagline is [`description`](#description), one level up).

The value is either inline markdown, or a path — relative to `mods.yaml`
— to a markdown file. If the value resolves to an existing file,
`gitrinth` reads the file at publish time; otherwise the value is sent
as literal markdown. To force literal markdown that shares a filename
with a real file, use a YAML `|` block.

```yaml
project:
  body: ./README.md
```

#### `source_url`

**Optional.** URL of the public source repository hosting `mods.yaml`
and any supporting files.

```yaml
project:
  source_url: https://github.com/example/modpack
```

#### `issues_url`

**Optional.** URL of the modpack's issue tracker. Defaults to the
repository's issues page when [`source_url`](#source_url) points at a
known host such as GitHub or GitLab.

```yaml
project:
  issues_url: https://github.com/example/modpack/issues
```

#### `wiki_url`

**Optional.** URL pointing at user-facing documentation for the modpack.

```yaml
project:
  wiki_url: https://example.com/modpack/docs
```

#### `discord_url`

**Optional.** Discord invite URL for the modpack's community.

```yaml
project:
  discord_url: https://discord.gg/example
```

#### `license_id`

**Optional.** SPDX identifier of the modpack's license (for example
`MIT`, `Apache-2.0`, `GPL-3.0-or-later`). Use `LicenseRef-<custom>` for
non-standard licenses.

```yaml
project:
  license_id: MIT
```

#### `license_url`

**Optional.** URL pointing at the full license text. Usually omitted for
standard SPDX licenses.

```yaml
project:
  license_url: https://example.com/modpack/LICENSE
```

#### `categories`

**Optional.** Primary Modrinth modpack categories applied when publishing.
Entries must match Modrinth's catalogue of modpack tags (for example
`adventure`, `multiplayer`, `technology`, `magic`).

```yaml
project:
  categories:
    - multiplayer
    - technology
```

#### `additional_categories`

**Optional.** Secondary Modrinth categories for the modpack. Same values
as [`categories`](#categories), but listed here so they are searchable
without appearing as primary tags on the Modrinth project page.

```yaml
project:
  additional_categories:
    - magic
    - adventure
```

#### `client_side`

**Optional.** Client-side compatibility declared for the modpack, shown
on the Modrinth project page.

| Value         | Meaning                                                       |
|---------------|---------------------------------------------------------------|
| `required`    | The modpack requires a client install to function (default).  |
| `optional`    | The modpack can be used on the client but doesn't have to be. |
| `unsupported` | The modpack cannot be installed on the client.                |
| `unknown`     | Compatibility is not declared.                                |

Defaults to `required` when omitted.

```yaml
project:
  client_side: required
```

#### `server_side`

**Optional.** Server-side compatibility declared for the modpack, shown
on the Modrinth project page.

| Value         | Meaning                                                       |
|---------------|---------------------------------------------------------------|
| `required`    | The modpack requires a server install to function (default).  |
| `optional`    | The modpack can be used on the server but doesn't have to be. |
| `unsupported` | The modpack cannot be installed on the server.                |
| `unknown`     | Compatibility is not declared.                                |

Defaults to `required` when omitted.

```yaml
project:
  server_side: required
```

### `publish_to`

**Optional.** URL of the Modrinth-compatible server `gitrinth publish`
uploads the modpack to.

| Value   | Meaning                                                        |
|---------|----------------------------------------------------------------|
| *unset* | Publish to modrinth.com (the default).                         |
| *URL*   | Publish to the Modrinth-compatible server at that URL instead. |

```yaml
publish_to: https://modrinth.example.com
```

### `loader`

**Required.** An object declaring which loader applies to each kind
of content the pack ships. Different content types on Modrinth use
different loader vocabularies — a shader version is tagged `iris`,
not `neoforge` — so each section that has a choice declares its own
loader.

```yaml
loader:
  mods: neoforge
  shaders: iris
```

Recognised keys:

| Key              | Required                                                           | Values                                   |
|------------------|--------------------------------------------------------------------|------------------------------------------|
| `loader.mods`    | **Yes.**                                                           | `forge`, `fabric`, `neoforge` (MVP).     |
| `loader.shaders` | When [`shaders:`](#shaders) has entries.                           | `iris`, `optifine`, `canvas`, `vanilla`. |
| `loader.plugins` | Deferred — accepted by the schema, rejected by the CLI in the MVP. | `bukkit`, `folia`, `paper`, `spigot`.    |

`resource_packs` and `data_packs` each have a single valid Modrinth
loader (`minecraft` and `datapack` respectively), so they are not
declared under `loader`.

`loader.mods` has three roles:

- **Version resolution.** When picking the version of each entry in
  [`mods`](#mods) and [`overrides`](#overrides) (when the override
  targets a mod), `gitrinth` only considers published mod versions
  tagged with this loader. Combined with
  [`mc-version`](#mc-version), this determines which "latest"
  version satisfies a blank or caret
  [mod-version constraint](#mod-version-constraints).
- **Published compatibility.** When `gitrinth publish` uploads the
  modpack, `loader.mods` is declared as the modpack's supported
  loader on Modrinth. End users see it on the project page, and
  launchers use it to decide whether the pack is installable.
- **Server distribution selection.** The server distribution
  assembled by [`gitrinth build`](cli.md#build) includes the
  matching server binary — the Forge/Fabric/NeoForge/Sponge
  installer for the pack's [`mc-version`](#mc-version), or the
  latest stable Paper/Spigot/Folia build for that `mc-version` (or a
  vanilla-derived jar for `bukkit`). `gitrinth` resolves the binary
  automatically from `loader.mods` + [`mc-version`](#mc-version); the
  modpack does not declare it, and it is not added manually after
  the build. Pinning the exact build is deferred to a future
  release.

`loader.shaders` applies version resolution for entries under
[`shaders:`](#shaders): `gitrinth` only considers shader versions
tagged with the declared shader loader. Leaving it out while `shaders:`
has entries is a parse error, with a message pointing at the missing
key.

Omitting the object entirely, supplying a scalar value
(`loader: neoforge`), or adding an unknown key (`loader: { foo: bar }`)
is a parse error. `gitrinth` rejects any value outside the enums above.

#### Plugin loaders

`bukkit`, `folia`, `paper`, and `spigot` (set via `loader.plugins`
when plugin support lands) are plugin-based server platforms — they
do not run Forge/Fabric-style client mods. Under one of these loaders:

- Every entry under [`mods`](#mods) is bundled into the **client-side
  modpack only**, regardless of any per-mod
  [per-side install state](#sides-client--server) value. (Mods do not load on a
  plugin server, so shipping them to the server side would be dead
  weight.)
- [`plugins`](#plugins) ship to the server distribution — always, the
  same as under every other loader.
- [`resource_packs`](#resource_packs) and [`data_packs`](#data_packs)
  behave the same way they do under `forge`/`fabric`/`neoforge` — data
  packs are world-level content that plugin servers load natively, and
  resource packs can still be served to clients. Their per-mod
  [per-side install state](#sides-client--server) is honoured.
- [`shaders`](#shaders) remain client-only, the same as under every
  other loader.

`forge`, `fabric`, `neoforge`, and `sponge` apply no such override:
every entry honours its declared [per-side install state](#sides-client--server).

### `mc-version`

**Required.** The exact Minecraft release the modpack targets, for
example `1.21.1`. Version ranges and wildcards are intentionally
disallowed — a modpack targets a single Minecraft version so that
mod-version resolution is deterministic. Like [`loader`](#loader),
`mc-version` has three roles:

- **Version resolution.** When picking the version of each entry in
  [`mods`](#mods), [`resource_packs`](#resource_packs),
  [`data_packs`](#data_packs), [`shaders`](#shaders),
  [`plugins`](#plugins), and [`overrides`](#overrides), `gitrinth` only
  considers published versions tagged with this Minecraft version.
  Combined with [`loader`](#loader), this is what makes blank and caret
  [mod-version constraints](#mod-version-constraints) resolve
  deterministically.
- **Published compatibility.** When `gitrinth publish` uploads the
  modpack, `mc-version` is declared as the modpack's supported
  Minecraft version on Modrinth. End users see it on the project page,
  and launchers use it to decide whether the pack is installable.
- **Server distribution selection.** Together with [`loader`](#loader),
  `mc-version` is what `gitrinth` uses to pick the server binary
  bundled into the server distribution. The user does not specify the
  server binary, and it is not added after the build — see the
  [Server distribution selection](#loader) role on `loader`.

```yaml
mc-version: 1.21.1
```

### `tooling`

**Optional.** Version constraints on the tooling used to build the
modpack. The block may be omitted entirely when no constraint is needed.

```yaml
tooling:
  gitrinth: ^1.0.0
```

| Key        | Required | Description                                                                                                                |
|------------|----------|----------------------------------------------------------------------------------------------------------------------------|
| `gitrinth` | no       | A version constraint on the `gitrinth` CLI itself, using semver range syntax (for example `^1.0.0` or `">=1.0.0 <2.0.0"`). |

#### `gitrinth`

Declares which versions of the `gitrinth` CLI the modpack is known to work
with. Unlike mod versions, this field accepts the full semver range syntax
(`^`, `>=`, `<`, `<=`, `>`), because the compatibility window for the tool
itself may span several majors.

```yaml
tooling:
  gitrinth: ^1.0.0
```

### Mod dependencies

[`mods`](#mods), [`resource_packs`](#resource_packs),
[`data_packs`](#data_packs), [`shaders`](#shaders), [`plugins`](#plugins),
and [`overrides`](#overrides) all map a Modrinth project slug to a **mod
dependency**. Every entry takes one of two forms — a short form (just a
version constraint) or a long form (a map with a source, a version, and/or
a per-mod [per-side install state](#sides-client--server)).

**Keys are Modrinth project slugs.** Every key under `mods`,
`resource_packs`, `data_packs`, `shaders`, `plugins`, and `overrides` is
the Modrinth project slug — the URL segment at
`modrinth.com/<project-type>/<slug>` — not Modrinth's internal project
`id`. For example, the mod at `modrinth.com/mod/jei` uses the key `jei`.
Slugs are globally unique across project types, so `overrides` entries
resolve unambiguously.

#### Short form

The value is a [mod-version constraint](#mod-version-constraints). The mod
is fetched from the default Modrinth instance.

```yaml
mods:
  create: ^6.0.10+mc1.21.1
  jei: ^19.27.0.340
  iris:
```

#### Long form

The value is a map with any combination of:

- a `version` — a [mod-version constraint](#mod-version-constraints);
- a `channel` — a [release-channel floor](#release-channel-channel);
- a `client:` and/or `server:` install state — see [Sides](#sides-client--server);
- an `accepts-mc` widening — see [Per-entry MC version tolerance](#per-entry-mc-version-tolerance-accepts-mc);
- at most one **source** — where `gitrinth` should fetch the mod from.

```yaml
mods:
  # Hosted on a custom Modrinth-compatible server.
  journeymap:
    hosted: https://modrinth.example.com
    version: ^5.10.0

  # Direct download URL.
  custom_mod:
    url: https://example.com/path/to/custom_mod.jar

  # Local path relative to mods.yaml.
  local_mod:
    path: ./mods/local_mod.jar

  # Long form with only per-side install state.
  iris:
    client: required
    server: unsupported
```

Each entry must specify **at most one** of `hosted`, `url`, or `path`.
Omitting all three is equivalent to `hosted:` on the default Modrinth
instance — useful when you only want to express a version constraint
or per-side install state in the long form.

| Source   | Publishable? | Notes                                                |
|----------|--------------|------------------------------------------------------|
| *(none)* | yes          | Default Modrinth instance.                           |
| `hosted` | yes          | Any Modrinth-compatible server. Value is a base URL. |
| `url`    | no           | Direct download URL for a `.jar`.                    |
| `path`   | no           | Local filesystem path relative to `mods.yaml`.       |

**Caution.** For [`mods`](#mods) entries (and [`overrides`](#overrides)
targeting a mod), `url` and `path` sources produce a modpack that is
not publishable to Modrinth. `gitrinth publish` will refuse to upload
it and will name the entries responsible. These sources are permitted
for [`resource_packs`](#resource_packs), [`data_packs`](#data_packs),
[`shaders`](#shaders), and [`plugins`](#plugins) without affecting
publishability — the Publishable? column above applies only when the
entry is a mod.

#### Release channel (`channel`)

A long-form entry may include a `channel` field to set a **stability floor**
on the version_type values the resolver accepts for that entry. Modrinth tags
every version as `release`, `beta`, or `alpha`; `channel` admits the stated
tier *and every more-stable tier* — never an exact-match filter.

| Value     | Admits                 | Use when                                                                                       |
|-----------|------------------------|------------------------------------------------------------------------------------------------|
| `release` | release only           | The pack should ship only stable builds for this entry.                                        |
| `beta`    | release + beta         | A stable build doesn't yet exist for the target `mc-version`, but a tagged beta is acceptable. |
| `alpha`   | release + beta + alpha | The mod only publishes alpha builds, or the pack tracks bleeding-edge versions deliberately.   |

Omitting `channel` defaults to `alpha`, matching Modrinth's default of returning
every `version_type`. The floor is applied **before** the
[mod-version constraint](#mod-version-constraints) — a `channel: release` entry
with a caret range that only resolves to a beta build will fail to resolve
rather than silently fall through to the beta.

```yaml
mods:
  # Use the latest stable version tagged `release` on Modrinth
  # Defaults to alpha, so no releases are filtered
  sodium: release

  # You can also filter by version and channel
  # This prevents newer alpha releases from being chosen, even if they match the version constraint
  distanthorizons:
    version: ^2.3.0
    channel: beta
```

`channel` is only available on long-form entries and works in the same
sections that support long form — [`mods`](#mods),
[`resource_packs`](#resource_packs), [`data_packs`](#data_packs),
[`shaders`](#shaders), and [`plugins`](#plugins).

#### Sides (`client` / `server`)

Each long-form entry may declare its install state on each side of the
pack independently. The two fields share the same vocabulary, and the
values pass through verbatim into the produced `.mrpack`'s per-file
`env` block.

| Value         | Meaning                                                                                                        |
|---------------|----------------------------------------------------------------------------------------------------------------|
| `required`    | Install the entry on this side. The launcher cannot disable it.                                                |
| `optional`    | Install the entry on this side, but expose a launcher-side toggle so the user can disable it.                  |
| `unsupported` | Do not install the entry on this side at all. The build pipeline skips it and `.mrpack` records `unsupported`. |

If both sides are `unsupported`, the entry would not install anywhere
and the parser rejects it.

**Per-section defaults** (used when an entry omits `client:` / `server:`,
including every short-form entry):

| Section          | `client` default | `server` default |
|------------------|------------------|------------------|
| `mods`           | `required`       | `required`       |
| `shaders`        | `required`       | `unsupported`    |
| `data_packs`     | `required`       | `required`       |
| `resource_packs` | `optional`       | `unsupported`    |

`shaders` enforces `server: unsupported` (any other value is a schema
error) and rejects `client: unsupported` (the entry would not install
anywhere). `resource_packs` default to optional on the client because
they are typically toggleable cosmetic content; data packs default to
required because they usually drive worldgen or game rules that the
pack relies on.

```yaml
mods:
  create: ^6.0.10+mc1.21.1   # short form → both sides required (default)
  iris:
    version: ^1.8.12+1.21.1-neoforge
    client: required
    server: unsupported
  spark:
    version: ^1.10.0
    client: unsupported
    server: required
  distanthorizons:
    version: beta
    client: optional         # launcher checkbox on the client
    server: optional         # and on the server (dedicated server admin
                             # can toggle it too)
```

**Build path consequences.** When `gitrinth build` produces the loose
output under `build/<env>/`, data packs and resource packs route into
the `global_packs/` tree the [`globalpacks`](https://modrinth.com/mod/globalpacks)
mod loads from:

| Section          | `<side>: required`                             | `<side>: optional`                             |
|------------------|------------------------------------------------|------------------------------------------------|
| `data_packs`     | `build/<env>/global_packs/required_data/`      | `build/<env>/global_packs/optional_data/`      |
| `resource_packs` | `build/<env>/global_packs/required_resources/` | `build/<env>/global_packs/optional_resources/` |

`mods/` and `shaderpacks/` keep their conventional subdirs. The
`.mrpack` archive is unaffected — `files[]` and `overrides/` continue
to use `mods/`, `datapacks/`, `resourcepacks/`, and `shaderpacks/` so
launchers without `globalpacks` install the artifacts to the
canonical locations.

**Migration.** The previous `environment:` enum (`client | server | both`)
and `optional: true` flag were removed. Translate as follows:

| Was                                      | Becomes                                      |
|------------------------------------------|----------------------------------------------|
| (omitted)                                | (omit `client:` / `server:`; defaults apply) |
| `environment: client`                    | `client: required`, `server: unsupported`    |
| `environment: server`                    | `client: unsupported`, `server: required`    |
| `optional: true`                         | `client: optional`, `server: optional`       |
| `environment: client` + `optional: true` | `client: optional`, `server: unsupported`    |
| `environment: server` + `optional: true` | `client: unsupported`, `server: optional`    |

The parser raises a clear migration error if a manifest still uses the
old fields, so a stale `mods.yaml` will fail loud rather than silently
ship under the wrong defaults.

#### Per-entry MC version tolerance (`accepts-mc`)

A long-form entry may include an `accepts-mc` field to **additively**
widen the Minecraft versions the resolver queries for that one entry.
The pack's [`mc-version`](#mc-version) remains the single source of
truth: `accepts-mc` never overrides it, never influences the server
binary or loader, and never applies to other entries.

Use it when a mod works on the pack's `mc-version` but the author
only tagged adjacent versions on Modrinth. For example, a pack on
`1.21.1` with a mod that's still tagged `1.21`:

```yaml
mc-version: 1.21.1
mods:
  appleskin:
    version: ^3.0.9+mc1.21
    accepts-mc: 1.21           # scalar shorthand for [1.21]
  some-other-mod:
    version: ^2.0.0
    accepts-mc: [1.21, 1.20.1] # explicit list form
```

Snapshot-style tags are accepted too — Modrinth publishes a single
`game_versions` list that mixes releases with weekly snapshots
(`24w10a`), pre-releases (`1.21-pre1`), release candidates
(`1.21-rc1`), and historical tags (`b1.7.3`). Any of these are valid
values.

At resolve time, the Modrinth `game_versions` filter for `appleskin`
becomes `["1.21.1", "1.21"]` instead of `["1.21.1"]`; every other
entry in the pack is unaffected. The resolved version's actual
Modrinth `game_versions` tag is recorded in `mods.lock` under
`game-versions:`, so a future `mc-version` bump can surface entries
that were only admitted via `accepts-mc`.

`accepts-mc` is only available on long-form entries and works in the
same sections that support long form — [`mods`](#mods),
[`resource_packs`](#resource_packs), [`data_packs`](#data_packs),
[`shaders`](#shaders), and [`plugins`](#plugins). When adding a new
mod, [`add`](cli.md#add) takes a repeatable `--accepts-mc` flag that
widens the Modrinth query and persists the list into the written
entry in one step.

#### Mod-version constraints

A mod-version constraint describes which version of a mod is acceptable.
Three forms are supported:

| Form  | Example            | Meaning                                                                                                                                                       |
|-------|--------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Exact | `19.27.0.340`      | Use this version and no other. Resolution fails if it is not compatible with the environment or with another mod.                                             |
| Blank | *(empty value)*    | Use the **latest** version of the mod that is compatible with the declared [`loader`](#loader) and [`mc-version`](#mc-version) and every other mod.           |
| Caret | `^6.0.10+mc1.21.1` | Use the latest version that is both compatible with the environment and *compatible with* `6.0.10+mc1.21.1` (same major for `1.x.y`, same minor for `0.x.y`). |

The version string itself is whatever the mod author publishes — copy it
exactly as it appears on Modrinth. `gitrinth` doesn't constrain the
format, so entries like `6.0.10+mc1.21.1`, `1.8.12+1.21.1-neoforge`,
`r5.7.1`, and `3.0.1-b-1.21.1` (a Distant Horizons beta pre-release)
are all valid. A leading `^` turns any of them into a caret
constraint.

Caret ranges also accept a **truncated pre-release label** — `^3.0.1-b`
matches `3.0.1-b`, every richer pre-release like `3.0.1-b-1.21.1`, and
any later stable `3.x` release. Useful when an author publishes a
family of betas tagged `-b-<mc>` and you want to track all of them
without pinning to a specific Minecraft suffix.

Blank short-form entries must still include the trailing colon:

```yaml
mods:
  iris:
```

Since the Minecraft version and loader already live in
[`loader`](#loader) and [`mc-version`](#mc-version), a shorter
constraint like `^6.0.10` is usually enough; `gitrinth` picks the
matching build.

##### Exact pins: semver vs. build-number

Exact constraints come in two flavours, distinguished by whether any
Modrinth build metadata (the part after `+`) is present and, if so,
whether it's all-numeric:

| Constraint        | Build metadata       | Flavour              | Matches                                                   |
|-------------------|----------------------|----------------------|-----------------------------------------------------------|
| `6.0.10`          | none                 | **semver pin**       | any candidate with major/minor/patch/pre-release `6.0.10` |
| `6.0.10+mc1.21.1` | tag (non-numeric)    | **semver pin**       | same as above — the `+mc...` tag is informational         |
| `19.27.0+340`     | `+340` (all-numeric) | **build-number pin** | only the specific build `19.27.0+340`                     |
| `19.27.0.340`     | 4-segment → `+340`   | **build-number pin** | only `19.27.0.340` / `19.27.0+340`                        |

A **semver pin** ignores build metadata on candidates. Use it when you
want "the `6.0.10` release, whichever `+mc...` Modrinth happened to
tag it with". A **build-number pin** is strict. Use it when the trailing
number is a real build counter you want to freeze exactly (most
commonly 4-segment versions like JEI's `19.27.0.340`).

The [`pin` command](cli.md#pin) writes the flavour that matches the
locked version: tag metadata (`+mc...`) is stripped because it's
cosmetic; numeric build segments are preserved because they narrow
the match.

##### Arbitrary-string version names

Some mods publish versions that aren't semver-shaped at all — e.g.
`release-snapshot-xyz` or `winter-2025-drop`. `gitrinth` accepts these
as **exact pins only**: the constraint matches iff its raw string is
identical to a candidate's `version_number`.

```yaml
mods:
  weirdmod: release-snapshot-xyz
```

Carets (`^`) don't work on arbitrary strings — they derive an upper
bound by bumping the major component, which has no meaning without a
semver base. `^release-snapshot-xyz` is rejected at parse time with
an `Invalid version constraint` error.

When [`add`](cli.md#add) resolves a slug and Modrinth returns a
non-semver version, it falls back to writing the raw version as an
exact pin (no caret). Subsequent [`get`](cli.md#get) runs won't pick
up newer versions automatically — edit the pin by hand when a new
release comes out.

### `mods`

**Optional.** Every mod in the pack. Keys are [Modrinth project
slugs](#mod-dependencies); values use the [mod
dependency](#mod-dependencies) syntax — short form (version only) or
long form (source, version, and/or [per-side install state](#sides-client--server)).

The field may be blank (`mods:` with no value, or omitted entirely) while
the modpack is still being assembled — `gitrinth` will resolve and
publish a pack with zero mods if asked to.

```yaml
mods:
  create: ^6.0.10+mc1.21.1
  create-aeronautics: ^1.1.0+mc1.21.1
  sable: ^1.1.1+mc1.21.1
  jei: ^19.27.0.340
  iris:
    version: ^1.8.12+1.21.1-neoforge
    client: required
    server: unsupported
  journeymap:
    hosted: https://modrinth.example.com
    version: ^5.10.0
```

### `resource_packs`

**Optional.** Resource packs to ship with the modpack. Keys are [Modrinth
project slugs](#mod-dependencies) (from `modrinth.com/resourcepack/<slug>`);
values use the same [mod dependency](#mod-dependencies) syntax as
[`mods`](#mods).

```yaml
resource_packs:
  faithful-32x: ^1.21.1                # default: client optional
  branding-pack:
    version: ^1.0.0
    client: required                    # mandatory on the client
```

### `data_packs`

**Optional.** Data packs to ship with the modpack. Keys are [Modrinth
project slugs](#mod-dependencies) (from `modrinth.com/datapack/<slug>`);
values use the same [mod dependency](#mod-dependencies) syntax as
[`mods`](#mods).

```yaml
data_packs:
  terralith: ^2.5.4
  incendium: ^5.3.4
```

### `shaders`

**Optional.** Shader packs to ship with the modpack. Keys are [Modrinth
project slugs](#mod-dependencies) (from `modrinth.com/shader/<slug>`);
values use the same [mod dependency](#mod-dependencies) syntax as
[`mods`](#mods). Shader entries always have `server: unsupported` (any
other value is a schema error) and cannot set `client: unsupported` —
the per-section default is `client: required, server: unsupported`,
and `client: optional` is the only meaningful override.

```yaml
shaders:
  complementary-shaders: ^4.7.2
  bsl-shaders:
```

### `plugins`

**Optional.** Server plugins to ship with the modpack. Keys are [Modrinth
project slugs](#mod-dependencies) (from `modrinth.com/plugin/<slug>`);
values use the same [mod dependency](#mod-dependencies) syntax as
[`mods`](#mods). Plugin entries default to `client: unsupported,
server: required` — the inverse of shaders.

```yaml
plugins:
  luckperms: ^5.4.0
  worldedit: ^7.3.0
```

### `overrides`

**Optional.** Overrides for individual entries in [`mods`](#mods),
[`resource_packs`](#resource_packs), [`data_packs`](#data_packs),
[`shaders`](#shaders), or [`plugins`](#plugins). Keys are [Modrinth
project slugs](#mod-dependencies); values use the same [mod
dependency](#mod-dependencies) syntax and take precedence over any
matching entry in those fields.

Use `overrides` to pin a version, flip the
[per-side install state](#sides-client--server), or redirect an entry to a
different source without editing the main list — for example when testing
a local build or a fork.

```yaml
overrides:
  # Pin a version but keep the default Modrinth source.
  jei:
    version: 19.27.0.340

  # Redirect to a local build.
  create:
    path: ./mods/create-dev.jar
```

Because keys are globally unique across Modrinth project types, a single
`overrides` entry unambiguously targets one entry in `mods`,
`resource_packs`, `data_packs`, `shaders`, or `plugins`.

Overrides may also live in a companion
[`mods_overrides.yaml`](mods-overrides-yaml.md) file — an object
with a single top-level `overrides:` key carrying the same map.
When both are present, entries in `mods_overrides.yaml` win on
conflicting keys and all other keys are unioned.

### `files`

Loose files copied into the build tree alongside mods. Use `files:`
for content that is not a Modrinth-resolvable artifact: per-mod config
files (`config/sodium-options.json`), KubeJS scripts, vanilla
`options.txt`, server config files, and so on.

Keys are destination paths relative to the build env root
(`build/<env>/`). Each value declares a local source path, optional
per-side state, and an optional `preserve` flag.

```yaml
files:
  config/sodium-options.json:
    path: ./presets/sodium-options.json
    preserve: true
  kubejs/server_scripts/loot.js:
    path: ./scripts/loot.js
    client: unsupported
    server: required
  options.txt:
    path: ./client-defaults/options.txt
    server: unsupported
```

Per-entry fields:

| Field      | Type    | Default    | Description                                                                                                   |
|------------|---------|------------|---------------------------------------------------------------------------------------------------------------|
| `path`     | string  | (required) | Source path relative to `mods.yaml`.                                                                          |
| `client`   | enum    | `required` | Install state on the client side. `required` or `unsupported`. (`optional` is reserved.)                      |
| `server`   | enum    | `required` | Install state on the server side. `required` or `unsupported`. (`optional` is reserved.)                      |
| `preserve` | boolean | `false`    | When `true`, [`build`](cli.md#build) does not overwrite an existing destination. First-install-only behavior. |

Destination keys must be relative, normalized, non-empty paths with
forward-slash separators. `..` segments, leading `/` or `\`, embedded
`.\` or `//`, and `\` separators are rejected at parse time.

#### `preserve: true` semantics

`preserve: true` makes the file *first-install-only*. After the first
build copies the file to its destination, subsequent builds skip the
copy as long as the destination still exists — letting users edit the
deployed config without their changes being trampled.

`preserve` is **not sticky**: removing the entry from `files:` prunes
the file on the next build, even if it was previously preserved. Treat
`preserve` as "don't overwrite," not as "never delete." If you need a
file to persist after the entry is removed, use a per-mod config
default (which mods install themselves on first run) instead.

#### How `files` interacts with `build` and `pack`

[`gitrinth build`](cli.md#build) copies each in-scope `files:` entry to
its destination under `build/<env>/`. The build also writes a side-car
ledger (`build/<env>/.gitrinth-state.yaml`) that records every managed
path; on subsequent runs, files in the prior ledger but not in the new
desired set are pruned, while user-dropped loose files (anything not
in the prior ledger) are never touched.

[`gitrinth pack`](cli.md#pack) bundles each `files:` entry into the
appropriate Modrinth `.mrpack` overrides root based on per-side state:

- `client: required, server: required` → `overrides/<destination>`
- `client: required, server: unsupported` → `client-overrides/<destination>`
- `client: unsupported, server: required` → `server-overrides/<destination>`

`files:` entries do not trip the [`--publishable`](cli.md#pack)
restriction — Modrinth's permission policy targets executable mod
jars under `mods/`, not loose configs.

#### `optional` is reserved

`client: optional` and `server: optional` are rejected on `files:`
entries in v1. Modrinth's `.mrpack` format has no env/toggle metadata
on loose overrides (only on Modrinth-CDN `files[]` entries), and
`gitrinth build` has no UI toggle, so the flag would have no
observable effect anywhere. The reservation will be lifted once a
real consumer-side toggle mechanism appears.

## Resolution

When `gitrinth` installs or updates a modpack it:

1. Reads `mods.yaml` and validates its structure against the schema.
2. Merges [`overrides`](#overrides) with any
   [`mods_overrides.yaml`](mods-overrides-yaml.md) (the latter wins
   on conflicting keys), then applies the merged map on top of the
   matching entries in [`mods`](#mods),
   [`resource_packs`](#resource_packs), [`data_packs`](#data_packs),
   [`shaders`](#shaders), and [`plugins`](#plugins) to produce the
   final set of dependencies.
3. For each entry, queries Modrinth (or the override source) for every
   version whose `loader` and `mc-version` match the modpack's
   [`loader`](#loader) and [`mc-version`](#mc-version).
4. Filters that list with the entry's version constraint.
5. Picks the highest remaining version, preferring versions that are
   compatible with every *other* entry's declared dependencies.
6. Partitions the resolved entries into client and server distributions
   using each entry's [per-side install state](#sides-client--server)
   (per-section defaults apply when fields are omitted; shaders default
   to `server: unsupported`, resource packs default to `server:
   unsupported`; when [`loader`](#loader) is `bukkit`, `folia`, `paper`,
   or `spigot`, [`mods`](#mods) entries are additionally forced to
   client-only — see [Plugin loaders](#plugin-loaders)).
7. Writes the chosen versions to `mods.lock` so subsequent runs are
   reproducible.

If step 4 yields an empty set for any entry, resolution fails and
`gitrinth` reports which constraint was unsatisfiable.

## See also

- [`mods.schema.yaml`](../assets/schema/mods.schema.yaml) — machine-readable schema.
- [Dart `pubspec.yaml` reference](https://dart.dev/tools/pub/pubspec) — the
  specification this file is modelled on.
- [Modrinth API docs](https://docs.modrinth.com) — for the project slugs,
  categories, and version identifiers used above.
- [Modrinth `createProject` reference](https://docs.modrinth.com/api/operations/createproject/)
  — canonical documentation for every field under [`project`](#project).
