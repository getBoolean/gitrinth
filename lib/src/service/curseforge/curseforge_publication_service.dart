import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../cli/exceptions.dart';
import '../../model/manifest/mods_yaml.dart' show SourceKind;
import '../../model/manifest/server_distribution.dart';
import '../file_digest.dart';
import '../modrinth/modrinth_url.dart';
import '../prepared_publication.dart';
import 'curseforge_publication_receipt.dart';
import 'curseforge_upload_client.dart';

class PreparedCurseForgePublication {
  final PreparedPublication root;
  final PreparedPublication server;
  final CurseForgePublicationReceipt receipt;
  final Map<PreparedPublication, String> peerKeys;
  PreparedCurseForgePublication({
    required this.root,
    required this.server,
    required this.receipt,
    required Map<PreparedPublication, String> peerKeys,
  }) : peerKeys = Map.unmodifiable(peerKeys);
}

class CurseForgePublicationResult {
  final int parentId;
  final int childId;
  final bool classificationConfirmed;
  const CurseForgePublicationResult(
    this.parentId,
    this.childId,
    this.classificationConfirmed,
  );
}

class CurseForgePublicationFailure extends UserError {
  final int? parentId;
  final int? childId;
  final bool unknownOutcome;
  const CurseForgePublicationFailure(
    super.message, {
    this.parentId,
    this.childId,
    this.unknownOutcome = false,
  });
}

/// Executes dependent uploads and records exactly which remote steps survived.
class CurseForgePublicationService {
  final CurseForgeUploadClient uploadClient;
  final Future<Map<String, dynamic>> Function(int projectId, int fileId)
  readFile;
  final Future<List<Map<String, dynamic>>> Function(int projectId) listFiles;
  final CurseForgePublicationReceiptStore store;
  const CurseForgePublicationService({
    required this.uploadClient,
    required this.readFile,
    required this.listFiles,
    required this.store,
  });

  static String _serverKey(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ValidationError(
        'Publication endpoints must be HTTP(S) base URLs without embedded credentials, queries, or fragments.',
      );
    }
    return normalizeServerKey(raw);
  }

  Future<PreparedCurseForgePublication> prepare({
    required PreparedPublication plan,
    required String slug,
    required String version,
    required String displayName,
    required String minecraft,
    required String loaderId,
    required String? loaderVersion,
    String? pluginLoaderId,
    String? pluginLoaderVersion,
    String? clientLoaderToken,
    bool requireLoaderVersionMatch = true,
    bool requirePluginVersionMatch = true,
    List<PreparedPublication> peers = const [],
  }) async {
    final server = plan.role == PublicationArtifactRole.server
        ? plan
        : plan.dependentServer;
    final project = plan.curseforgeProjectId;
    if (server == null || project == null || project <= 0) {
      throw const ValidationError(
        'A server publication requires a CurseForge project and distribution artifact.',
      );
    }
    if (plan.target != SourceKind.curseforge ||
        server.target != SourceKind.curseforge ||
        server.curseforgeProjectId != project ||
        _serverKey(plan.serverUrl) != _serverKey(server.serverUrl) ||
        plan.token.isEmpty ||
        server.token.isEmpty) {
      throw const ValidationError(
        'Dependent server publication requires matching CurseForge project/endpoints and nonempty upload credentials.',
      );
    }
    final distribution = _validateDistribution(
      server.artifact,
      slug: slug,
      version: version,
      minecraft: minecraft,
      loaderId: loaderId,
      loaderVersion: loaderVersion,
      pluginLoaderId: pluginLoaderId,
      pluginLoaderVersion: pluginLoaderVersion,
      requireLoaderVersionMatch: requireLoaderVersionMatch,
      requirePluginVersionMatch: requirePluginVersionMatch,
    );
    if (plan.role == PublicationArtifactRole.client) {
      if (loaderId != 'vanilla' &&
          (clientLoaderToken == null ||
              distribution.loaderVersion == null ||
              const {
                'stable',
                'latest',
              }.contains(distribution.loaderVersion))) {
        throw const ValidationError(
          'Client publication requires a CurseForge archive loader mapping and a concrete matching server loader version.',
        );
      }
      _validateClient(
        plan.artifact,
        displayName: displayName,
        version: version,
        minecraft: minecraft,
        expectedLoader: loaderId == 'vanilla'
            ? null
            : '$clientLoaderToken-${distribution.loaderVersion}',
      );
    }
    final serverHash = await fileDigest(server.artifact, sha256);
    final serverSha1 = await fileDigest(server.artifact, sha1);
    final clientHash = plan.role == PublicationArtifactRole.client
        ? await fileDigest(plan.artifact, sha256)
        : null;
    final key = _serverKey(plan.serverUrl);
    final releaseType = plan.payload['releaseType'];
    final manual = plan.payload['isMarkedForManualRelease'];
    if (displayName.isEmpty ||
        !const {'release', 'beta', 'alpha'}.contains(releaseType) ||
        manual is! bool) {
      throw const ValidationError('Invalid CurseForge release metadata.');
    }
    if (server.payload['releaseType'] != releaseType ||
        server.payload['isMarkedForManualRelease'] != manual ||
        server.payload['displayName'] is! String ||
        (server.payload['displayName'] as String).isEmpty) {
      throw const ValidationError(
        'Client/server release channel and manual-release metadata must match before publication.',
      );
    }
    final prior = store.read(project, version);
    final receipt =
        prior ??
        CurseForgePublicationReceipt(
          projectId: project,
          release: version,
          slug: slug,
          serverUrl: key,
          displayName: displayName,
          releaseType: releaseType as String,
          manualRelease: manual,
          client: PublicationStepReceipt(sha256: clientHash),
          server: PublicationStepReceipt(sha256: serverHash),
        );
    if (receipt.projectId != project ||
        receipt.release != version ||
        receipt.slug != slug ||
        receipt.serverUrl != key ||
        receipt.displayName != displayName ||
        receipt.releaseType != releaseType ||
        receipt.manualRelease != manual ||
        receipt.server.sha256 != serverHash ||
        (clientHash != null && receipt.client.sha256 != clientHash)) {
      throw const ValidationError(
        'Publication identity or artifact changed from its receipt. Use a new pack release for changed artifacts; inspect the existing remote release before resuming.',
      );
    }
    final peerKeys = <PreparedPublication, String>{};
    for (final peer in peers) {
      final peerKey = jsonEncode([
        peer.target.name,
        _serverKey(peer.serverUrl),
      ]);
      final hash = await fileDigest(peer.artifact, sha256);
      final recorded = receipt.peers[peerKey];
      if (recorded != null && recorded.sha256 != hash) {
        throw const ValidationError(
          'A peer-platform publication artifact changed from its receipt. Start a new release.',
        );
      }
      receipt.peers.putIfAbsent(
        peerKey,
        () => PublicationStepReceipt(sha256: hash),
      );
      peerKeys[peer] = peerKey;
      if (_unknown(receipt.peers[peerKey])) {
        throw const ValidationError(
          'The peer-platform upload outcome is unknown. Inspect its remote release before repeating this publication; use a verified CurseForge server-only retry independently.',
        );
      }
    }
    final explicit = plan.parentFileId;
    if (plan.role == PublicationArtifactRole.server) {
      if (explicit == null || explicit <= 0) {
        throw const UsageError(
          'Server-only publishing requires an explicit positive parent file ID.',
        );
      }
      if (receipt.parentId != null && receipt.parentId != explicit) {
        throw const ValidationError(
          'Explicit parent differs from the recorded publication parent.',
        );
      }
      await _verifyParent(
        project,
        explicit,
        displayName,
        releaseType as String,
      );
      receipt.client.id = explicit.toString();
      receipt.client.state = PublicationStepState.complete;
    } else if (_unknown(receipt.client)) {
      throw const ValidationError(
        'The client upload outcome is unknown. Inspect remote files, then resume with --server-only and an explicitly verified --curseforge-parent-file ID; do not repeat the client POST.',
      );
    }
    if (_unknown(receipt.server)) {
      final parent = receipt.parentId;
      if (parent == null) {
        throw const ValidationError(
          'The server upload outcome is unknown and its parent is unverified. Inspect remote files before retrying.',
        );
      }
      final List<Map<String, dynamic>> remoteFiles;
      try {
        remoteFiles = await listFiles(project);
      } on Object catch (e) {
        throw ValidationError(
          'The server upload outcome is unknown and remote reconciliation failed. ${e is GitrinthException ? e.message : "Inspect the remote parent and artifact hash before retrying."} No duplicate POST was sent.',
        );
      }
      final matches = remoteFiles
          .where(
            (file) =>
                file['modId'] == project &&
                file['parentProjectFileId'] == parent &&
                _sha1(file) == serverSha1 &&
                file['id'] is int &&
                (file['id'] as int) > 0,
          )
          .toList();
      if (matches.length != 1) {
        throw const ValidationError(
          'The server upload outcome is unknown. Inspect remote files for the matching parent and artifact hash before retrying; no duplicate POST was sent.',
        );
      }
      receipt.server.id = matches.single['id'].toString();
      receipt.server.state = PublicationStepState.complete;
    }
    return PreparedCurseForgePublication(
      root: plan,
      server: server,
      receipt: receipt,
      peerKeys: peerKeys,
    );
  }

  bool peerComplete(
    PreparedCurseForgePublication plan,
    PreparedPublication peer,
  ) => _peerStep(plan, peer).state == PublicationStepState.complete;
  String? peerId(
    PreparedCurseForgePublication plan,
    PreparedPublication peer,
  ) => _peerStep(plan, peer).id;
  PublicationStepReceipt _peerStep(
    PreparedCurseForgePublication plan,
    PreparedPublication peer,
  ) {
    final key = plan.peerKeys[peer];
    final step = plan.receipt.peers[key];
    if (step == null) {
      throw StateError(
        'Prepared peer publication is missing its receipt step.',
      );
    }
    return step;
  }

  Future<void> startPeer(
    PreparedCurseForgePublication plan,
    PreparedPublication peer,
  ) async {
    final step = _peerStep(plan, peer);
    await _unchanged(peer.artifact, step.sha256);
    step.state = PublicationStepState.inFlight;
    store.write(plan.receipt);
  }

  void completePeer(
    PreparedCurseForgePublication plan,
    PreparedPublication peer,
    String? id,
  ) {
    final step = _peerStep(plan, peer);
    if (id == null || id.isEmpty) {
      step.state = PublicationStepState.unknown;
      store.write(plan.receipt);
      throw const UserError(
        'Peer-platform upload returned no version ID; its outcome is unknown. Inspect remote releases before retrying.',
      );
    }
    step.id = id;
    step.state = PublicationStepState.complete;
    store.write(plan.receipt);
  }

  void failPeer(
    PreparedCurseForgePublication plan,
    PreparedPublication peer,
    Object error,
  ) {
    final step = _peerStep(plan, peer);
    step.state = _unknownFailure(error)
        ? PublicationStepState.unknown
        : PublicationStepState.failed;
    store.write(plan.receipt);
  }

  Future<CurseForgePublicationResult> publish(
    PreparedCurseForgePublication prepared,
  ) async {
    final receipt = prepared.receipt;
    try {
      store.write(receipt);
      if (receipt.client.state != PublicationStepState.complete) {
        await _upload(
          prepared,
          receipt.client,
          prepared.root,
          prepared.root.payload,
        );
      }
      final parent = receipt.parentId;
      if (parent == null || parent <= 0) {
        throw StateError('Completed client publication has no parent ID.');
      }
      if (receipt.server.state != PublicationStepState.complete) {
        final payload = {...prepared.server.payload, 'parentFileID': parent}
          ..remove('gameVersions')
          ..remove('gameVersionNames');
        await _upload(prepared, receipt.server, prepared.server, payload);
      }
      final child = receipt.childId;
      if (child == null || child <= 0) {
        throw StateError('Completed server publication has no child ID.');
      }
      receipt.classification = 'pending';
      try {
        final parentFile = await readFile(receipt.projectId, parent);
        final childFile = await readFile(receipt.projectId, child);
        if (parentFile['id'] == parent &&
            parentFile['modId'] == receipt.projectId &&
            parentFile['serverPackFileId'] == child &&
            childFile['id'] == child &&
            childFile['modId'] == receipt.projectId &&
            childFile['isServerPack'] == true &&
            childFile['parentProjectFileId'] == parent) {
          receipt.classification = 'confirmed';
        }
      } on Object {
        // Moderation/read visibility can lag successful additional-file uploads.
      }
      store.write(receipt);
      return CurseForgePublicationResult(
        parent,
        child,
        receipt.classification == 'confirmed',
      );
    } on Object catch (e) {
      final message = e is GitrinthException
          ? e.message
          : 'CurseForge publication failed; inspect recorded remote outcomes before retrying.';
      throw CurseForgePublicationFailure(
        message,
        parentId: receipt.parentId,
        childId: receipt.childId,
        unknownOutcome: _unknown(receipt.client) || _unknown(receipt.server),
      );
    }
  }

  Future<void> _upload(
    PreparedCurseForgePublication prepared,
    PublicationStepReceipt step,
    PreparedPublication artifact,
    Map<String, dynamic> metadata,
  ) async {
    await _unchanged(artifact.artifact, step.sha256);
    step.state = PublicationStepState.inFlight;
    store.write(prepared.receipt);
    final CurseForgeUploadResult result;
    try {
      result = await uploadClient.upload(
        projectId: prepared.receipt.projectId,
        token: artifact.token,
        archive: artifact.artifact,
        metadata: metadata,
      );
    } on Object catch (e) {
      step.state = _unknownFailure(e)
          ? PublicationStepState.unknown
          : PublicationStepState.failed;
      store.write(prepared.receipt);
      rethrow;
    }
    step.id = result.fileId.toString();
    step.state = PublicationStepState.complete;
    store.write(prepared.receipt);
  }

  static Future<void> _unchanged(File artifact, String? expected) async {
    if (expected == null || await fileDigest(artifact, sha256) != expected) {
      throw const ValidationError(
        'Prepared publication artifact changed before upload. Inspect the receipt and start a new release for changed bytes.',
      );
    }
  }

  static bool _unknown(PublicationStepReceipt? step) =>
      step != null &&
      const {
        PublicationStepState.inFlight,
        PublicationStepState.unknown,
      }.contains(step.state);
  static bool _unknownFailure(Object error) => switch (error) {
    CurseForgeUploadFailure(:final unknownOutcome) => unknownOutcome,
    AuthenticationError() => false,
    DioException(:final response) =>
      response == null || (response.statusCode ?? 500) >= 500,
    _ => true,
  };
  Future<void> _verifyParent(
    int project,
    int parent,
    String displayName,
    String releaseType,
  ) async {
    final file = await readFile(project, parent);
    if (file['id'] != parent || file['modId'] != project) {
      throw const ValidationError(
        'CurseForge parent file belongs to a different project.',
      );
    }
    if (file['displayName'] != displayName ||
        file['releaseType'] !=
            const {'release': 1, 'beta': 2, 'alpha': 3}[releaseType] ||
        file['isServerPack'] == true) {
      throw const ValidationError(
        'CurseForge parent file does not match the intended client pack release and channel.',
      );
    }
  }

  static String? _sha1(Map<String, dynamic> file) {
    final hashes = file['hashes'];
    if (hashes is! List) return null;
    for (final hash in hashes) {
      if (hash is Map && hash['algo'] == 1 && hash['value'] is String) {
        return (hash['value'] as String).toLowerCase();
      }
    }
    return null;
  }

  static ServerDistributionManifest _validateDistribution(
    File file, {
    required String slug,
    required String version,
    required String minecraft,
    required String loaderId,
    required String? loaderVersion,
    required String? pluginLoaderId,
    required String? pluginLoaderVersion,
    required bool requireLoaderVersionMatch,
    required bool requirePluginVersionMatch,
  }) {
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      _validateArchiveEntries(archive, server: true);
      final marker = archive.findFile(serverDistributionManifestName);
      if (marker == null || !marker.isFile) {
        throw const FormatException('Missing server distribution marker.');
      }
      final raw = jsonDecode(utf8.decode(marker.content));
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid server distribution marker.');
      }
      final manifest = ServerDistributionManifest.fromMap(raw);
      if (manifest.slug != slug ||
          manifest.version != version ||
          manifest.minecraft != minecraft ||
          manifest.loaderId != loaderId ||
          (requireLoaderVersionMatch &&
              manifest.loaderVersion != loaderVersion) ||
          manifest.pluginLoaderId != pluginLoaderId ||
          (requirePluginVersionMatch &&
              manifest.pluginLoaderVersion != pluginLoaderVersion)) {
        throw const FormatException(
          'Server distribution does not match this pack release, Minecraft version, or loader.',
        );
      }
      final actual = archive.files
          .where(
            (entry) =>
                entry.isFile && entry.name != serverDistributionManifestName,
          )
          .toList();
      if (archive.files
                  .where(
                    (entry) => entry.name == serverDistributionManifestName,
                  )
                  .length !=
              1 ||
          actual.length != manifest.files.length) {
        throw const FormatException(
          'Server distribution inventory does not match archive contents.',
        );
      }
      final entriesByPath = <String, List<ArchiveFile>>{};
      for (final entry in actual) {
        (entriesByPath[entry.name] ??= []).add(entry);
      }
      for (final expected in manifest.files) {
        final entries = entriesByPath[expected.path] ?? const <ArchiveFile>[];
        if (entries.length != 1 ||
            entries.single.isSymbolicLink ||
            sha256.convert(entries.single.content).toString() !=
                expected.sha256) {
          throw FormatException(
            'Server distribution inventory/hash mismatch for ${expected.path}.',
          );
        }
      }
      return manifest;
    } on Object catch (e) {
      throw ValidationError(
        'Invalid server distribution ${file.path}: $e. Build it with `gitrinth pack --curseforge --server-distribution`; the legacy manifest-server ZIP is not a distribution.',
      );
    } finally {
      input.closeSync();
    }
  }

  static void _validateArchiveEntries(Archive archive, {required bool server}) {
    for (final entry in archive.files) {
      final path = !entry.isFile && entry.name.endsWith('/')
          ? entry.name.substring(0, entry.name.length - 1)
          : entry.name;
      if (entry.isSymbolicLink ||
          (entry.mode & 0xf000) == 0xa000 ||
          !isSafeServerDistributionPath(path) ||
          (server &&
              entry.name != serverDistributionManifestName &&
              isPrivateServerDistributionPath(path))) {
        throw FormatException(
          'Unsafe/private path or symbolic link in archive: ${entry.name}',
        );
      }
    }
  }

  static void _validateClient(
    File file, {
    required String displayName,
    required String version,
    required String minecraft,
    required String? expectedLoader,
  }) {
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      _validateArchiveEntries(archive, server: false);
      final manifests = archive.files
          .where((entry) => entry.name == 'manifest.json' && entry.isFile)
          .toList();
      if (manifests.length != 1) {
        throw const FormatException(
          'Client ZIP requires exactly one manifest.json.',
        );
      }
      final raw = jsonDecode(utf8.decode(manifests.single.content));
      if (raw is! Map ||
          raw['manifestType'] != 'minecraftModpack' ||
          raw['manifestVersion'] != 1 ||
          raw['version'] != version ||
          raw['name'] is! String ||
          '${raw['name']} $version' != displayName ||
          raw['minecraft'] is! Map ||
          raw['files'] is! List ||
          raw['overrides'] is! String ||
          !isSafeServerDistributionPath(raw['overrides'] as String)) {
        throw const FormatException(
          'Client manifest does not match the intended pack release or format.',
        );
      }
      final game = raw['minecraft'] as Map;
      final loaders = game['modLoaders'];
      if (game['version'] != minecraft ||
          loaders is! List ||
          loaders.any(
            (loader) =>
                loader is! Map ||
                loader['id'] is! String ||
                loader['primary'] is! bool,
          )) {
        throw const FormatException(
          'Client manifest has incompatible Minecraft/loader metadata.',
        );
      }
      final primaries = loaders
          .where((loader) => (loader as Map)['primary'] == true)
          .toList();
      if ((expectedLoader == null && loaders.isNotEmpty) ||
          (expectedLoader != null &&
              (primaries.length != 1 ||
                  (primaries.single as Map)['id'] != expectedLoader))) {
        throw const FormatException(
          'Client and server distribution loader versions do not match.',
        );
      }
      for (final entry in raw['files'] as List) {
        if (entry is! Map ||
            entry['projectID'] is! int ||
            (entry['projectID'] as int) <= 0 ||
            entry['fileID'] is! int ||
            (entry['fileID'] as int) <= 0 ||
            entry['required'] is! bool) {
          throw const FormatException(
            'Invalid client manifest project/file reference.',
          );
        }
      }
    } on Object catch (e) {
      throw ValidationError(
        'Invalid client CurseForge archive ${file.path}: $e. Rebuild the matching client release with `gitrinth pack --curseforge`.',
      );
    } finally {
      input.closeSync();
    }
  }
}
