import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// In-process Modrinth-shaped HTTP server used by tests. Spawns on
/// 127.0.0.1:0 (free port). Routes:
///   - GET /v2/project/{slug}             -> canned project json
///   - GET /v2/project/{slug}/version     -> list of canned versions
///   - GET /v2/tag/game_version           -> canned MC version list
///   - GET /downloads/{slug}/{filename}   -> the artifact bytes
class FakeModrinth {
  late final HttpServer _server;
  final Map<String, Map<String, dynamic>> projects;
  final Map<String, List<Map<String, dynamic>>> versions;
  final Map<String, Uint8List> artifacts;

  /// Minecraft versions returned by `/v2/tag/game_version`. Default
  /// includes the versions used in the test fixtures so existing tests
  /// keep passing without configuring this explicitly.
  List<Map<String, dynamic>> gameVersions = [
    {
      'version': '1.21.1',
      'version_type': 'release',
      'date': '2024-08-08T00:00:00Z',
      'major': false,
    },
    {
      'version': '1.21',
      'version_type': 'release',
      'date': '2024-06-13T00:00:00Z',
      'major': true,
    },
    {
      'version': '1.20.1',
      'version_type': 'release',
      'date': '2023-06-12T00:00:00Z',
      'major': false,
    },
  ];

  /// Last query-parameter map seen on `GET /v2/project/<slug>/version`,
  /// keyed by slug. Tests can assert which `loaders`/`game_versions`
  /// filters the CLI sent (or didn't send) for a given request.
  final Map<String, Map<String, String>> lastVersionQuery = {};

  /// Number of times each route has been requested. Tests can assert
  /// that mc-version validation only fires when expected (one-shot rule).
  final Map<String, int> requestCounts = {};

  FakeModrinth({
    Map<String, Map<String, dynamic>>? projects,
    Map<String, List<Map<String, dynamic>>>? versions,
    Map<String, Uint8List>? artifacts,
  }) : projects = projects ?? {},
       versions = versions ?? {},
       artifacts = artifacts ?? {};

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v2';
  String get downloadBaseUrl => 'http://127.0.0.1:${_server.port}/downloads';

  /// URL for the fake fabric-meta loader-list response. Tests pass this
  /// via the `GITRINTH_FABRIC_META_URL` env var to keep the resolver off
  /// the real fabricmc.net.
  String get fabricMetaUrl =>
      'http://127.0.0.1:${_server.port}/fabric/v2/versions/loader';

  /// Newest-first list returned by the fake fabric-meta endpoint. Each
  /// entry needs at least `version` (String) and `stable` (bool); other
  /// fields are ignored by the resolver.
  List<Map<String, dynamic>> fabricLoaderVersions = [
    {'version': '0.17.3', 'stable': true},
    {'version': '0.17.2-beta.1', 'stable': false},
    {'version': '0.17.1', 'stable': true},
  ];

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

  /// Registers a single canned version under [slug]. Returns the generated
  /// version-id so tests can assert against it. Builds the artifact bytes
  /// on the fly and hashes them.
  ///
  /// [versionType] is the Modrinth `version_type` ("release" | "beta" |
  /// "alpha"); omit to leave it unset (the resolver treats missing as
  /// "release").
  String registerVersion({
    required String slug,
    required String versionNumber,
    String? versionType,
    String projectId = '',
    String loader = 'neoforge',
    String gameVersion = '1.21.1',
    List<String> requiredDeps = const [],
    String? datePublished,
  }) {
    final pid = projectId.isEmpty ? '${slug}_ID' : projectId;
    final versionId =
        '${slug}_${versionNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
    final filename = '$slug-$versionNumber.jar';
    final bytes = Uint8List.fromList(
      List.generate(
        16,
        (i) => (versionNumber.codeUnitAt(i % versionNumber.length) + i) & 0xff,
      ),
    );
    final sha = addArtifact(slug, filename, bytes);
    projects.putIfAbsent(
      slug,
      () => <String, dynamic>{
        'id': pid,
        'slug': slug,
        'title': slug,
        'project_type': 'mod',
      },
    );
    final deps = <Map<String, dynamic>>[
      for (final depSlug in requiredDeps)
        {
          'project_id': '${depSlug}_ID',
          'dependency_type': 'required',
        },
    ];
    final entry = <String, dynamic>{
      'id': versionId,
      'project_id': pid,
      'version_number': versionNumber,
      'files': [
        {
          'url': '$downloadBaseUrl/$slug/$filename',
          'filename': filename,
          'hashes': {'sha512': sha},
          'size': bytes.length,
          'primary': true,
        },
      ],
      'dependencies': deps,
      'loaders': [loader],
      'game_versions': [gameVersion],
    };
    if (versionType != null) entry['version_type'] = versionType;
    if (datePublished != null) entry['date_published'] = datePublished;
    versions.putIfAbsent(slug, () => <Map<String, dynamic>>[]).add(entry);
    return versionId;
  }

  void _handle(HttpRequest req) async {
    final path = req.uri.path;
    requestCounts.update(path, (n) => n + 1, ifAbsent: () => 1);
    try {
      if (path == '/v2/tag/game_version') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(gameVersions));
      } else if (path == '/fabric/v2/versions/loader') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(fabricLoaderVersions));
      } else if (path.startsWith('/v2/project/')) {
        final tail = path.substring('/v2/project/'.length);
        if (tail.endsWith('/version')) {
          final slug = tail.substring(0, tail.length - '/version'.length);
          lastVersionQuery[slug] = Map<String, String>.from(
            req.uri.queryParameters,
          );
          final list = versions[slug];
          if (list == null) {
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'error': 'unknown slug $slug'}));
          } else {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(list));
          }
        } else {
          // Modrinth's real /v2/project/{id|slug} accepts either form.
          // Mirror that so dep lookups (which carry project IDs) resolve.
          var p = projects[tail];
          if (p == null) {
            for (final candidate in projects.values) {
              if (candidate['id'] == tail) {
                p = candidate;
                break;
              }
            }
          }
          if (p == null) {
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'error': 'unknown id/slug $tail'}));
          } else {
            req.response.headers.contentType = ContentType.json;
            // Auto-derive `loaders` from the first registered version when
            // the test didn't set it explicitly. Mirrors Modrinth's real
            // behavior (project responses include the union of loader tags
            // across that project's versions) closely enough for routing
            // tests.
            final body = Map<String, dynamic>.from(p);
            if (!body.containsKey('loaders')) {
              final resolvedSlug = body['slug'] as String?;
              final vs = resolvedSlug == null ? null : versions[resolvedSlug];
              final first = (vs != null && vs.isNotEmpty) ? vs.first : null;
              final derived = first?['loaders'];
              body['loaders'] = derived is List
                  ? List<dynamic>.from(derived)
                  : const <dynamic>[];
            }
            req.response.write(jsonEncode(body));
          }
        }
      } else if (path.startsWith('/downloads/')) {
        final key = path.substring('/downloads/'.length);
        final bytes = artifacts[key];
        if (bytes == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType(
            'application',
            'java-archive',
          );
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
