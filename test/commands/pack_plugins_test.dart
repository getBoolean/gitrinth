import 'package:gitrinth/src/commands/build_assembler.dart';
import 'package:gitrinth/src/commands/pack_assembler.dart';
import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';

void main() {
  test('mrpackSubdirFor(plugins) is "plugins"', () {
    expect(mrpackSubdirFor(Section.plugins), 'plugins');
  });

  test('plugin entry surfaces in modrinth.index.json files[] with the right '
      'path and env', () {
    final sha1 = 'a' * 40;
    final sha512 = 'b' * 128;
    final lock = ModsLock(
      gitrinthVersion: '1.0.0',
      loader: const LoaderConfig(
        mods: ModLoader.neoforge,
        modsVersion: '21.1.50',
        plugins: PluginLoader.paper,
      ),
      mcVersion: '1.21.1',
      plugins: {
        'luckperms': LockedEntry(
          slug: 'luckperms',
          sourceKind: LockedSourceKind.modrinth,
          version: '5.4.0',
          projectId: 'luckperms_ID',
          versionId: 'luckperms_5_4_0',
          file: LockedFile(
            name: 'luckperms-5.4.0.jar',
            url: 'https://example.com/luckperms-5.4.0.jar',
            sha1: sha1,
            sha512: sha512,
            size: 1024,
          ),
          client: SideEnv.unsupported,
          server: SideEnv.required,
        ),
      },
    );
    final manifest = const ModsYaml(
      slug: 'pack',
      name: 'Pack',
      version: '1.0.0',
      description: 'x',
      loader: LoaderConfig(
        mods: ModLoader.neoforge,
        modsVersion: '21.1.50',
        plugins: PluginLoader.paper,
      ),
      mcVersion: '1.21.1',
    );
    final index = buildIndex(
      yaml: manifest,
      lock: lock,
      target: PackTarget.combined,
      publishable: false,
    );
    final pluginFile = index.files.singleWhere(
      (f) => f.path == 'plugins/luckperms-5.4.0.jar',
    );
    expect(pluginFile.env, {'client': 'unsupported', 'server': 'required'});
    expect(pluginFile.fileSize, 1024);
  });
}
