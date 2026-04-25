# gitrinth

A CLI for managing Modrinth modpacks as git repositories. A modpack is
declared in `mods.yaml`; `gitrinth` resolves entries against Modrinth, locks
versions to `mods.lock`, assembles client/server distributions, and publishes
the result as an `.mrpack`.

See [`docs/mvp.md`](docs/mvp.md) for the current feature set and
[`docs/cli.md`](docs/cli.md) for the full CLI surface.

## Usage

Scaffold a pack, add a mod, lock, and build:

```sh
gitrinth create my_pack
cd my_pack
gitrinth add sodium
gitrinth get
gitrinth build
```

Test it locally — boot the server, or open the Minecraft Launcher pointed
at the built client:

```sh
gitrinth launch server --accept-eula
gitrinth launch client
```

Both subcommands run `gitrinth build` for their side first; pass
`--no-build` to skip when the build tree is already current. `launch
server` needs `--accept-eula` once to write `eula=true` to
`build/server/eula.txt` (you agree to the [Mojang EULA](https://aka.ms/MinecraftEULA)).
A JDK matching the pack's `mc-version` is auto-downloaded into the
cache if one isn't already on the system.

Common commands:

| Command                             | Purpose                                                                       |
|-------------------------------------|-------------------------------------------------------------------------------|
| `gitrinth create <slug>`            | Scaffold a new modpack.                                                       |
| `gitrinth add <slug>`               | Add an entry and re-resolve.                                                  |
| `gitrinth remove <slug>`            | Remove an entry and re-resolve.                                               |
| `gitrinth get`                      | Resolve `mods.yaml`, write `mods.lock`, fill cache.                           |
| `gitrinth upgrade`                  | Re-resolve to the newest in-range version per entry.                          |
| `gitrinth upgrade --major-versions` | Upgrade to newest version, even when version number implies breaking changes. |
| `gitrinth build`                    | Assemble modpack distributions for client and server.                         |
| `gitrinth pack`                     | Produce `.mrpack` artifacts under `build/`.                                   |
| `gitrinth launch server`            | Build and start the server.                                                   |
| `gitrinth launch client`            | Build and open the Minecraft Launcher.                                        |
| `gitrinth clean`                    | Delete `mods.lock` and `build/`.                                              |

Run `gitrinth <command> --help` for options. Every mutating command accepts
`--offline` to use only what's already in the cache.

## Contributing

### Regenerating templates and generated code

After changing any file under `assets/template/`, Dart Mappable models, or Retrofit HTTP interfaces, regenerate the constants in `lib/src/asset_strings.g.dart` and commit them alongside the asset change:

```sh
dart pub get
dart run build_runner build --delete-conflicting-outputs
```
