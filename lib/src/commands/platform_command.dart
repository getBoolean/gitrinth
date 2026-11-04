import 'dart:io';

import 'package:yaml_edit/yaml_edit.dart';

import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/parser.dart';
import '../service/manifest_io.dart';
import '../util/yaml_root.dart';
import 'publish_command.dart';

/// Changes implicit source participation without resolving or changing entries.
class PlatformToggleCommand extends GitrinthCommand {
  final String platform;
  final bool enabled;
  PlatformToggleCommand(this.platform, this.enabled);

  @override
  String get name => enabled ? 'enable' : 'disable';
  @override
  String get description =>
      '${enabled ? 'Enable' : 'Disable'} $platform by default in mods.yaml.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
    final io = ManifestIo();
    io.readModsYaml();
    final editor = YamlEditor(File(io.modsYamlPath).readAsStringSync());
    final root = parseYamlRoot(editor, filename: 'mods.yaml');
    final value = enabled ? 'enabled' : 'disabled';
    if (root['gitrinth'] == null) {
      editor.update(['gitrinth'], {platform: value});
    } else {
      editor.update(['gitrinth', platform], value);
    }
    final text = editor.toString();
    parseModsYaml(text, filePath: io.modsYamlPath);
    io.writeModsYaml(text);
    console.message('$platform $value in mods.yaml.');
    return exitOk;
  }
}

class CurseForgeCommand extends GitrinthCommand {
  CurseForgeCommand() {
    addSubcommand(CurseForgePublishCommand());
    addSubcommand(PlatformToggleCommand('curseforge', true));
    addSubcommand(PlatformToggleCommand('curseforge', false));
  }
  @override
  String get name => 'curseforge';
  @override
  String get description =>
      'Configure CurseForge participation and publishing.';
  @override
  Future<int> run() async {
    printUsage();
    return exitOk;
  }
}
