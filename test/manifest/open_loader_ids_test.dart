import 'package:gitrinth/src/model/manifest/emitter.dart';
import 'package:gitrinth/src/model/manifest/parser.dart';
import 'package:test/test.dart';

void main() {
  test('future loader identities survive manifest and lock parsing', () {
    const manifest = '''
slug: future
name: Future
version: 1.0.0
description: test
mc_version: 1.21.1
loader: {mods: 'future-loader:1.2.3', shaders: future-shader}
''';
    final yaml = parseModsYaml(manifest, filePath: 'mods.yaml');
    expect(yaml.loader.mods.name, 'future-loader');
    expect(yaml.loader.shaders?.name, 'future-shader');
    const lock = '''
gitrinth-version: 0.1.0
mc_version: 1.21.1
loader: {mods: 'future-loader:1.2.3', plugins: 'future-plugin:2.0.0'}
''';
    final parsed = parseModsLock(lock, filePath: 'mods.lock');
    final emitted = emitModsLock(parsed);
    final roundtrip = parseModsLock(emitted, filePath: 'mods.lock');
    expect(roundtrip.loader.mods.name, 'future-loader');
    expect(roundtrip.loader.plugins?.name, 'future-plugin');
    expect(roundtrip.loader.modLoaderVersion, '1.2.3');
    expect(roundtrip.loader.pluginLoaderVersion, '2.0.0');
  });
}
