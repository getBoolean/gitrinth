# gitrinth

A CLI for managing Modrinth modpacks as git repositories. A modpack is
declared in `mods.yaml`; `gitrinth` resolves entries against Modrinth, locks
versions to `mods.lock`, assembles client/server distributions, and publishes
the result as an `.mrpack`.

See [`docs/mvp.md`](docs/mvp.md) for the current feature set and
[`docs/cli.md`](docs/cli.md) for the full CLI surface.

## Contributing

### Regenerating templates

After changing any file under `assets/template/`, regenerate the constants in `lib/src/asset_strings.g.dart` and commit them alongside the asset change:

```sh
dart pub get
dart run build_runner build --delete-conflicting-outputs
```
