import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../cli/exceptions.dart';
import '../../util/atomic_file_writer.dart';

enum PublicationStepState { pending, inFlight, failed, complete, unknown }

class PublicationStepReceipt {
  PublicationStepState state;
  String? id;
  final String? sha256;
  PublicationStepReceipt({
    this.state = PublicationStepState.pending,
    this.id,
    this.sha256,
  });
  Map<String, dynamic> toMap() => {
    'state': state.name,
    if (id != null) 'id': id,
    if (sha256 != null) 'sha256': sha256,
  };
  factory PublicationStepReceipt.fromMap(Map raw, {bool numericId = false}) {
    final state = PublicationStepState.values
        .where((v) => v.name == raw['state'])
        .firstOrNull;
    final id = raw['id'];
    final hash = raw['sha256'];
    if (state == null ||
        (id != null && id is! String) ||
        (hash != null &&
            (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))) ||
        (state == PublicationStepState.complete &&
            (id is! String ||
                id.isEmpty ||
                (numericId && (int.tryParse(id) ?? 0) <= 0)))) {
      throw const FormatException('Invalid publication step.');
    }
    return PublicationStepReceipt(
      state: state,
      id: id as String?,
      sha256: hash as String?,
    );
  }
}

/// Token-free durable state. In-flight steps are never safe to repeat blindly.
class CurseForgePublicationReceipt {
  final int projectId;
  final String release;
  final String slug;
  final String serverUrl;
  final String displayName;
  final String releaseType;
  final bool manualRelease;
  final PublicationStepReceipt client;
  final PublicationStepReceipt server;
  final Map<String, PublicationStepReceipt> peers;
  String classification;
  CurseForgePublicationReceipt({
    required this.projectId,
    required this.release,
    required this.slug,
    required this.serverUrl,
    required this.displayName,
    required this.releaseType,
    required this.manualRelease,
    required this.client,
    required this.server,
    Map<String, PublicationStepReceipt>? peers,
    this.classification = 'pending',
  }) : peers = peers ?? {};

  int? get parentId => int.tryParse(client.id ?? '');
  int? get childId => int.tryParse(server.id ?? '');
  Map<String, dynamic> toMap() => {
    'version': 1,
    'target': 'curseforge',
    'projectId': projectId,
    'release': release,
    'slug': slug,
    'serverUrl': serverUrl,
    'displayName': displayName,
    'releaseType': releaseType,
    'manualRelease': manualRelease,
    'client': client.toMap(),
    'server': server.toMap(),
    'classification': classification,
    'peers': {for (final e in peers.entries) e.key: e.value.toMap()},
  };
  factory CurseForgePublicationReceipt.fromMap(Map raw) {
    if (raw['version'] != 1 ||
        raw['target'] != 'curseforge' ||
        raw['projectId'] is! int ||
        (raw['projectId'] as int) <= 0 ||
        raw['release'] is! String ||
        raw['slug'] is! String ||
        raw['serverUrl'] is! String ||
        raw['client'] is! Map ||
        raw['server'] is! Map ||
        raw['peers'] is! Map ||
        raw['displayName'] is! String ||
        !const {'release', 'beta', 'alpha'}.contains(raw['releaseType']) ||
        raw['manualRelease'] is! bool ||
        !const {'pending', 'confirmed'}.contains(raw['classification'])) {
      throw const FormatException('Invalid publication receipt.');
    }
    final peers = <String, PublicationStepReceipt>{};
    for (final entry in (raw['peers'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid publication peer.');
      }
      peers[entry.key as String] = PublicationStepReceipt.fromMap(
        entry.value as Map,
      );
    }
    return CurseForgePublicationReceipt(
      projectId: raw['projectId'] as int,
      release: raw['release'] as String,
      slug: raw['slug'] as String,
      serverUrl: raw['serverUrl'] as String,
      client: PublicationStepReceipt.fromMap(
        raw['client'] as Map,
        numericId: true,
      ),
      displayName: raw['displayName'] as String,
      releaseType: raw['releaseType'] as String,
      manualRelease: raw['manualRelease'] as bool,
      server: PublicationStepReceipt.fromMap(
        raw['server'] as Map,
        numericId: true,
      ),
      peers: peers,
      classification: raw['classification'] as String,
    );
  }
}

class CurseForgePublicationReceiptStore {
  final String projectDir;
  const CurseForgePublicationReceiptStore(this.projectDir);
  String path(int projectId, String release) {
    final key = sha256
        .convert(utf8.encode(jsonEncode([projectId.toString(), release])))
        .toString();
    return p.join(
      projectDir,
      '.gitrinth',
      'publications',
      'curseforge',
      projectId.toString(),
      '$key.json',
    );
  }

  CurseForgePublicationReceipt? read(int projectId, String release) {
    final file = File(path(projectId, release));
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) {
        throw const FormatException('Receipt must be an object.');
      }
      return CurseForgePublicationReceipt.fromMap(raw);
    } on Object catch (_) {
      throw ValidationError(
        'Cannot read publication receipt at ${file.path}. Inspect and reconcile the recorded remote outcomes before publishing again.',
      );
    }
  }

  /// Replaces only the snapshot this invocation actually prepared against.
  String writeIfUnchanged(
    CurseForgePublicationReceipt receipt,
    String? expected,
  ) {
    final file = File(path(receipt.projectId, receipt.release));
    try {
      file.parent.createSync(recursive: true);
      final lock = File(
        '${file.path}.transaction.lock',
      ).openSync(mode: FileMode.append);
      try {
        lock.lockSync(FileLock.blockingExclusive);
        try {
          final current = read(receipt.projectId, receipt.release);
          final snapshot = current == null ? null : jsonEncode(current.toMap());
          if (snapshot != expected) {
            throw const ValidationError(
              'Publication receipt changed after preparation. Another invocation may have uploaded files; rerun to reload and reconcile its state before any further POST.',
            );
          }
          final contents = jsonEncode(receipt.toMap());
          atomicReplaceString(file.path, contents);
          return contents;
        } finally {
          lock.unlockSync();
        }
      } finally {
        lock.closeSync();
      }
    } on FileSystemException {
      throw UserError(
        'Cannot persist publication receipt at ${file.path}. No further uploads were attempted; inspect remote files before retrying.',
      );
    }
  }
}
