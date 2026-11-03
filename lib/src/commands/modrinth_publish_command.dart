import '../model/manifest/mods_yaml.dart';
import 'publish_command.dart';

class ModrinthPublishCommand extends PublicationCommand {
  ModrinthPublishCommand() : super(forcedPlatform: SourceKind.modrinth);

  @override
  String get invocation => 'gitrinth modrinth publish [arguments]';

  @override
  String get description =>
      'Upload a built .mrpack as a new version on the Modrinth-compatible server.';
}
