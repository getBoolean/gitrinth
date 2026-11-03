import 'modrinth_api.dart';

/// Host-addressed public API access, without ownership of the transport.
abstract interface class ModrinthApiSource {
  String get defaultBaseUrl;
  ModrinthApi forHost(String? hostUrl);
}
