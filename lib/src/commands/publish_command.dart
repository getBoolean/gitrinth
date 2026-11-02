import '../model/manifest/mods_yaml.dart';
import 'modrinth_publish_command.dart';

class PublishCommand extends ModrinthPublishCommand {
  PublishCommand() : super(platformAware: true);

  @override
  String get invocation => 'gitrinth publish [arguments]';

  @override
  String get description =>
      'Publish built artifacts to the selected platforms.';
}

class CurseForgePublishCommand extends ModrinthPublishCommand {
  CurseForgePublishCommand() : super(forcedPlatform: SourceKind.curseforge);

  @override
  String get invocation => 'gitrinth curseforge publish [arguments]';

  @override
  String get description => 'Upload a built CurseForge .zip.';
}
