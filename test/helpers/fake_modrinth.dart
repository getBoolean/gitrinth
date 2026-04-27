import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// In-process Modrinth-like test server. Routes:
///   - GET /v2/project/{slug}             -> canned project json
///   - GET /v2/project/{slug}/version     -> list of canned versions
///   - GET /v2/project/{slug}/check       -> 200 + `{"id": ...}` if taken,
///                                          404 otherwise
///   - GET /v2/tag/game_version           -> canned MC version list
///   - GET /downloads/{slug}/{filename}   -> the artifact bytes
///   - GET /fabric/v2/versions/loader     -> fabric-meta loader list
///   - GET /forge/promotions_slim.json    -> Forge `:stable`/`:latest`
///   - GET /forge/maven-metadata.json     -> Forge concrete-tag validation
///   - GET /neoforge/versions             -> NeoForge modern (MC ≥ 1.20.2)
///   - GET /neoforge-legacy/versions      -> NeoForge legacy (MC 1.20.1)
class FakeModrinth {
  late final HttpServer _server;
  final Map<String, Map<String, dynamic>> projects;
  final Map<String, List<Map<String, dynamic>>> versions;
  final Map<String, Uint8List> artifacts;

  /// Extra slugs treated as taken by `/v2/project/<slug>/check`.
  final Set<String> _takenSlugs = <String>{};

  /// Versions returned by `/v2/tag/game_version`.
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

  /// Last `GET /v2/project/<slug>/version` query, keyed by slug.
  final Map<String, Map<String, String>> lastVersionQuery = {};

  /// Tokens accepted by `GET /v2/user`.
  final Map<String, String> _knownTokens = <String, String>{};

  /// Last `Authorization` header seen on a request, by path.
  final Map<String, String?> lastAuthorization = <String, String?>{};

  /// Request count by route.
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

  /// Fake fabric-meta loader-list URL.
  String get fabricMetaUrl =>
      'http://127.0.0.1:${_server.port}/fabric/v2/versions/loader';

  /// Newest-first fabric-meta response.
  List<Map<String, dynamic>> fabricLoaderVersions = [
    {'version': '0.17.3', 'stable': true},
    {'version': '0.17.2-beta.1', 'stable': false},
    {'version': '0.17.1', 'stable': true},
  ];

  /// URL for the fake Forge promotions endpoint (`stable`/`latest`).
  String get forgePromotionsUrl =>
      'http://127.0.0.1:${_server.port}/forge/promotions_slim.json';

  /// Fake Forge maven-metadata URL.
  String get forgeVersionsUrl =>
      'http://127.0.0.1:${_server.port}/forge/maven-metadata.json';

  /// Fake modern NeoForge versions URL.
  String get neoforgeVersionsUrl =>
      'http://127.0.0.1:${_server.port}/neoforge/versions';

  /// Fake legacy NeoForge versions URL.
  String get neoforgeLegacyVersionsUrl =>
      'http://127.0.0.1:${_server.port}/neoforge-legacy/versions';

  /// Fake Forge installer URL template.
  String get forgeInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/forge-installer/'
      '{mc}-{v}/forge-{mc}-{v}-installer.jar';

  /// Fake modern NeoForge installer URL template.
  String get neoforgeInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/neoforge-installer/'
      '{v}/neoforge-{v}-installer.jar';

  /// Fake legacy NeoForge installer URL template.
  String get neoforgeLegacyInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/neoforge-legacy-installer/'
      '{mc}-{v}/forge-{mc}-{v}-installer.jar';

  /// Fake Fabric server-launch URL template.
  String get fabricServerJarUrlTemplate =>
      'http://127.0.0.1:${_server.port}/fabric-server/'
      '{mc}/{v}/server/jar';

  /// Forge installer bytes keyed by `<mc>-<v>`.
  final Map<String, Uint8List> forgeInstallerBytes = {};

  /// Modern NeoForge installer bytes keyed by `<v>`.
  final Map<String, Uint8List> neoforgeInstallerBytes = {};

  /// Legacy NeoForge installer bytes keyed by `<mc>-<v>`.
  final Map<String, Uint8List> neoforgeLegacyInstallerBytes = {};

  /// Fabric server-launch bytes keyed by `<mc>/<v>`.
  final Map<String, Uint8List> fabricServerJarBytes = {};

  /// Fake Fabric installer URL template.
  String get fabricInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/fabric-installer/'
      '{installerVersion}/fabric-installer-{installerVersion}.jar';

  /// Fabric installer bytes keyed by version.
  final Map<String, Uint8List> fabricInstallerBytes = {};

  /// Fake Adoptium metadata URL template.
  String get adoptiumMetadataUrlTemplate =>
      'http://127.0.0.1:${_server.port}/adoptium/v3/assets/'
      'feature_releases/{feature}/ga'
      '?architecture={arch}&os={os}';

  /// Adoptium metadata keyed by `<feature>-<os>-<arch>`.
  final Map<String, List<Map<String, dynamic>>> adoptiumMetadata = {};

  /// Adoptium binary bytes keyed by URL tail.
  final Map<String, Uint8List> adoptiumBinaryBytes = {};

  /// URL prefix for [adoptiumBinaryBytes].
  String get adoptiumBinaryUrlPrefix =>
      'http://127.0.0.1:${_server.port}/adoptium-binary/';

  /// Body served at [forgePromotionsUrl].
  Map<String, dynamic> forgePromotions = {
    'homepage': 'https://files.minecraftforge.net/',
    'promos': {'1.20.1-recommended': '47.2.0', '1.20.1-latest': '47.4.10'},
  };

  /// Body served at [forgeVersionsUrl].
  Map<String, dynamic> forgeVersions = {
    '1.20.1': ['1.20.1-47.2.0', '1.20.1-47.4.10'],
  };

  /// Body served at [neoforgeVersionsUrl].
  Map<String, dynamic> neoforgeVersionsBody = {
    'isSnapshot': false,
    'versions': ['21.1.50', '21.1.228'],
  };

  /// Body served at [neoforgeLegacyVersionsUrl].
  Map<String, dynamic> neoforgeLegacyVersionsBody = {
    'isSnapshot': false,
    'versions': ['1.20.1-47.1.100', '1.20.1-47.1.106'],
  };

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  /// Parses a `loaders=` / `game_versions=` query value.
  static List<String>? _decodeFilterArray(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } on FormatException {
      // Invalid JSON means no filter.
    }
    return null;
  }

  /// Marks [slug] as taken for `/v2/project/<slug>/check`.
  void markSlugTaken(String slug) {
    _takenSlugs.add(slug);
  }

  /// Registers [token] as valid; `GET /v2/user` returns [username].
  void registerToken(String token, {String username = 'tester'}) {
    _knownTokens[token] = username;
  }

  /// Adds an artifact and returns its sha512.
  String addArtifact(String slug, String filename, Uint8List bytes) {
    final key = '$slug/$filename';
    artifacts[key] = bytes;
    return sha512.convert(bytes).toString();
  }

  /// Registers one canned version under [slug].
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
    Map<String, String> requiredDepsAtVersion = const {},
    List<String> incompatibleDeps = const [],
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
    String depVersionId(String depSlug, String depVersion) =>
        '${depSlug}_${depVersion.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
    final deps = <Map<String, dynamic>>[
      for (final depSlug in requiredDeps)
        {'project_id': '${depSlug}_ID', 'dependency_type': 'required'},
      for (final entry in requiredDepsAtVersion.entries)
        {
          'project_id': '${entry.key}_ID',
          'version_id': depVersionId(entry.key, entry.value),
          'dependency_type': 'required',
        },
      for (final depSlug in incompatibleDeps)
        {'project_id': '${depSlug}_ID', 'dependency_type': 'incompatible'},
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
    lastAuthorization[path] = req.headers.value('authorization');
    try {
      if (path == '/v2/user') {
        final auth = req.headers.value('authorization');
        final username = auth == null ? null : _knownTokens[auth];
        if (username == null) {
          req.response.statusCode = 401;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'error': 'unauthenticated'}));
        } else {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({'id': 'fake-user-id', 'username': username}),
          );
        }
      } else if (path == '/v2/tag/game_version') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(gameVersions));
      } else if (path == '/fabric/v2/versions/loader') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(fabricLoaderVersions));
      } else if (path == '/forge/promotions_slim.json') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(forgePromotions));
      } else if (path == '/forge/maven-metadata.json') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(forgeVersions));
      } else if (path == '/neoforge/versions') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(neoforgeVersionsBody));
      } else if (path == '/neoforge-legacy/versions') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(neoforgeLegacyVersionsBody));
      } else if (path.startsWith('/forge-installer/')) {
        // /forge-installer/<mc>-<v>/forge-<mc>-<v>-installer.jar
        final tail = path.substring('/forge-installer/'.length);
        final slash = tail.indexOf('/');
        final key = slash < 0 ? tail : tail.substring(0, slash);
        final bytes = forgeInstallerBytes[key];
        if (bytes == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType(
            'application',
            'java-archive',
          );
          req.response.add(bytes);
        }
      } else if (path.startsWith('/neoforge-installer/')) {
        // /neoforge-installer/<v>/neoforge-<v>-installer.jar
        final tail = path.substring('/neoforge-installer/'.length);
        final slash = tail.indexOf('/');
        final key = slash < 0 ? tail : tail.substring(0, slash);
        final bytes = neoforgeInstallerBytes[key];
        if (bytes == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType(
            'application',
            'java-archive',
          );
          req.response.add(bytes);
        }
      } else if (path.startsWith('/neoforge-legacy-installer/')) {
        // /neoforge-legacy-installer/<mc>-<v>/forge-<mc>-<v>-installer.jar
        final tail = path.substring('/neoforge-legacy-installer/'.length);
        final slash = tail.indexOf('/');
        final key = slash < 0 ? tail : tail.substring(0, slash);
        final bytes = neoforgeLegacyInstallerBytes[key];
        if (bytes == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType(
            'application',
            'java-archive',
          );
          req.response.add(bytes);
        }
      } else if (path.startsWith('/fabric-installer/')) {
        // /fabric-installer/<v>/fabric-installer-<v>.jar
        final tail = path.substring('/fabric-installer/'.length);
        final slash = tail.indexOf('/');
        final key = slash < 0 ? tail : tail.substring(0, slash);
        final bytes = fabricInstallerBytes[key];
        if (bytes == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType(
            'application',
            'java-archive',
          );
          req.response.add(bytes);
        }
      } else if (path.startsWith('/adoptium/v3/assets/feature_releases/')) {
        // /adoptium/v3/assets/feature_releases/<feature>/ga?...
        final tail = path.substring(
          '/adoptium/v3/assets/feature_releases/'.length,
        );
        final slash = tail.indexOf('/');
        final feature = slash < 0 ? tail : tail.substring(0, slash);
        final qp = req.uri.queryParameters;
        final os = qp['os'] ?? '';
        final arch = qp['architecture'] ?? '';
        final key = '$feature-$os-$arch';
        final body = adoptiumMetadata[key];
        if (body == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(body));
        }
      } else if (path.startsWith('/adoptium-binary/')) {
        final key = path.substring('/adoptium-binary/'.length);
        final bytes = adoptiumBinaryBytes[key];
        if (bytes == null) {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType(
            'application',
            'octet-stream',
          );
          req.response.add(bytes);
        }
      } else if (path.startsWith('/fabric-server/')) {
        // /fabric-server/<mc>/<v>/server/jar
        final tail = path.substring('/fabric-server/'.length);
        final segments = tail.split('/');
        if (segments.length >= 2) {
          final key = '${segments[0]}/${segments[1]}';
          final bytes = fabricServerJarBytes[key];
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
      } else if (path.startsWith('/v2/project/')) {
        final tail = path.substring('/v2/project/'.length);
        if (tail.endsWith('/check')) {
          final slug = tail.substring(0, tail.length - '/check'.length);
          if (_takenSlugs.contains(slug) || projects.containsKey(slug)) {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode({'id': 'fake-$slug'}));
          } else {
            req.response.statusCode = 404;
          }
        } else if (tail.endsWith('/version')) {
          final slug = tail.substring(0, tail.length - '/version'.length);
          lastVersionQuery[slug] = Map<String, String>.from(
            req.uri.queryParameters,
          );
          final list = versions[slug];
          if (list == null) {
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'error': 'unknown slug $slug'}));
          } else {
            // Apply the same loader/game-version filters as Modrinth.
            final qp = req.uri.queryParameters;
            final loadersFilter = _decodeFilterArray(qp['loaders']);
            final gvFilter = _decodeFilterArray(qp['game_versions']);
            final filtered = list.where((v) {
              final loaders =
                  (v['loaders'] as List?)?.cast<String>() ?? const [];
              final gvs =
                  (v['game_versions'] as List?)?.cast<String>() ?? const [];
              final loaderOk =
                  loadersFilter == null || loaders.any(loadersFilter.contains);
              final gvOk = gvFilter == null || gvs.any(gvFilter.contains);
              return loaderOk && gvOk;
            }).toList();
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(filtered));
          }
        } else {
          // Accept project ID or slug.
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
            // Derive `loaders` when tests did not set it explicitly.
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
