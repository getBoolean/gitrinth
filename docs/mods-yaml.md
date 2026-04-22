# The `mods.yaml` file

Every modpack managed by **gitrinth** has a `mods.yaml` file at its root. It
declares the modpack's identity, publishing metadata, target Minecraft
environment, and the mods that belong to it.

The `gitrinth` CLI reads `mods.yaml` to pull each declared mod from
[Modrinth](https://modrinth.com) (or another configured source), resolve a
version of every mod that satisfies its compatibility requirements, and
assemble client and server distributions.

A machine-readable schema lives alongside this document at
[mods.schema.yaml](mods.schema.yaml).

## Supported fields

A `mods.yaml` file can contain the following top-level fields. The required
fields are [`slug`](#slug), [`name`](#name), [`version`](#version),
[`description`](#description), and [`environment`](#environment).

| Field                               | Required | Description                                                                                                                                                                    |
|-------------------------------------|----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`slug`](#slug)                     | yes      | Modrinth project slug for the modpack.                                                                                                                                         |
| [`name`](#name)                     | yes      | Human-readable display name.                                                                                                                                                   |
| [`version`](#version)               | yes      | The semver version of the modpack.                                                                                                                                             |
| [`description`](#description)       | yes      | Short, public-facing tagline.                                                                                                                                                  |
| [`project`](#project)               | no       | Modrinth project metadata — links, body, license, gallery, categories, client/server compatibility. See below for the full list of sub-fields.                                 |
| [`publish_to`](#publish_to)         | no       | Where the modpack publishes to.                                                                                                                                                |
| [`environment`](#environment)       | yes      | Target loader and Minecraft version.                                                                                                                                           |
| [`mods`](#mods)                     | no       | Every mod in the pack. Each entry may declare a per-mod [`environment`](#per-mod-environment) (`client`, `server`, or `both`). May be blank while the pack is being assembled. |
| [`resource_packs`](#resource_packs) | no       | Resource packs to ship with the pack. Same syntax as `mods`.                                                                                                                   |
| [`data_packs`](#data_packs)         | no       | Data packs to ship with the pack. Same syntax as `mods`.                                                                                                                       |
| [`shaders`](#shaders)               | no       | Shader packs to ship with the pack. Same syntax as `mods`.                                                                                                                     |
| [`overrides`](#overrides)           | no       | Overrides that win over matching entries in `mods`, `resource_packs`, `data_packs`, or `shaders`.                                                                              |
| [`servers`](#servers)               | no       | Default servers embedded in the client's multiplayer menu.                                                                                                                     |

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
  donation_urls:
    - platform: ko-fi
      url: https://ko-fi.com/example
  categories:
    - multiplayer
    - technology
  additional_categories:
    - magic
  client_side: required
  server_side: required
  gallery:
    - ./screenshots/overview.png
    - ./screenshots/base.png

publish_to: https://modrinth.com

environment:
  loader: neoforge
  mc-version: 1.21.1
  gitrinth: ^1.0.0

mods:
  create: ^6.0.10+mc1.21.1
  create-aeronautics: ^1.1.0+mc1.21.1
  sable: ^1.1.1+mc1.21.1
  jei: ^19.27.0.340
  iris:
    version: ^1.8.12+1.21.1-neoforge
    environment: client
  netherportalfix:
    version: ^21.1.1+neoforge-1.21.1
    environment: server

resource_packs:
  faithful-32x: ^1.21.1

data_packs:
  terralith: ^2.5.4

shaders:
  complementary-shaders: ^4.7.2

overrides:
  jei:
    version: 19.27.0.340

servers:
  - name: Example Server
    address: play.example.com
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
  donation_urls:
    - platform: ko-fi
      url: https://ko-fi.com/example
  categories:
    - multiplayer
    - technology
  additional_categories:
    - magic
  client_side: required
  server_side: required
  gallery:
    - ./screenshots/overview.png
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

#### `donation_urls`

**Optional.** Links to platforms where users can donate to the modpack
author. Each entry is an object with a `platform` and a `url`. The
`gitrinth` CLI expands `platform` into Modrinth's separate `id` and
display-name pair at publish time, so the list below is exhaustive and
custom values are rejected.

| Key        | Required | Description                                                             |
|------------|----------|-------------------------------------------------------------------------|
| `platform` | yes      | Modrinth donation-platform identifier. Must be one of the values below. |
| `url`      | yes      | Donation URL on the platform.                                           |

Supported `platform` values, sourced from Modrinth's
`GET /tag/donation_platform` endpoint:

| `platform` | Displayed as      |
|------------|-------------------|
| `patreon`  | Patreon           |
| `bmac`     | Buy Me A Coffee   |
| `paypal`   | PayPal            |
| `github`   | GitHub Sponsors   |
| `ko-fi`    | Ko-fi             |
| `other`    | Other             |

```yaml
project:
  donation_urls:
    - platform: ko-fi
      url: https://ko-fi.com/example
    - platform: patreon
      url: https://patreon.com/example
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

#### `gallery`

**Optional.** A list of screenshots to upload as part of the modpack's
Modrinth gallery. Each entry is a path relative to `mods.yaml`.

```yaml
project:
  gallery:
    - ./screenshots/overview.png
    - ./screenshots/base.png
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

### `environment`

**Required.** Describes the target Minecraft environment for the modpack.

```yaml
environment:
  loader: neoforge
  mc-version: 1.21.1
  gitrinth: ^1.0.0
```

| Key          | Required | Description                                                                                                                |
|--------------|----------|----------------------------------------------------------------------------------------------------------------------------|
| `loader`     | yes      | The mod loader. One of `forge`, `fabric`, `neoforge` (also accepted as `neoForge`).                                        |
| `mc-version` | yes      | The **exact** Minecraft version (for example `1.21.1`). Ranges are not permitted.                                          |
| `gitrinth`   | no       | A version constraint on the `gitrinth` CLI itself, using semver range syntax (for example `^1.0.0` or `">=1.0.0 <2.0.0"`). |

#### `loader`

Supported loaders:

- `forge`
- `fabric`
- `neoforge` — also accepted as `neoForge` for compatibility with the
  project's brand casing. The lowercase spelling matches Modrinth's
  loader tag and is preferred.

Values are plain YAML strings and do not need to be quoted:

```yaml
environment:
  loader: neoforge
```

`gitrinth` rejects any value outside the list above.

#### `mc-version`

`mc-version` must be an exact Minecraft release such as `1.21.1`. Version
ranges and wildcards are intentionally disallowed — a modpack targets a
single Minecraft version so that mod-version resolution is deterministic.

#### `gitrinth`

Declares which versions of the `gitrinth` CLI the modpack is known to work
with. Unlike mod versions, this field accepts the full semver range syntax
(`^`, `>=`, `<`, `<=`, `>`), because the compatibility window for the tool
itself may span several majors.

### Mod dependencies

[`mods`](#mods), [`resource_packs`](#resource_packs),
[`data_packs`](#data_packs), [`shaders`](#shaders), and
[`overrides`](#overrides) all map a Modrinth project slug to a **mod
dependency**. Every entry takes one of two forms — a short form (just a
version constraint) or a long form (a map with a source, a version, and/or
a per-mod [`environment`](#per-mod-environment)).

**Keys are Modrinth project slugs.** Every key under `mods`,
`resource_packs`, `data_packs`, `shaders`, and `overrides` is the Modrinth
project slug — the URL segment at `modrinth.com/<project-type>/<slug>` —
not Modrinth's internal project `id`. For example, the mod at
`modrinth.com/mod/jei` uses the key `jei`. Slugs are globally unique
across project types, so `overrides` entries resolve unambiguously.

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
- an `environment` — see [Per-mod environment](#per-mod-environment);
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

  # GitHub-style "owner/repo" shorthand.
  forked_mod:
    git: getBoolean/forked_mod

  # Git source with a specific ref and sub-path.
  deep_mod:
    git:
      url: https://github.com/example/deep_mod.git
      ref: main
      path: mods/deep_mod
    version: ^1.2.0

  # Long form with only a per-mod environment.
  iris:
    environment: client
```

Each entry must specify **at most one** of `hosted`, `url`, `path`, or
`git`. Omitting all four is equivalent to `hosted:` on the default
Modrinth instance — useful when you only want to express a version
constraint or an `environment` in the long form.

| Source   | Publishable? | Notes                                                |
|----------|--------------|------------------------------------------------------|
| *(none)* | yes          | Default Modrinth instance.                           |
| `hosted` | yes          | Any Modrinth-compatible server. Value is a base URL. |
| `url`    | no           | Direct download URL for a `.jar`.                    |
| `path`   | no           | Local filesystem path relative to `mods.yaml`.       |
| `git`    | no           | See [Git sources](#git-sources).                     |

**Caution.** For [`mods`](#mods) entries (and [`overrides`](#overrides)
targeting a mod), `url`, `path`, and `git` sources produce a modpack
that is not publishable to Modrinth. `gitrinth publish` will refuse to
upload it and will name the entries responsible. These sources are
permitted for [`resource_packs`](#resource_packs),
[`data_packs`](#data_packs), and [`shaders`](#shaders) without affecting
publishability — the Publishable? column above applies only when the
entry is a mod.

#### Git sources

The `git` source fetches a mod directly from a Git repository. It is the
easiest way to depend on a fork, a pre-release branch, or a mod that is
not published to Modrinth at all.

Three forms are accepted:

```yaml
mods:
  # 1. GitHub "owner/repo" shorthand.
  #    Expanded to https://github.com/<owner>/<repo>.git and checked
  #    out on the repository's default branch.
  forked_jei:
    git: example/forked_jei

  # 2. A full git URL — https, ssh, or git:// — again on the default
  #    branch.
  forked_iris:
    git: https://github.com/example/forked_iris.git

  # 3. An object form with url, ref, and/or path.
  deep_mod:
    git:
      url: git@github.com:example/monorepo.git
      ref: mc-1.21.1-backports
      path: mods/deep_mod
    version: ^1.2.0
```

The object form accepts:

- **`url`** *(required)* — Any Git-supported URL: `https://…`,
  `git@host:…` (SSH), `git://…`, or a local path. SSH URLs are the
  recommended way to reach private repositories: `gitrinth` shells out
  to the ambient `git` CLI, so your usual SSH keys and credential
  helpers work without extra configuration.
- **`ref`** *(optional)* — Any reference `git checkout` will accept — a
  branch name, tag, or full commit hash. Defaults to the repository's
  default branch. For reproducible builds, prefer a tag or commit hash
  over a branch.
- **`path`** *(optional)* — Path **inside** the repository where the mod
  lives, relative to the repo root. Use this when a single repo hosts
  more than one mod (a monorepo layout). Defaults to the repo root.

The resolved tree — the repository at `ref`, entered at `path` — must
contain a `mods.toml` file describing the mod. `gitrinth` reads that file
for the mod's identifier, version, and declared mod dependencies.

When both a `version` constraint and a `git` source are specified, the
constraint is matched against the `version` declared inside the resolved
`mods.toml` rather than against a Modrinth version. Resolution fails if
the two disagree, which guards against accidentally pulling a branch
that has drifted out of the expected version range.

**Caching.** Git sources are cloned into `gitrinth`'s local cache on
first resolution and re-used on subsequent runs. Pinning `ref` to a tag
or commit hash is the simplest way to keep collaborators' client and
server builds locked to the same revision.

**Publishing.** As with `url` and `path`, a `git` source makes the
modpack non-publishable to Modrinth.

#### Per-mod environment

A long-form mod entry may include an `environment` field that restricts
which side of the pack the mod is shipped with.

| Value    | Meaning                                                                                                                          |
|----------|----------------------------------------------------------------------------------------------------------------------------------|
| `client` | Include the mod only in the client distribution.                                                                                 |
| `server` | Include the mod only in the server distribution.                                                                                 |
| `both`   | Include the mod on both sides. This is the default when `environment` is omitted, and is the only option for short-form entries. |

```yaml
mods:
  create: ^6.0.10+mc1.21.1   # short form → ships to both sides
  iris:
    version: ^1.8.12+1.21.1-neoforge
    environment: client
  spark:
    version: ^1.10.0
    environment: server
  jei:
    environment: client      # no version → latest compatible, client only
```

Because `environment` is a per-mod property, a mod cannot be simultaneously
client-only and server-only. To restrict the side, switch the short-form
entry to long form and add the field.

#### Mod-version constraints

A mod-version constraint describes which version of a mod is acceptable.
Three forms are supported:

| Form  | Example            | Meaning                                                                                                                                                       |
|-------|--------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Exact | `19.27.0.340`      | Use this version and no other. Resolution fails if it is not compatible with the environment or with another mod.                                             |
| Blank | *(empty value)*    | Use the **latest** version of the mod that is compatible with [`environment`](#environment) and every other mod.                                              |
| Caret | `^6.0.10+mc1.21.1` | Use the latest version that is both compatible with the environment and *compatible with* `6.0.10+mc1.21.1` (same major for `1.x.y`, same minor for `0.x.y`). |

The version string itself is whatever the mod author publishes — copy it
exactly as it appears on Modrinth. `gitrinth` doesn't constrain the
format, so entries like `6.0.10+mc1.21.1`, `1.8.12+1.21.1-neoforge`, and
`r5.7.1` are all valid. A leading `^` turns any of them into a caret
constraint.

Blank short-form entries must still include the trailing colon:

```yaml
mods:
  iris:
```

Since the Minecraft version and loader already live in
[`environment`](#environment), a shorter constraint like `^6.0.10` is
usually enough; `gitrinth` picks the matching build.

### `mods`

**Optional.** Every mod in the pack. Keys are [Modrinth project
slugs](#mod-dependencies); values use the [mod
dependency](#mod-dependencies) syntax — short form (version only) or
long form (source, version, and/or [`environment`](#per-mod-environment)).

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
    environment: client
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
  faithful-32x: ^1.21.1
  xalis-enchanted-books:
    version: ^1.3.0
    environment: client
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
[`mods`](#mods). Shaders are always client-only regardless of any per-mod
[`environment`](#per-mod-environment).

```yaml
shaders:
  complementary-shaders: ^4.7.2
  bsl-shaders:
```

### `overrides`

**Optional.** Overrides for individual entries in [`mods`](#mods),
[`resource_packs`](#resource_packs), [`data_packs`](#data_packs), or
[`shaders`](#shaders). Keys are [Modrinth project
slugs](#mod-dependencies); values use the same [mod
dependency](#mod-dependencies) syntax and take precedence over any
matching entry in those fields.

Use `overrides` to pin a version, flip the
[`environment`](#per-mod-environment), or redirect an entry to a
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

  # Use a fork from git.
  iris:
    git: my-org/iris-fork
    version: ^1.8.12
```

Because keys are globally unique across Modrinth project types, a single
`overrides` entry unambiguously targets one entry in `mods`,
`resource_packs`, `data_packs`, or `shaders`.

### `servers`

**Optional.** Default servers embedded in the client distribution's
multiplayer menu. Each entry is an object with a `name` and an `address`.

| Key       | Required | Description                                                             |
|-----------|----------|-------------------------------------------------------------------------|
| `name`    | yes      | Display name shown in the multiplayer server list.                      |
| `address` | yes      | Server address, optionally including a port (`play.example.com:25565`). |

```yaml
servers:
  - name: Example Server
    address: play.example.com
  - name: Community Realms
    address: realms.example.com:25566
```

Servers only appear in the client distribution; they are ignored when
building the server distribution.

## Resolution

When `gitrinth` installs or updates a modpack it:

1. Reads `mods.yaml` and validates its structure against the schema.
2. Applies [`overrides`](#overrides) on top of the matching entries in
   [`mods`](#mods), [`resource_packs`](#resource_packs),
   [`data_packs`](#data_packs), and [`shaders`](#shaders) to produce the
   final set of dependencies.
3. For each entry, queries Modrinth (or the override source) for every
   version whose `loader` and `mc-version` match
   [`environment`](#environment).
4. Filters that list with the entry's version constraint.
5. Picks the highest remaining version, preferring versions that are
   compatible with every *other* entry's declared dependencies.
6. Partitions the resolved entries into client and server distributions
   using each entry's [`environment`](#per-mod-environment) (default
   `both`; shaders and the [`servers`](#servers) list are always
   client-only).
7. Writes the chosen versions to `mods.lock` so subsequent runs are
   reproducible.

If step 4 yields an empty set for any entry, resolution fails and
`gitrinth` reports which constraint was unsatisfiable.

## See also

- [`mods.schema.yaml`](mods.schema.yaml) — machine-readable schema.
- [Dart `pubspec.yaml` reference](https://dart.dev/tools/pub/pubspec) — the
  specification this file is modelled on.
- [Modrinth API docs](https://docs.modrinth.com) — for the project slugs,
  categories, and version identifiers used above.
- [Modrinth `createProject` reference](https://docs.modrinth.com/api/operations/createproject/)
  — canonical documentation for every field under [`project`](#project).
