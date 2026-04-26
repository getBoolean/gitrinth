import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import '../model/manifest/mods_lock.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/manifest/parser.dart';
import '../model/manifest/project_overrides.dart';
import '../util/atomic_file_writer.dart';

class ManifestIo {
  final Directory directory;

  ManifestIo({Directory? directory})
    : directory = directory ?? Directory.current;

  String get modsYamlPath => p.normalize(p.join(directory.path, 'mods.yaml'));
  String get projectOverridesPath =>
      p.normalize(p.join(directory.path, 'project_overrides.yaml'));
  String get modsLockPath => p.normalize(p.join(directory.path, 'mods.lock'));

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

  ProjectOverrides readProjectOverrides() {
    final file = File(projectOverridesPath);
    if (!file.existsSync()) return const ProjectOverrides();
    return parseProjectOverrides(
      file.readAsStringSync(),
      filePath: projectOverridesPath,
    );
  }

  ModsLock? readModsLock() {
    final file = File(modsLockPath);
    if (!file.existsSync()) return null;
    return parseModsLock(file.readAsStringSync(), filePath: modsLockPath);
  }

  void writeModsLock(String contents) {
    atomicWriteString(modsLockPath, contents);
  }

  void writeModsYaml(String contents) {
    atomicWriteString(modsYamlPath, contents);
  }

  void writeProjectOverrides(String contents) {
    atomicWriteString(projectOverridesPath, contents);
  }
}
