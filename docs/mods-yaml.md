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
id: example_modpack
name: Example Modpack
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
  loader: neoforge
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
fields are [`id`](#id), [`name`](#name), [`version`](#version),
[`description`](#description), and [`environment`](#environment).

| Field | Required | Description |
| --- | --- | --- |
| [`id`](#id) | yes | Machine-readable identifier / Modrinth project slug. |
| [`name`](#name) | yes | Human-readable display name. |
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
| [`mods`](#mods) | no | Mods included on both client and server. May be blank while the pack is being assembled. |
| [`mod_overrides`](#mod_overrides) | no | Overrides that win over any matching entry in the lists above, same syntax as `mods`. |
| [`client_mods`](#client_mods) | no | Client-only mods. |
| [`server_mods`](#server_mods) | no | Server-only mods. |

Unknown top-level fields are ignored by `gitrinth`, but the CLI will emit a
warning so typos don't silently disable options.

---

### `id`

**Required.** The modpack's machine-readable identifier. This is the
Modrinth project slug and is also used in generated artifact filenames
and lockfile entries.

A valid `id`:

- uses only lowercase ASCII letters, digits, and underscores (`a`–`z`,
  `0`–`9`, `_`);
- starts with a letter;
- is not a Dart or YAML reserved word.

```yaml
id: example_modpack
```

### `name`

**Required.** The modpack's human-readable display name. This is what
appears on the Modrinth project page and in launcher UIs, so use whatever
casing, spacing, and punctuation reads best. Any non-empty string is
accepted.

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
  loader: neoforge
  mc-version: 1.21.1
  gitrinth: ^1.0.0
```

| Key | Required | Description |
| --- | --- | --- |
| `loader` | yes | The mod loader. One of `forge`, `fabric`, `neoforge` (also accepted as `neoForge`). |
| `mc-version` | yes | The **exact** Minecraft version (for example `1.21.1`). Ranges are not permitted. |
| `gitrinth` | no | A version constraint on the `gitrinth` CLI itself, using Dart pub–style ranges (for example `^1.0.0` or `">=1.0.0 <2.0.0"`). |

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
with. Unlike mod versions, this field accepts the full Dart pub range syntax
(`^`, `>=`, `<`, `<=`, `>`), because the compatibility window for the tool
itself may span several majors.

---

### Mod dependencies

`mods`, `client_mods`, `server_mods`, and `mod_overrides` all map a mod
identifier to a **mod dependency**. The syntax mirrors Dart pub's
[dependencies](https://dart.dev/tools/pub/dependencies): every entry takes
one of two forms — a short form (just a version constraint) or a long
form (a map with a source and, usually, a version).

A mod identifier is the Modrinth project slug (the URL segment at
`modrinth.com/mod/<slug>`).

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

The value is a map identifying a **source** — where `gitrinth` should fetch
the mod from — and, optionally, a `version` constraint.

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
```

Each entry must specify **at most one** of `hosted`, `url`, `path`, or
`git`. Omitting all four is equivalent to `hosted:` on the default
Modrinth instance — useful when you only want to express a version
constraint in the long form.

| Source | Publishable? | Notes |
| --- | --- | --- |
| *(none)* | yes | Default Modrinth instance. |
| `hosted` | yes | Any Modrinth-compatible server. Value is a base URL. |
| `url` | no | Direct download URL for a `.jar`. |
| `path` | no | Local filesystem path relative to `mods.yaml`. |
| `git` | no | `owner/repo` shorthand or a `{url, ref, path}` object. The resolved tree must contain a `mods.toml` describing the mod. |

**Caution.** `url`, `path`, and `git` sources produce a modpack that is
not publishable to Modrinth. `gitrinth publish` will refuse to upload it
and will name the entries responsible.

#### Mod-version constraints

A mod-version constraint describes which version of a mod is acceptable.
Exactly three forms are supported:

| Form | Example | Meaning |
| --- | --- | --- |
| Exact | `19.27.0.340` | Use this version and no other. Resolution fails if it is not compatible with the environment or with another mod. |
| Blank | *(empty value)* | Use the **latest** version of the mod that is compatible with [`environment`](#environment) and every other mod. |
| Caret | `^6.0.10+mc1.21.1` | Use the latest version that is both compatible with the environment and *compatible with* `6.0.10+mc1.21.1` (same major for `1.x.y`, same minor for `0.x.y`). |

Blank short-form entries must still include the trailing colon:

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

**Required.** Mods shipped to both the client and the server. Entries use
the [mod dependency](#mod-dependencies) syntax.

```yaml
mods:
  create: ^6.0.10+mc1.21.1
  create-aeronautics: ^1.1.0+mc1.21.1
  sable: ^1.1.1+mc1.21.1
  jei: ^19.27.0.340
  iris:
  journeymap:
    hosted: https://modrinth.example.com
    version: ^5.10.0
```

### `mod_overrides`

**Optional.** The direct analogue of pub's
[`dependency_overrides`](https://dart.dev/tools/pub/dependencies#dependency-overrides).
Entries use the exact same [mod dependency](#mod-dependencies) syntax as
`mods`, and take precedence over any matching entry in [`mods`](#mods),
[`client_mods`](#client_mods), or [`server_mods`](#server_mods) regardless
of which list it appears in.

Use `mod_overrides` to pin a version or redirect a mod to a different
source without editing the main `mods` list — for example when testing a
local build or a fork.

```yaml
mod_overrides:
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

### `client_mods`

**Optional.** Mods that are only included when building the client
distribution. Entries use the same [mod dependency](#mod-dependencies)
syntax as [`mods`](#mods).

```yaml
client_mods:
  iris:
```

An identifier may appear in either `mods` or `client_mods` — not both. If
the same mod is needed on both sides, declare it once in `mods`.

### `server_mods`

**Optional.** Mods that are only included when building the server
distribution. Entries use the same [mod dependency](#mod-dependencies)
syntax as [`mods`](#mods).

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
