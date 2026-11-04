import 'dart:io';

import '../model/manifest/mods_yaml.dart';

enum PublicationArtifactRole { client, server }

class PreparedPublication {
  final SourceKind target;
  final String serverUrl;
  final String token;
  final File artifact;
  final Map<String, dynamic> payload;
  final int? curseforgeProjectId;
  final PublicationArtifactRole role;
  final PreparedPublication? dependentServer;
  final int? parentFileId;

  PreparedPublication({
    required this.target,
    required this.serverUrl,
    required this.token,
    required this.artifact,
    required Map<String, dynamic> payload,
    this.curseforgeProjectId,
    this.role = PublicationArtifactRole.client,
    this.dependentServer,
    this.parentFileId,
  }) : payload = Map.unmodifiable(payload);
}
