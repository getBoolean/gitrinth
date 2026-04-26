# The `project_overrides.yaml` file

> **v2 rename.** This file was previously named `mods_overrides.yaml`,
> with a top-level key of `overrides:`. Rename the file to
> `project_overrides.yaml` and the top-level key to
> `project_overrides:` — contents are otherwise unchanged.

`project_overrides.yaml` is an optional companion to
[`mods.yaml`](mods-yaml.md). It carries the same content as the
[`project_overrides`](mods-yaml.md#project_overrides) section —
overrides for individual entries in [`mods`](mods-yaml.md#mods),
[`resource_packs`](mods-yaml.md#resource_packs),
[`data_packs`](mods-yaml.md#data_packs),
[`shaders`](mods-yaml.md#shaders), or
[`plugins`](mods-yaml.md#plugins), plus an injection seam for
purely-transitive Modrinth project dependencies — factored into its
own file so it can be gitignored, swapped per environment, or edited
without touching the main manifest.

A machine-readable schema lives alongside this document at
[project-overrides.schema.yaml](../assets/schema/project-overrides.schema.yaml).

## Shape

The file has a single top-level `project_overrides:` key whose value
is the same map used by the
[`project_overrides`](mods-yaml.md#project_overrides) section of
`mods.yaml`. Keys are [Modrinth project
slugs](mods-yaml.md#mod-dependencies); values use the
[mod-dependency](mods-yaml.md#mod-dependencies) syntax (short or
long form).

```yaml
# project_overrides.yaml
project_overrides:
  jei:
    version: 19.27.0.340

  create:
    path: ./mods/create-dev.jar
```

An empty file, a file containing just `project_overrides:` with no
value, or one containing `project_overrides: null` is treated as no
overrides.

## Relationship to `mods.yaml`

`project_overrides.yaml` **coexists** with the
[`project_overrides`](mods-yaml.md#project_overrides) section in
`mods.yaml`. When both declare the same key, the entry from
`project_overrides.yaml` wins; all other keys from both sources are
unioned.

The merged override map is then applied exactly as described in the
[resolution](mods-yaml.md#resolution) sequence.

## Why a separate file?

- **Gitignore-friendly.** Commit `mods.yaml` but keep
  `project_overrides.yaml` untracked when it carries local-only
  paths or forks.
- **Per-environment.** Swap in a different `project_overrides.yaml`
  without editing the manifest.
- **Smaller diffs.** Experiments that flip entries to local builds
  never touch the shared `mods.yaml`.

## See also

- [`mods.yaml` reference](mods-yaml.md) — the manifest this file
  extends. The
  [`project_overrides`](mods-yaml.md#project_overrides) section
  documents the underlying semantics.
- [`project-overrides.schema.yaml`](../assets/schema/project-overrides.schema.yaml) —
  machine-readable schema.
