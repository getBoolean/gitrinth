import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_overrides.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/parser.dart';

class ManifestIo {
  final Directory directory;

  ManifestIo({Directory? directory})
    : directory = directory ?? Directory.current;

  String get modsYamlPath => p.join(directory.path, 'mods.yaml');
  String get modsOverridesPath => p.join(directory.path, 'mods_overrides.yaml');
  String get modsLockPath => p.join(directory.path, 'mods.lock');

  ModsYaml readModsYaml() {
    final file = File(modsYamlPath);
    if (!file.existsSync()) {
      throw UserError(
        'mods.yaml not found in ${directory.path}. '
        'Run `gitrinth create` first or change directory with -C.',
      );
    }
    return parseModsYaml(file.readAsStringSync(), filePath: modsYamlPath);
  }

  ModsOverrides readOverrides() {
    final file = File(modsOverridesPath);
    if (!file.existsSync()) return const ModsOverrides();
    return parseModsOverrides(
      file.readAsStringSync(),
      filePath: modsOverridesPath,
    );
  }

  ModsLock? readModsLock() {
    final file = File(modsLockPath);
    if (!file.existsSync()) return null;
    return parseModsLock(file.readAsStringSync(), filePath: modsLockPath);
  }

  void writeModsLock(String contents) {
    final lockFile = File(modsLockPath);
    final tempFile = File('$modsLockPath.tmp');
    tempFile.writeAsStringSync(contents);
    if (lockFile.existsSync()) lockFile.deleteSync();
    tempFile.renameSync(lockFile.path);
  }

  void writeModsYaml(String contents) {
    final yamlFile = File(modsYamlPath);
    final tempFile = File('$modsYamlPath.tmp');
    tempFile.writeAsStringSync(contents);
    if (yamlFile.existsSync()) yamlFile.deleteSync();
    tempFile.renameSync(yamlFile.path);
  }
}
