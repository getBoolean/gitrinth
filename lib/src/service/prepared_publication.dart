import 'dart:io';

import '../model/manifest/mods_yaml.dart';

class PreparedPublication {
  final SourceKind target;
  final String serverUrl;
  final String token;
  final File artifact;
  final Map<String, dynamic> payload;
  final int? curseforgeProjectId;

  PreparedPublication({
    required this.target,
    required this.serverUrl,
    required this.token,
    required this.artifact,
    required Map<String, dynamic> payload,
    this.curseforgeProjectId,
  }) : payload = Map.unmodifiable(payload);
}
