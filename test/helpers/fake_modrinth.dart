import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// In-process Modrinth-shaped HTTP server used by tests. Spawns on
/// 127.0.0.1:0 (free port). Routes:
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

  /// Slugs that should report as already taken on `/v2/project/<slug>/check`,
  /// in addition to anything in [projects]. Tests that want to assert collision
  /// behavior without registering a full project body use this.
  final Set<String> _takenSlugs = <String>{};

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

  /// Tokens accepted by `GET /v2/user`. Map value is the username
  /// returned in the response body. Add via [registerToken]; any
  /// `Authorization` header not present here yields 401.
  final Map<String, String> _knownTokens = <String, String>{};

  /// Last `Authorization` header seen on a request, by path.
  final Map<String, String?> lastAuthorization = <String, String?>{};

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

  /// URL for the fake Forge promotions endpoint (`stable`/`latest`).
  String get forgePromotionsUrl =>
      'http://127.0.0.1:${_server.port}/forge/promotions_slim.json';

  /// URL for the fake Forge maven-metadata endpoint (concrete-tag validation).
  String get forgeVersionsUrl =>
      'http://127.0.0.1:${_server.port}/forge/maven-metadata.json';

  /// URL for the fake NeoForge modern versions endpoint.
  String get neoforgeVersionsUrl =>
      'http://127.0.0.1:${_server.port}/neoforge/versions';

  /// URL for the fake NeoForge legacy (MC 1.20.1) versions endpoint.
  String get neoforgeLegacyVersionsUrl =>
      'http://127.0.0.1:${_server.port}/neoforge-legacy/versions';

  /// Template URL for the fake Forge installer endpoint, with `{mc}` and
  /// `{v}` placeholders that mirror the real maven.minecraftforge.net path
  /// shape (`<root>/<mc>-<v>/forge-<mc>-<v>-installer.jar`). Tests pass this
  /// to [LoaderBinaryFetcher] so the cache exercise hits this server instead
  /// of upstream.
  String get forgeInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/forge-installer/'
      '{mc}-{v}/forge-{mc}-{v}-installer.jar';

  /// Template URL for the fake NeoForge installer endpoint (modern, MC ≥
  /// 1.20.2). `{v}` placeholder mirrors `<root>/<v>/neoforge-<v>-installer.jar`.
  String get neoforgeInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/neoforge-installer/'
      '{v}/neoforge-{v}-installer.jar';

  /// Template URL for the fake NeoForge legacy installer endpoint (MC 1.20.1).
  /// `{mc}` and `{v}` placeholders mirror the real
  /// `<root>/<mc>-<v>/forge-<mc>-<v>-installer.jar` shape.
  String get neoforgeLegacyInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/neoforge-legacy-installer/'
      '{mc}-{v}/forge-{mc}-{v}-installer.jar';

  /// Template URL for the fake Fabric server-launch JAR endpoint.
  /// `{mc}` and `{v}` placeholders mirror the real
  /// `meta.fabricmc.net/v2/versions/loader/<mc>/<v>/server/jar` path.
  String get fabricServerJarUrlTemplate =>
      'http://127.0.0.1:${_server.port}/fabric-server/'
      '{mc}/{v}/server/jar';

  /// Bytes served at the Forge installer endpoint, keyed by `<mc>-<v>`
  /// (e.g. `1.21.1-52.1.5`). Tests register entries here, then assert the
  /// downloaded file matches.
  final Map<String, Uint8List> forgeInstallerBytes = {};

  /// Bytes served at the modern NeoForge installer endpoint, keyed by `<v>`
  /// (e.g. `21.1.50`).
  final Map<String, Uint8List> neoforgeInstallerBytes = {};

  /// Bytes served at the legacy NeoForge installer endpoint, keyed by
  /// `<mc>-<v>` (the legacy maven uses the same path shape as Forge, so the
  /// key includes the MC prefix).
  final Map<String, Uint8List> neoforgeLegacyInstallerBytes = {};

  /// Bytes served at the Fabric server-launch JAR endpoint, keyed by
  /// `<mc>/<v>` (e.g. `1.21.1/0.17.3`).
  final Map<String, Uint8List> fabricServerJarBytes = {};

  /// Template URL for the fake Fabric universal installer endpoint.
  /// `{installerVersion}` placeholder mirrors the real
  /// `maven.fabricmc.net/net/fabricmc/fabric-installer/<v>/fabric-installer-<v>.jar`
  /// path.
  String get fabricInstallerUrlTemplate =>
      'http://127.0.0.1:${_server.port}/fabric-installer/'
      '{installerVersion}/fabric-installer-{installerVersion}.jar';

  /// Bytes served at the Fabric universal installer endpoint, keyed by
  /// installer version (e.g. `1.0.1`).
  final Map<String, Uint8List> fabricInstallerBytes = {};

  /// Template URL for the fake Adoptium metadata endpoint. `{feature}`,
  /// `{os}`, `{arch}` placeholders mirror the real
  /// `api.adoptium.net/v3/assets/feature_releases/<feature>/ga` shape.
  String get adoptiumMetadataUrlTemplate =>
      'http://127.0.0.1:${_server.port}/adoptium/v3/assets/'
      'feature_releases/{feature}/ga'
      '?architecture={arch}&os={os}';

  /// JSON body served at the Adoptium metadata endpoint, keyed by
  /// `<feature>-<os>-<arch>` (e.g. `21-windows-x64`). Tests register
  /// entries as `List<Map<String, dynamic>>` to mirror the real shape.
  final Map<String, List<Map<String, dynamic>>> adoptiumMetadata = {};

  /// Bytes served at the Adoptium fake binary endpoint, keyed by the
  /// path tail (e.g. `21-windows-x64.zip`). The metadata `package.link`
  /// must point at `http://127.0.0.1:<port>/adoptium-binary/<key>` for
  /// the test to wire end-to-end.
  final Map<String, Uint8List> adoptiumBinaryBytes = {};

  /// URL prefix tests should use when registering [adoptiumBinaryBytes].
  String get adoptiumBinaryUrlPrefix =>
      'http://127.0.0.1:${_server.port}/adoptium-binary/';

  /// Body served at [forgePromotionsUrl]. Shape mirrors the real
  /// `promotions_slim.json` — `promos` keyed by `<mc>-recommended` and
  /// `<mc>-latest`, values are bare build numbers.
  Map<String, dynamic> forgePromotions = {
    'homepage': 'https://files.minecraftforge.net/',
    'promos': {
      '1.20.1-recommended': '47.2.0',
      '1.20.1-latest': '47.4.10',
    },
  };

  /// Body served at [forgeVersionsUrl]. Shape mirrors the real
  /// `maven-metadata.json` — top-level keys are MC versions, values are
  /// arrays of full `<mc>-<build>` strings.
  Map<String, dynamic> forgeVersions = {
    '1.20.1': ['1.20.1-47.2.0', '1.20.1-47.4.10'],
  };

  /// Body served at [neoforgeVersionsUrl]. Shape mirrors the real
  /// neoforged maven JSON API: `{"isSnapshot": bool, "versions": [...]}`.
  /// Versions ascending, `-beta` suffix denotes non-stable.
  Map<String, dynamic> neoforgeVersionsBody = {
    'isSnapshot': false,
    'versions': ['21.1.50', '21.1.228'],
  };

  /// Body served at [neoforgeLegacyVersionsUrl]. Same shape; entries are
  /// `1.20.1-<build>`.
  Map<String, dynamic> neoforgeLegacyVersionsBody = {
    'isSnapshot': false,
    'versions': ['1.20.1-47.1.100', '1.20.1-47.1.106'],
  };

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  /// Parses a `loaders=`/`game_versions=` query value (real Modrinth
  /// expects a JSON array). Returns null when absent so callers can
  /// distinguish "no filter" from "filter that matches nothing".
  static List<String>? _decodeFilterArray(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } on FormatException {
      // Fall through: invalid JSON arrays are treated as no filter.
    }
    return null;
  }

  /// Marks [slug] as already taken so `/v2/project/<slug>/check` returns 200.
  /// `registerVersion` already records into [projects], which is also treated
  /// as taken — this is for tests that want collision behavior without a full
  /// project fixture.
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
        {
          'project_id': '${depSlug}_ID',
          'dependency_type': 'required',
        },
      for (final entry in requiredDepsAtVersion.entries)
        {
          'project_id': '${entry.key}_ID',
          'version_id': depVersionId(entry.key, entry.value),
          'dependency_type': 'required',
        },
      for (final depSlug in incompatibleDeps)
        {
          'project_id': '${depSlug}_ID',
          'dependency_type': 'incompatible',
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
          req.response.write(jsonEncode({
            'id': 'fake-user-id',
            'username': username,
          }));
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
            // Mirror real Modrinth's server-side filter so the resolver
            // doesn't see candidates that wouldn't be returned in
            // production (e.g. a 1.21.1-only version when the query
            // asks for 1.21.4). Only applies when the caller actually
            // sent the filter — absent params keep the full list.
            final qp = req.uri.queryParameters;
            final loadersFilter = _decodeFilterArray(qp['loaders']);
            final gvFilter = _decodeFilterArray(qp['game_versions']);
            final filtered = list.where((v) {
              final loaders = (v['loaders'] as List?)?.cast<String>() ?? const [];
              final gvs = (v['game_versions'] as List?)?.cast<String>() ?? const [];
              final loaderOk = loadersFilter == null ||
                  loaders.any(loadersFilter.contains);
              final gvOk = gvFilter == null || gvs.any(gvFilter.contains);
              return loaderOk && gvOk;
            }).toList();
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(filtered));
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
