# Flatten `environment` Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the top-level `environment:` wrapper in `mods.yaml`. Promote `loader` and `mc-version` to top-level fields and move `gitrinth` under a new top-level `tooling:` object.

**Architecture:** Pure schema + documentation + example refactor. No Dart parser code consumes these fields yet (`bin/gitrinth.dart` is a stub). The source of truth is `docs/mods.schema.yaml`; `example/mods.yaml` is validated against it via a `yaml-language-server` directive; `docs/mods-yaml.md` is the human-facing reference. All three must move together. The per-mod `environment` field (`client`/`server`/`both`) inside long-form mod entries is unchanged — only the top-level wrapper is being flattened.

**Tech Stack:** YAML, JSON Schema (draft 2020-12), Markdown.

**Out of scope:** The top-level field key convention is mixed (`publish_to` uses `_`, but inside the old `environment` block `mc-version` used `-`). This plan preserves `mc-version` as-is to keep the rename surgical; renaming to `mc_version` for consistency is a separate decision.

---

## File Structure

Files touched:

- **Modify** `docs/mods.schema.yaml` — remove `environment` property and its `required` entry; add top-level `loader`, `mc-version`, and `tooling` properties; add `loader` and `mc-version` to `required`.
- **Modify** `example/mods.yaml` — replace the current `platform:` block (lines 37–40, which is already out of sync with the schema) with top-level `loader:`, `mc-version:`, and a new `tooling:` block.
- **Modify** `docs/mods-yaml.md` — update the intro, the required-fields list, the top-level field table, the example, the `### environment` section (replace with `### loader`, `### mc-version`, `### tooling`), and any cross-references to `#environment` that point at the top-level field (leave per-mod `environment` references alone).

No new files. No Dart code changes (none exists for these fields).

---

## Task 1: Update the JSON Schema

**Files:**
- Modify: `docs/mods.schema.yaml`

### Step 1.1: Remove `environment` from the top-level `required` list and add `loader` + `mc-version`

- [ ] **Step**

Edit `docs/mods.schema.yaml` lines 10–15. Replace:

```yaml
required:
  - slug
  - name
  - version
  - description
  - environment
```

with:

```yaml
required:
  - slug
  - name
  - version
  - description
  - loader
  - mc-version
```

### Step 1.2: Replace the `environment` property with three top-level properties

- [ ] **Step**

In `docs/mods.schema.yaml`, replace the entire `environment:` property block (lines 193–221, inclusive of the blank line after it):

```yaml
  environment:
    type: object
    description: Target Minecraft environment for the modpack.
    additionalProperties: false
    required:
      - loader
      - mc-version
    properties:
      loader:
        type: string
        description: |
          The mod loader the modpack targets. Values
          are plain YAML strings and do not need to be quoted.
        enum:
          - forge
          - fabric
          - neoforge
      mc-version:
        type: string
        description: |
          Exact Minecraft version, e.g. "1.21.1". Ranges and wildcards are
          not permitted.
        pattern: ^\d+\.\d+(?:\.\d+)?$
      gitrinth:
        type: [string, "null"]
        description: |
          Version constraint on the gitrinth CLI, using semver range
          syntax (e.g. "^1.0.0" or ">=1.0.0 <2.0.0"). May be blank.
        minLength: 1
```

with:

```yaml
  loader:
    type: string
    description: |
      The mod loader the modpack targets. Values are plain YAML
      strings and do not need to be quoted.
    enum:
      - forge
      - fabric
      - neoforge

  mc-version:
    type: string
    description: |
      Exact Minecraft version, e.g. "1.21.1". Ranges and wildcards are
      not permitted.
    pattern: ^\d+\.\d+(?:\.\d+)?$

  tooling:
    type: [object, "null"]
    description: |
      Version constraints on the tooling used to build this modpack.
    additionalProperties: false
    properties:
      gitrinth:
        type: [string, "null"]
        description: |
          Version constraint on the gitrinth CLI, using semver range
          syntax (e.g. "^1.0.0" or ">=1.0.0 <2.0.0"). May be blank.
        minLength: 1
```

### Step 1.3: Verify the schema is still valid YAML

- [ ] **Step**

Run from the repo root:

```bash
dart run -e 'import "dart:io"; import "package:yaml/yaml.dart"; void main() { loadYaml(File("docs/mods.schema.yaml").readAsStringSync()); print("ok"); }'
```

Expected: prints `ok` and exits 0. If `package:yaml` isn't resolvable, fall back to any YAML-aware editor that reports parse errors, or use `dart pub get` first.

If that one-liner is awkward on Windows, equivalent shell check:

```bash
node -e "require('js-yaml').load(require('fs').readFileSync('docs/mods.schema.yaml','utf8')); console.log('ok')"
```

Either passes ⇒ the file parses.

### Step 1.4: Commit

- [ ] **Step**

```bash
git add docs/mods.schema.yaml
git commit -m "schema: flatten environment block into top-level loader/mc-version/tooling"
```

---

## Task 2: Update the Example

**Files:**
- Modify: `example/mods.yaml`

### Step 2.1: Replace the `platform:` block with flattened fields

- [ ] **Step**

Context: `example/mods.yaml` currently uses `platform:` (lines 37–40), which is already out of sync with the schema's `environment:`. Both names go away.

Replace lines 37–40 of `example/mods.yaml`:

```yaml
platform:
  loader: neoforge # Enum: forge, fabric, neoforge.
  mc-version: 1.21.1 # Exact version only — no ranges.
  gitrinth: ">=1.0.0 < 2.0.0" # Semver range constraint on the gitrinth CLI version.
```

with:

```yaml
loader: neoforge # Enum: forge, fabric, neoforge.
mc-version: 1.21.1 # Exact version only — no ranges.

tooling:
  gitrinth: ">=1.0.0 < 2.0.0" # Semver range constraint on the gitrinth CLI version.
```

Leave the blank line above `mods:` as-is.

### Step 2.2: Verify the example validates against the schema

- [ ] **Step**

The example has a `# yaml-language-server: $schema=../docs/mods.schema.yaml` directive on line 1, so any editor with `yaml-language-server` will flag errors live.

For a CLI check without Python, use Node's `ajv`:

```bash
npx --yes -p ajv-cli@5 -p ajv-formats@3 ajv validate \
  -s docs/mods.schema.yaml \
  -d example/mods.yaml \
  --spec=draft2020 -c ajv-formats
```

Expected: `example/mods.yaml valid`.

If `npx` is unavailable, open `example/mods.yaml` in VS Code with the YAML extension installed and confirm the "Problems" panel is empty for that file.

### Step 2.3: Commit

- [ ] **Step**

```bash
git add example/mods.yaml
git commit -m "example: flatten platform block to match schema (loader, mc-version, tooling)"
```

---

## Task 3: Update the Human-Facing Documentation

**Files:**
- Modify: `docs/mods-yaml.md`

This is the largest task because the doc references the old field in several places. Do them in document order so line numbers stay predictable.

### Step 3.1: Update the intro paragraph

- [ ] **Step**

In `docs/mods-yaml.md`, replace lines 3–5:

```markdown
Every modpack managed by **gitrinth** has a `mods.yaml` file at its root. It
declares the modpack's identity, publishing metadata, target Minecraft
environment, and the mods that belong to it.
```

with:

```markdown
Every modpack managed by **gitrinth** has a `mods.yaml` file at its root. It
declares the modpack's identity, publishing metadata, target Minecraft
loader and version, and the mods that belong to it.
```

### Step 3.2: Update the required-fields sentence

- [ ] **Step**

Replace lines 17–19:

```markdown
A `mods.yaml` file can contain the following top-level fields. The required
fields are [`slug`](#slug), [`name`](#name), [`version`](#version),
[`description`](#description), and [`environment`](#environment).
```

with:

```markdown
A `mods.yaml` file can contain the following top-level fields. The required
fields are [`slug`](#slug), [`name`](#name), [`version`](#version),
[`description`](#description), [`loader`](#loader), and
[`mc-version`](#mc-version).
```

### Step 3.3: Update the top-level field table

- [ ] **Step**

Replace the single `environment` row (currently line 29):

```markdown
| [`environment`](#environment)       | yes      | Target loader and Minecraft version.                                                                                                                                           |
```

with three rows, placed in the same location (keeping table alignment — pad with spaces so the pipe columns line up; exact whitespace inside each cell doesn't affect rendering):

```markdown
| [`loader`](#loader)                 | yes      | The mod loader the modpack targets (`forge`, `fabric`, or `neoforge`).                                                                                                         |
| [`mc-version`](#mc-version)         | yes      | The exact Minecraft version the modpack targets (e.g. `1.21.1`).                                                                                                               |
| [`tooling`](#tooling)               | no       | Version constraints on the tooling used to build the modpack (currently just `gitrinth`).                                                                                      |
```

### Step 3.4: Update the top-level example block

- [ ] **Step**

Replace lines 72–75 inside the ```` ```yaml ```` block:

```yaml
environment:
  loader: neoforge
  mc-version: 1.21.1
  gitrinth: ^1.0.0
```

with:

```yaml
loader: neoforge
mc-version: 1.21.1

tooling:
  gitrinth: ^1.0.0
```

### Step 3.5: Replace the `### environment` section with three new sections

- [ ] **Step**

Replace the entire `### environment` section (currently lines 392–439 — the section header, the intro, the example, the table, and the three subsections `#### loader`, `#### mc-version`, `#### gitrinth`):

```markdown
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
```

with:

```markdown
### `loader`

**Required.** The mod loader the modpack targets.

Supported loaders:

- `forge`
- `fabric`
- `neoforge` — also accepted as `neoForge` for compatibility with the
  project's brand casing. The lowercase spelling matches Modrinth's
  loader tag and is preferred.

Values are plain YAML strings and do not need to be quoted:

```yaml
loader: neoforge
```

`gitrinth` rejects any value outside the list above.

### `mc-version`

**Required.** The exact Minecraft release the modpack targets, for
example `1.21.1`. Version ranges and wildcards are intentionally
disallowed — a modpack targets a single Minecraft version so that
mod-version resolution is deterministic.

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
```

### Step 3.6: Fix the stray reference in the mod-version-constraints section

- [ ] **Step**

In `docs/mods-yaml.md`, replace the two-line sentence currently at lines 646–648:

```markdown
Since the Minecraft version and loader already live in
[`environment`](#environment), a shorter constraint like `^6.0.10` is
usually enough; `gitrinth` picks the matching build.
```

with:

```markdown
Since the Minecraft version and loader already live in
[`loader`](#loader) and [`mc-version`](#mc-version), a shorter
constraint like `^6.0.10` is usually enough; `gitrinth` picks the
matching build.
```

Also check the "Blank" row of the mod-version-constraints table (currently line 630):

```markdown
| Blank | *(empty value)*    | Use the **latest** version of the mod that is compatible with [`environment`](#environment) and every other mod.                                              |
```

Replace with:

```markdown
| Blank | *(empty value)*    | Use the **latest** version of the mod that is compatible with the declared [`loader`](#loader) and [`mc-version`](#mc-version) and every other mod.           |
```

### Step 3.7: Fix the Resolution section

- [ ] **Step**

In the "Resolution" section, replace step 3 (currently lines 781–783):

```markdown
3. For each entry, queries Modrinth (or the override source) for every
   version whose `loader` and `mc-version` match
   [`environment`](#environment).
```

with:

```markdown
3. For each entry, queries Modrinth (or the override source) for every
   version whose `loader` and `mc-version` match the modpack's
   [`loader`](#loader) and [`mc-version`](#mc-version).
```

### Step 3.8: Verify no stale top-level `environment` references remain

- [ ] **Step**

Run from the repo root:

```bash
grep -n "#environment" docs/mods-yaml.md
grep -n "^environment:" docs/mods-yaml.md
```

Expected: the first command returns lines only inside the **per-mod** environment section (near lines 448–453, 474, 484, 506, 596–620) — NOT the top-level `#environment` anchor. The second command returns nothing.

Cross-check that every remaining `#environment` link targets the "Per-mod environment" heading, which renders to the anchor `#per-mod-environment`. If any `#environment` link points at the (now-deleted) top-level heading, update it to `#per-mod-environment` or `#loader`/`#mc-version` as context demands.

Use the Grep tool for these two checks rather than bash `grep` per project conventions.

### Step 3.9: Commit

- [ ] **Step**

```bash
git add docs/mods-yaml.md
git commit -m "docs: flatten environment section into loader, mc-version, tooling"
```

---

## Task 4: End-to-end verification

**Files:** none (read-only verification).

### Step 4.1: Re-validate example against the updated schema

- [ ] **Step**

Run the same validation command from Step 2.2:

```bash
npx --yes -p ajv-cli@5 -p ajv-formats@3 ajv validate \
  -s docs/mods.schema.yaml \
  -d example/mods.yaml \
  --spec=draft2020 -c ajv-formats
```

Expected: `example/mods.yaml valid`.

### Step 4.2: Confirm there are no lingering references to the old shape

- [ ] **Step**

Using the Grep tool, run the following patterns across the repo (excluding `docs/superpowers/plans/` which will legitimately reference the old shape):

- `environment:\s*$` — any line declaring an `environment:` block. Expected: zero hits outside `$defs/modSource` (the per-mod `environment` enum) and `pubspec.yaml` (Dart SDK `environment:`, unrelated).
- `#environment\b` — markdown anchors. Expected: zero hits, or only references that now correctly point at `#per-mod-environment`.
- `platform:\s*$` in `example/mods.yaml` — zero hits.

If any unexpected match appears, fix it and re-run.

### Step 4.3: Final commit only if fixups were needed

- [ ] **Step**

If Step 4.2 surfaced cleanups, stage and commit them:

```bash
git add <files>
git commit -m "docs: remove lingering environment-block references"
```

Otherwise skip.

---

## Self-Review Notes

- Spec coverage: loader → top-level (Task 1.2, 3.3, 3.5); mc-version → top-level (Task 1.2, 3.3, 3.5); gitrinth → `tooling` block (Task 1.2, 3.3, 3.5). All three are in required fields list exactly where they should be (loader, mc-version required; tooling optional).
- Per-mod `environment` (client/server/both) is explicitly preserved everywhere — see Task 3.8 which guards against accidentally stripping it.
- No placeholders: every edit contains exact before/after text.
- Key-name consistency: `mc-version` preserved everywhere (not `mc_version`), matching the user's instruction.
