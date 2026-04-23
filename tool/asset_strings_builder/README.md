# asset_strings_builder

A `build_runner` builder that materialises on-disk asset files as Dart
`String` declarations in a single generated library. Each asset is
base64-encoded into the source and decoded once at first access via a
top-level `final`, keeping the generated file binary-safe.

## Consumer setup

This package is intended to be consumed via Dart's
[workspaces](https://dart.dev/tools/pub/workspaces) feature. Vendor it under
the consumer's `tool/` directory (or any path you prefer) and declare it as
a workspace member.

Consumer's `pubspec.yaml`:

```yaml
environment:
  sdk: ^3.11.0   # workspaces require >=3.6.0

workspace:
  - tool/asset_strings_builder

dev_dependencies:
  asset_strings_builder: any
  build_runner: ^2.4.0
```

The vendored package's `pubspec.yaml` must opt in:

```yaml
name: asset_strings_builder
resolution: workspace
```

Then create a `build.yaml` at the consumer's package root:

```yaml
targets:
  $default:
    sources:
      include:
        - $package$        # required: the synthetic input the builder runs on
        - lib/**
        - bin/**
        - test/**
        - assets/**        # required: wherever the source asset files live
        - pubspec.*
        - build.yaml
    builders:
      asset_strings_builder:asset_strings:
        enabled: true
        options:
          assets:
            myConstantName: assets/path/to/file.txt
            anotherConstant: assets/other.md
```

Run the generator:

```sh
dart run build_runner build --delete-conflicting-outputs
```

## What the builder does

- **Input:** the synthetic `$package$` input (the builder reads its asset
  list from `BuilderOptions`, not from individual source files).
- **Output (fixed):** `lib/src/asset_strings.g.dart` in the consumer
  package. The path is hardcoded by the builder and is **not**
  consumer-configurable; re-export from wherever you want the constants
  surfaced (e.g. `export 'src/asset_strings.g.dart';`).
- **Encoding:** each asset is read as bytes, base64-encoded, and emitted as
  `final String x = utf8.decode(base64.decode('...'));`. This is binary-safe
  for any byte sequence (no escape-sequence quirks) but means the constants
  are lazy `final` rather than `const` — they cannot be used in a `const`
  context.
- **Determinism:** entries are sorted by constant name.

## `build.yaml` options reference

| Key      | Type                  | Required | Description                                                                                              |
|----------|-----------------------|----------|----------------------------------------------------------------------------------------------------------|
| `assets` | `Map<String, String>` | yes      | Maps the Dart constant name (key) to the package-relative asset path (value). Empty map → no-op + warning. |

Each key must be a valid Dart identifier; each value must be a path that
resolves to a readable asset relative to the consumer package root. A
missing asset path produces an `AssetNotFoundException` at build time.
