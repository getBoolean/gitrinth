# The `mods_overrides.yaml` file

`mods_overrides.yaml` is an optional companion to
[`mods.yaml`](mods-yaml.md). It carries the same content as the
[`overrides`](mods-yaml.md#overrides) section — overrides for
individual entries in [`mods`](mods-yaml.md#mods),
[`resource_packs`](mods-yaml.md#resource_packs),
[`data_packs`](mods-yaml.md#data_packs),
[`shaders`](mods-yaml.md#shaders), or
[`plugins`](mods-yaml.md#plugins) — factored into its own file so it
can be gitignored, swapped per environment, or edited without
touching the main manifest.

A machine-readable schema lives alongside this document at
[mods-overrides.schema.yaml](../assets/schema/mods-overrides.schema.yaml).

## Shape

The file has a single top-level `overrides:` key whose value is the
same map used by the [`overrides`](mods-yaml.md#overrides) section
of `mods.yaml`. Keys are [Modrinth project
slugs](mods-yaml.md#mod-dependencies); values use the
[mod-dependency](mods-yaml.md#mod-dependencies) syntax (short or
long form).

```yaml
# mods_overrides.yaml
overrides:
  jei:
    version: 19.27.0.340

  create:
    path: ./mods/create-dev.jar
```

An empty file, a file containing just `overrides:` with no value,
or one containing `overrides: null` is treated as no overrides.

## Relationship to `mods.yaml`

`mods_overrides.yaml` **coexists** with the
[`overrides`](mods-yaml.md#overrides) section in `mods.yaml`. When
both declare the same key, the entry from `mods_overrides.yaml`
wins; all other keys from both sources are unioned.

The merged override map is then applied exactly as described in the
[resolution](mods-yaml.md#resolution) sequence.

## Why a separate file?

- **Gitignore-friendly.** Commit `mods.yaml` but keep
  `mods_overrides.yaml` untracked when it carries local-only paths
  or forks.
- **Per-environment.** Swap in a different `mods_overrides.yaml`
  without editing the manifest.
- **Smaller diffs.** Experiments that flip entries to local builds
  never touch the shared `mods.yaml`.

## See also

- [`mods.yaml` reference](mods-yaml.md) — the manifest this file
  extends. The [`overrides`](mods-yaml.md#overrides) section
  documents the underlying semantics.
- [`mods-overrides.schema.yaml`](../assets/schema/mods-overrides.schema.yaml) —
  machine-readable schema.
