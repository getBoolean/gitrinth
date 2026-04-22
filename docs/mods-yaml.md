# The `mods.yaml` file

Every modpack managed by **gitrinth** has a `mods.yaml` file at its root. This
file — modelled on Dart's [`pubspec.yaml`](https://dart.dev/tools/pub/pubspec) —
declares the modpack's identity, publishing metadata, target Minecraft
environment, and the mods that belong to it.

The `gitrinth` CLI reads `mods.yaml` to pull each declared mod from
[Modrinth](https://modrinth.com) (or another configured source), resolve a
version of every mod that satisfies its compatibility requirements, and
assemble client and server distributions.

A machine-readable schema lives alongside this document at
[mods.schema.yaml](mods.schema.yaml).

## Example

```yaml
name: example_modpack
description: A short, public-facing summary of the modpack.
version: 0.1.0

homepage: https://example.com/modpack
repository: https://github.com/example/modpack
issue_tracker: https://github.com/example/modpack/issues
documentation: https://example.com/modpack/docs

publish_to: none

gallery:
  - ./screenshots/overview.png
  - ./screenshots/base.png

categories:
  - multiplayer
  - technology

environment:
  loader: neoForge
  mc-version: 1.21.1
  gitrinth: ^1.0.0

mods:
  create: ^6.0.10+mc1.21.1
  create-aeronautics: ^1.1.0+mc1.21.1
  sable: ^1.1.1+mc1.21.1
  jei: ^19.27.0.340
  iris:

mod_overrides:
  jei:
    version: 19.27.0.340

client_mods:
  iris:

server_mods:
```

## Supported fields

A `mods.yaml` file can contain the following top-level fields. The required
fields are [`name`](#name), [`version`](#version),
[`description`](#description), [`environment`](#environment), and
[`mods`](#mods).

| Field | Required | Description |
| --- | --- | --- |
| [`name`](#name) | yes | The identifier of the modpack. |
| [`version`](#version) | yes | The semver version of the modpack. |
| [`description`](#description) | yes | A short, public description. |
| [`homepage`](#homepage) | no | URL of the modpack's home page. |
| [`repository`](#repository) | no | URL of the source repository. |
| [`issue_tracker`](#issue_tracker) | no | URL of the issue tracker. |
| [`documentation`](#documentation) | no | URL of the modpack's documentation. |
| [`publish_to`](#publish_to) | no | Where the modpack publishes to. |
| [`gallery`](#gallery) | no | Screenshots displayed on Modrinth. |
| [`categories`](#categories) | no | Modrinth categories for the modpack. |
| [`environment`](#environment) | yes | Target loader and Minecraft version. |
| [`mods`](#mods) | yes | Mods included on both client and server. |
| [`mod_overrides`](#mod_overrides) | no | Per-mod source or version overrides. |
| [`client_mods`](#client_mods) | no | Client-only mods. |
| [`server_mods`](#server_mods) | no | Server-only mods. |

Unknown top-level fields are ignored by `gitrinth`, but the CLI will emit a
warning so typos don't silently disable options.

---

### `name`

**Required.** The modpack's identifier. It appears in the filenames of
generated artifacts and in lockfile entries.

A valid `name`:

- uses only lowercase ASCII letters, digits, and underscores (`a`–`z`,
  `0`–`9`, `_`);
- starts with a letter;
- is not a Dart or YAML reserved word.

```yaml
name: example_modpack
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

**Required.** A short, human-readable summary of the modpack. This is the
text shown on the modpack's Modrinth page, so keep it concise — one or two
sentences is ideal, and Modrinth truncates long descriptions in listings.

```yaml
description: A tech-focused modpack centred around Create and its addons.
```

### `homepage`

**Optional.** URL of the modpack's home page. Use this when the modpack has
a dedicated site; otherwise prefer [`repository`](#repository).

```yaml
homepage: https://example.com/modpack
```

### `repository`

**Optional.** URL of the public source repository hosting `mods.yaml` and any
supporting files.

```yaml
repository: https://github.com/example/modpack
```

### `issue_tracker`

**Optional.** URL of the modpack's issue tracker. Defaults to the repository's
issues page when [`repository`](#repository) points at a known host such as
GitHub or GitLab.

```yaml
issue_tracker: https://github.com/example/modpack/issues
```

### `documentation`

**Optional.** URL pointing at user-facing documentation for the modpack.

```yaml
documentation: https://example.com/modpack/docs
```

### `publish_to`

**Optional.** Controls where `gitrinth publish` uploads the modpack.

| Value | Meaning |
| --- | --- |
| *unset* | Publish to Modrinth (the default). |
| `none` | Never publish. `gitrinth publish` will refuse to run. |
| *URL* | Publish to a custom Modrinth-compatible server. |

```yaml
publish_to: none
```

Setting `publish_to: none` is the recommended guard for private or work-in-
progress modpacks to prevent an accidental publish.

### `gallery`

**Optional.** A list of screenshots to upload as part of the modpack's
Modrinth gallery. Each entry is a path relative to `mods.yaml`.

```yaml
gallery:
  - ./screenshots/overview.png
  - ./screenshots/base.png
```

### `categories`

**Optional.** A list of Modrinth modpack categories applied when publishing.
Entries must match Modrinth's catalogue of modpack tags (for example
`adventure`, `multiplayer`, `technology`, `magic`).

```yaml
categories:
  - multiplayer
  - technology
```

### `environment`

**Required.** Describes the target Minecraft environment for the modpack.

```yaml
environment:
  loader: neoForge
  mc-version: 1.21.1
  gitrinth: ^1.0.0
```

| Key | Required | Description |
| --- | --- | --- |
| `loader` | yes | The mod loader. One of `forge`, `fabric`, `neoForge`. |
| `mc-version` | yes | The **exact** Minecraft version (for example `1.21.1`). Ranges are not permitted. |
| `gitrinth` | no | A version constraint on the `gitrinth` CLI itself, using Dart pub–style ranges (for example `^1.0.0` or `">=1.0.0 <2.0.0"`). |

#### `loader`

Supported loaders:

- `forge`
- `fabric`
- `neoForge`

The value is case-sensitive. `gitrinth` rejects any other value.

#### `mc-version`

`mc-version` must be an exact Minecraft release such as `1.21.1`. Version
ranges and wildcards are intentionally disallowed — a modpack targets a
single Minecraft version so that mod-version resolution is deterministic.

#### `gitrinth`

Declares which versions of the `gitrinth` CLI the modpack is known to work
with. Unlike mod versions, this field accepts the full Dart pub range syntax
(`^`, `>=`, `<`, `<=`, `>`), because the compatibility window for the tool
itself may span several majors.

---

### Mod versions

`mods`, `client_mods`, and `server_mods` all map a mod identifier to a
**mod-version constraint**. Constraints are deliberately simpler than
Dart pub's dependency syntax. Exactly three forms are supported:

| Form | Example | Meaning |
| --- | --- | --- |
| Exact | `19.27.0.340` | Use this version and no other. Resolution fails if it is not compatible with the environment or with another mod. |
| Blank | *(empty value)* | Use the **latest** version of the mod that is compatible with [`environment`](#environment) and every other mod. |
| Caret | `^6.0.10+mc1.21.1` | Use the latest version that is both compatible with the environment and *compatible with* `6.0.10+mc1.21.1` (same major for `1.x.y`, same minor for `0.x.y`). |

A mod identifier is the Modrinth project slug (the URL segment at
`modrinth.com/mod/<slug>`).

Blank constraints must still include the trailing colon:

```yaml
mods:
  iris:
```

The `+` suffix (`+mc1.21.1`, `+1.21.1-neoforge`) is the mod's Modrinth
build/loader metadata. When present on a caret constraint, the suffix is
treated as part of the required identity — only versions with a matching
suffix are considered.

Because the exact Minecraft version and loader already live in
[`environment`](#environment), most mod entries can omit the suffix and
rely on `gitrinth` to select a compatible build.

### `mods`

**Required.** Mods shipped to both the client and the server. Keys are
Modrinth project slugs; values are [mod-version constraints](#mod-versions).

```yaml
mods:
  create: ^6.0.10+mc1.21.1
  create-aeronautics: ^1.1.0+mc1.21.1
  sable: ^1.1.1+mc1.21.1
  jei: ^19.27.0.340
  iris:
```

### `mod_overrides`

**Optional.** Per-mod overrides for how `gitrinth` fetches a mod. This is the
`mods.yaml` equivalent of pub's `dependency_overrides`: entries here take
precedence over the matching entry in [`mods`](#mods),
[`client_mods`](#client_mods), or [`server_mods`](#server_mods).

Each entry is a map with at most one *source* field (`hosted`, `url`, `path`,
or `git`) and, optionally, a `version` field. If no source is specified, the
mod is still fetched from Modrinth but pinned to the given `version`.

```yaml
mod_overrides:
  jei:
    version: 19.27.0.340
  journeymap:
    hosted: https://modrinth.example.com
    version: ^5.10.0
  custom_mod:
    url: https://example.com/path/to/custom_mod.jar
  local_mod:
    path: ./mods/local_mod.jar
  forked_mod:
    git: getBoolean/forked_mod
```

| Field | Description |
| --- | --- |
| `version` | A mod-version constraint (exact, blank, or caret). |
| `hosted` | Base URL of a Modrinth-compatible server to fetch the mod from. |
| `url` | Direct download URL for a `.jar`. |
| `path` | Local filesystem path relative to `mods.yaml`. |
| `git` | A `owner/repo` reference. The repository must contain a `mods.toml` at its root describing the mod. |

**Caution.** Using `url`, `path`, or `git` produces a modpack that is not
publishable to Modrinth: `gitrinth publish` will refuse to upload it and
will explain which overrides are responsible.

### `client_mods`

**Optional.** Mods that are only included when building the client
distribution. Entries use the same syntax as [`mods`](#mods).

```yaml
client_mods:
  iris:
```

An identifier may appear in either `mods` or `client_mods` — not both. If
the same mod is needed on both sides, declare it once in `mods`.

### `server_mods`

**Optional.** Mods that are only included when building the server
distribution. Entries use the same syntax as [`mods`](#mods).

```yaml
server_mods:
  spark:
```

---

## Resolution

When `gitrinth` installs or updates a modpack it:

1. Reads `mods.yaml` and validates its structure against the schema.
2. Merges [`mods`](#mods), [`client_mods`](#client_mods), and
   [`server_mods`](#server_mods) into the set of mods to resolve, applying
   any [`mod_overrides`](#mod_overrides).
3. For each mod, queries Modrinth (or the override source) for every version
   whose `loader` and `mc-version` match [`environment`](#environment).
4. Filters that list with the mod's version constraint.
5. Picks the highest remaining version, preferring versions that are
   compatible with every *other* mod's declared dependencies.
6. Writes the chosen versions to `mods.lock` so subsequent runs are
   reproducible.

If step 4 yields an empty set for any mod, resolution fails and `gitrinth`
reports which constraint was unsatisfiable.

## See also

- [`mods.schema.yaml`](mods.schema.yaml) — machine-readable schema.
- [Dart `pubspec.yaml` reference](https://dart.dev/tools/pub/pubspec) — the
  specification this file is modelled on.
- [Modrinth API docs](https://docs.modrinth.com) — for the project slugs,
  categories, and version identifiers used above.
