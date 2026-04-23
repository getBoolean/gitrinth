import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// In-process Modrinth-shaped HTTP server used by tests. Spawns on
/// 127.0.0.1:0 (free port). Routes:
///   - GET /v2/project/{slug}             -> canned project json
///   - GET /v2/project/{slug}/version     -> list of canned versions
///   - GET /downloads/{slug}/{filename}   -> the artifact bytes
class FakeModrinth {
  late final HttpServer _server;
  final Map<String, Map<String, dynamic>> projects;
  final Map<String, List<Map<String, dynamic>>> versions;
  final Map<String, Uint8List> artifacts;

  FakeModrinth({
    Map<String, Map<String, dynamic>>? projects,
    Map<String, List<Map<String, dynamic>>>? versions,
    Map<String, Uint8List>? artifacts,
  })  : projects = projects ?? {},
        versions = versions ?? {},
        artifacts = artifacts ?? {};

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v2';
  String get downloadBaseUrl => 'http://127.0.0.1:${_server.port}/downloads';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  /// Adds an artifact and returns its sha512.
  String addArtifact(String slug, String filename, Uint8List bytes) {
    final key = '$slug/$filename';
    artifacts[key] = bytes;
    return sha512.convert(bytes).toString();
  }

  void _handle(HttpRequest req) async {
    final path = req.uri.path;
    try {
      if (path.startsWith('/v2/project/')) {
        final tail = path.substring('/v2/project/'.length);
        if (tail.endsWith('/version')) {
          final slug = tail.substring(0, tail.length - '/version'.length);
          final list = versions[slug];
          if (list == null) {
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'error': 'unknown slug $slug'}));
          } else {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(list));
          }
        } else {
          final slug = tail;
          final p = projects[slug];
          if (p == null) {
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'error': 'unknown slug $slug'}));
          } else {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(p));
          }
        }
      } else if (path.startsWith('/downloads/')) {
        final key = path.substring('/downloads/'.length);
        final bytes = artifacts[key];
        if (bytes == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType =
              ContentType('application', 'java-archive');
          req.response.add(bytes);
        }
      } else {
        req.response.statusCode = 404;
      }
    } catch (e) {
      req.response.statusCode = 500;
      req.response.write('error: $e');
    } finally {
      await req.response.close();
    }
  }
}
