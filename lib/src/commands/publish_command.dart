import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../app/env.dart';
import '../app/providers.dart';
import '../app/loader_registry_provider.dart';
import '../app/runner_settings.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/changelog_reader.dart';
import '../service/file_digest.dart';
import '../service/curseforge/curseforge_upload_client.dart';
import '../service/curseforge/curseforge_publication_receipt.dart';
import '../service/curseforge/curseforge_publication_service.dart';
import '../service/curseforge/curseforge_url.dart';
import '../service/manifest_io.dart';
import '../service/modrinth/modrinth_auth_interceptor.dart';
import '../service/modrinth/modrinth_url.dart';
import '../service/prepared_publication.dart';
import '../service/user_config.dart';
import 'curseforge_pack_assembler.dart';
import 'pack_assembler.dart';

class PublishCommand extends PublicationCommand {
  @override
  String get invocation => 'gitrinth publish [arguments]';

  @override
  String get description =>
      'Publish built artifacts to the selected platforms.';
}

class CurseForgePublishCommand extends PublicationCommand {
  CurseForgePublishCommand() : super(forcedPlatform: SourceKind.curseforge);

  @override
  String get invocation => 'gitrinth curseforge publish [arguments]';

  @override
  String get description => 'Upload a built CurseForge .zip.';
}

abstract class PublicationCommand extends GitrinthCommand {
  final SourceKind? forcedPlatform;

  @override
  String get name => 'publish';

  PublicationCommand({this.forcedPlatform}) {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Assemble the payload, hash the artifact, and print the JSON without uploading.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Skip the interactive confirmation prompt.',
      )
      ..addFlag(
        'draft',
        negatable: false,
        help:
            'Upload as a draft (Modrinth `status: draft`) instead of publicly listed.',
      )
      ..addFlag(
        'with-server',
        negatable: false,
        help:
            'Upload the client, then associate a server-distribution ZIP as an additional file.',
      )
      ..addFlag(
        'server-only',
        negatable: false,
        help:
            'Retry only the CurseForge server distribution against an explicit verified parent.',
      )
      ..addOption(
        'curseforge-parent-file',
        valueHelp: 'id',
        help: 'Existing client file ID required by --server-only.',
      )
      ..addOption(
        'curseforge-server-pack',
        valueHelp: 'path',
        help:
            'Actual server-distribution ZIP, distinct from the legacy manifest-server ZIP.',
      )
      ..addOption(
        'curseforge-pack',
        valueHelp: 'path',
        help: 'CurseForge .zip artifact path when publishing both targets.',
      )
      ..addOption(
        'curseforge-project',
        valueHelp: 'id',
        help:
            'Numeric CurseForge project ID (required for CurseForge uploads).',
      )
      ..addFlag(
        'publishable',
        negatable: false,
        help: 'Reject target-missing sources and allow_hash_mismatch entries.',
      )
      ..addOption(
        'version-type',
        valueHelp: 'release|beta|alpha',
        allowed: ['release', 'beta', 'alpha'],
        help:
            'Modrinth version channel. Defaults to `beta` when `mods.yaml.version` carries a pre-release suffix, else `release`.',
      )
      ..addOption(
        'changelog',
        valueHelp: 'path',
        help:
            'Path to a Markdown changelog. Defaults to the matching section of CHANGELOG.md when present.',
      )
      ..addOption(
        'pack',
        valueHelp: 'path',
        help:
            'Path to the .mrpack to upload. Defaults to build/<slug>-<version>.mrpack.',
      );
  }

  String _publishLoaderToken(LoaderId id, String host) {
    final token = read(loaderRegistryProvider)[id]?.modrinthTag(host);
    if (token == null) {
      throw ValidationError(
        'Loader ${id.name} has no Modrinth publish mapping for $host.',
      );
    }
    return token;
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageError('Unexpected arguments: ${argResults!.rest.join(' ')}');
    }
    final io = ManifestIo();
    final yaml = io.readModsYaml();
    if (yaml.publishTargets.isEmpty) {
      throw const UserError(
        "publish_to: 'none' in mods.yaml — publishing is disabled for this pack.",
      );
    }
    final targets = forcedPlatform == null
        ? yaml.publishTargets.keys.toList()
        : [forcedPlatform!];
    for (final target in targets) {
      if (!yaml.publishTargets.containsKey(target)) {
        throw UserError('${target.name} is not selected by publish_to.');
      }
    }
    final withServer = argResults!['with-server'] as bool;
    final serverOnly = argResults!['server-only'] as bool;
    final parentRaw = argResults!['curseforge-parent-file'] as String?;
    final parentId = int.tryParse(parentRaw ?? '');
    if (withServer && serverOnly) {
      throw const UsageError(
        '--with-server and --server-only cannot be combined.',
      );
    }
    if ((withServer || serverOnly) &&
        !targets.contains(SourceKind.curseforge)) {
      throw const UsageError(
        'Server publication requires CurseForge as a selected target.',
      );
    }
    if (serverOnly && targets.contains(SourceKind.modrinth)) {
      throw const UsageError(
        '--server-only cannot publish Modrinth. Use `gitrinth curseforge publish --server-only` for a CurseForge-only retry.',
      );
    }
    if (serverOnly && (parentId == null || parentId <= 0)) {
      throw const UsageError(
        '--server-only requires --curseforge-parent-file <positive id>.',
      );
    }
    if (!serverOnly && parentRaw != null) {
      throw const UsageError(
        '--curseforge-parent-file is only valid with --server-only.',
      );
    }
    if (!withServer &&
        !serverOnly &&
        argResults!['curseforge-server-pack'] != null) {
      throw const UsageError(
        '--curseforge-server-pack requires --with-server or --server-only.',
      );
    }
    await prepareLoaderRegistry(container, yaml, offline: true);
    final plans = _preparePublications(
      yaml,
      io,
      targets,
      withServer: withServer,
      serverOnly: serverOnly,
      parentId: parentId,
    );
    final dryRun = argResults!['dry-run'] as bool;
    final cfPlan = plans
        .where(
          (plan) =>
              plan.role == PublicationArtifactRole.server ||
              plan.dependentServer != null,
        )
        .firstOrNull;
    final factory = cfPlan == null ? null : read(curseForgeApiFactoryProvider);
    final service = factory == null
        ? null
        : CurseForgePublicationService(
            uploadClient: CurseForgeUploadClient(
              read(dioProvider),
              baseUrl: cfPlan?.serverUrl ?? defaultCurseForgeUploadBaseUrl,
            ),
            readFile: factory.publicationFile,
            listFiles: factory.publicationFiles,
            store: CurseForgePublicationReceiptStore(io.directory.path),
          );
    final locked = io.readModsLock();
    final loader = locked?.loader ?? yaml.loader;
    final prepared = cfPlan == null || service == null
        ? null
        : await service.prepare(
            plan: cfPlan,
            slug: yaml.slug,
            version: yaml.version,
            displayName: '${yaml.name} ${yaml.version}',
            minecraft: yaml.mcVersion,
            loaderId: loader.mods.name,
            loaderVersion: loader.modLoaderVersion,
            pluginLoaderId: loader.plugins?.name,
            pluginLoaderVersion: loader.pluginLoaderVersion,
            clientLoaderToken: read(
              loaderRegistryProvider,
            )[loader.mods]?.curseforgeArchiveToken,
            requireLoaderVersionMatch: !const {
              'stable',
              'latest',
            }.contains(loader.modLoaderVersion),
            requirePluginVersionMatch: !const {
              'stable',
              'latest',
            }.contains(loader.pluginLoaderVersion),
            peers: plans
                .where((plan) => plan.target == SourceKind.modrinth)
                .toList(),
          );
    if (!dryRun && !(argResults!['force'] as bool)) {
      if (!stdin.hasTerminal) {
        throw const UsageError(
          'publish: refusing to upload without --force when stdin is not a terminal.',
        );
      }
      stdout.write(
        'Publish ${yaml.slug} v${yaml.version} to ${targets.map((e) => e.name).join(', ')}? [y/N] ',
      );
      final answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
      if (answer != 'y' && answer != 'yes') {
        console.message('Aborted.');
        return exitOk;
      }
    }
    final completed = <String>[];
    for (final plan in plans) {
      if (identical(plan, cfPlan) && service != null && prepared != null) {
        if (dryRun) {
          final payload =
              {
                  ...prepared.server.payload,
                  'parentFileID':
                      prepared.receipt.parentId ?? '<returned client file ID>',
                }
                ..remove('gameVersions')
                ..remove('gameVersionNames');
          console.message(
            'Dry run: CurseForge client -> server additional file (server-pack classification requires verification).',
          );
          console.message(
            jsonEncode({
              'client': serverOnly
                  ? {'existingFileID': parentId}
                  : {'artifact': plan.artifact.path, 'metadata': plan.payload},
              'server': {
                'artifact': prepared.server.artifact.path,
                'metadata': payload,
              },
            }),
          );
        } else {
          try {
            final result = await service.publish(prepared);
            console.message(
              'Published CurseForge client file ${result.parentId} and additional server file ${result.childId}.',
            );
            if (result.classificationConfirmed) {
              console.message(
                'Server-pack classification confirmed by CurseForge read-back.',
              );
            } else {
              console.message(
                'Server-pack classification pending: open the matching client release in the CurseForge author console and classify the additional file as its server pack. Rerun the same command to verify; completed uploads are reused.',
              );
            }
          } on CurseForgePublicationFailure catch (e) {
            final parent = e.parentId;
            final surviving = [
              if (completed.isNotEmpty) completed.join(', '),
              if (parent != null) 'CurseForge client file $parent',
              if (e.childId != null) 'CurseForge child file ${e.childId}',
            ];
            final retry = parent == null
                ? 'Inspect remote files before any retry.'
                : 'Retry only the server: ${_serverRetryCommand(io.directory.path, prepared, parent)}';
            final pendingPeers = plans
                .where(
                  (peer) =>
                      peer.target == SourceKind.modrinth &&
                      !service.peerComplete(prepared, peer),
                )
                .map((peer) => peer.target.name)
                .toList();
            throw UserError(
              '${surviving.isEmpty ? "Publication failed" : "Partial publication; ${surviving.join(', ')} survives"}: ${e.message}\n${e.unknownOutcome ? "Remote outcome is unknown; inspect remote files before retrying. Reconciliation must succeed before another POST.\n" : ""}$retry${pendingPeers.isEmpty ? "" : "\nOther selected targets remain pending: ${pendingPeers.join(', ')}."}',
            );
          }
        }
      } else if (service != null &&
          prepared != null &&
          plan.target == SourceKind.modrinth &&
          !dryRun) {
        if (service.peerComplete(prepared, plan)) {
          console.message(
            'Reusing completed Modrinth version ${service.peerId(prepared, plan)}.',
          );
          completed.add('Modrinth version ${service.peerId(prepared, plan)}');
          continue;
        }
        await service.startPeer(prepared, plan);
        try {
          final id = await _publish(plan, yaml, dryRun: false);
          service.completePeer(prepared, plan, id);
          completed.add('Modrinth version $id');
        } on Object catch (e) {
          service.failPeer(prepared, plan, e);
          throw UserError(
            'Peer-platform publication failed. ${e is GitrinthException ? e.message : "Inspect its remote release and the publication receipt before retrying."}',
          );
        }
      } else {
        final id = await _publish(plan, yaml, dryRun: dryRun);
        if (!dryRun) completed.add('${plan.target.name} file $id');
      }
    }
    return exitOk;
  }

  List<PreparedPublication> _preparePublications(
    ModsYaml yaml,
    ManifestIo io,
    List<SourceKind> targets, {
    required bool withServer,
    required bool serverOnly,
    required int? parentId,
  }) {
    final lock = io.readModsLock();
    final publishable = argResults!['publishable'] as bool;
    if (lock == null && publishable) {
      throw const UserError(
        '--publishable requires mods.lock. Run `gitrinth get` first.',
      );
    }
    final env = read(environmentProvider);
    final stored = _readTokens();
    final pending =
        <
          ({
            SourceKind target,
            String serverUrl,
            String token,
            File artifact,
            int? projectId,
          })
        >[];
    for (final target in targets) {
      final projectId = target == SourceKind.curseforge
          ? int.tryParse(argResults!['curseforge-project'] as String? ?? '')
          : null;
      if (target == SourceKind.curseforge && (projectId ?? 0) <= 0) {
        throw const UsageError(
          'CurseForge publishing requires --curseforge-project <numeric id>.',
        );
      }
      final serverUrl = target == SourceKind.modrinth
          ? yaml.publishTargets[target] ?? resolveModrinthBaseUrl(env)
          : env['GITRINTH_CURSEFORGE_UPLOAD_URL'] ??
                defaultCurseForgeUploadBaseUrl;
      final String? token;
      if (target == SourceKind.curseforge) {
        token = resolveCurseForgeUploadToken(env: env, userTokens: stored);
        if (token == null) {
          throw const AuthenticationError(
            'No CurseForge publish token configured. Set GITRINTH_CURSEFORGE_UPLOAD_TOKEN or run `gitrinth token add curseforge.com`.',
          );
        }
      } else {
        final envToken = env['GITRINTH_TOKEN'];
        token =
            normalizeServerKey(serverUrl) ==
                    normalizeServerKey(resolveModrinthBaseUrl(env)) &&
                (envToken ?? '').isNotEmpty
            ? envToken
            : _bestTokenFor(stored, serverUrl);
        if (token == null || token.isEmpty) {
          throw AuthenticationError(
            'No token configured for $serverUrl. Run `gitrinth token add $serverUrl`.',
          );
        }
      }
      final artifact = serverOnly && target == SourceKind.curseforge
          ? _serverArtifactFor(yaml)
          : _artifactFor(yaml, target, targets.length > 1);
      if (!artifact.existsSync()) {
        throw UserError(
          'Pack artifact not found at ${artifact.path}. Run `gitrinth pack${target == SourceKind.curseforge ? ' --curseforge' : ''}` first.',
        );
      }
      if (lock != null && !serverOnly) {
        if (target == SourceKind.modrinth) {
          buildIndex(
            registry: read(loaderRegistryProvider),
            yaml: yaml,
            lock: lock,
            target: PackTarget.client,
            publishable: publishable,
          );
        } else {
          buildCurseForgeManifest(
            registry: read(loaderRegistryProvider),
            yaml: yaml,
            lock: lock,
            target: PackTarget.client,
            publishable: publishable,
          );
        }
        final overrides = collectOverrides(
          lock: lock,
          cache: read(cacheProvider),
          projectDir: io.directory.path,
          target: PackTarget.client,
          platform: target,
          modrinthHost: resolveModrinthBaseUrl(env),
        );
        for (final entry in overrides.entries.where((e) => e.section != null)) {
          console.message(
            'Warning: ${entry.slug} is unavailable on ${target.name}; bundled as a loose override with author permission.',
          );
        }
      }
      pending.add((
        target: target,
        serverUrl: serverUrl,
        token: token,
        artifact: artifact,
        projectId: projectId,
      ));
    }
    final changelog =
        _resolveChangelog(yaml: yaml, projectDir: io.directory) ?? '';
    final versionType =
        (argResults!['version-type'] as String?) ??
        _defaultVersionType(yaml.version);
    final draft = argResults!['draft'] as bool;
    return [
      for (final target in pending)
        PreparedPublication(
          target: target.target,
          serverUrl: target.serverUrl,
          token: target.token,
          artifact: target.artifact,
          curseforgeProjectId: target.projectId,
          role: serverOnly
              ? PublicationArtifactRole.server
              : PublicationArtifactRole.client,
          parentFileId: serverOnly ? parentId : null,
          dependentServer: withServer && target.target == SourceKind.curseforge
              ? PreparedPublication(
                  target: SourceKind.curseforge,
                  serverUrl: target.serverUrl,
                  token: target.token,
                  artifact: _serverArtifactFor(yaml),
                  curseforgeProjectId: target.projectId,
                  role: PublicationArtifactRole.server,
                  payload: {
                    'displayName': '${yaml.name} ${yaml.version} Server',
                    'changelog': changelog,
                    'changelogType': 'markdown',
                    'releaseType': versionType,
                    'isMarkedForManualRelease': draft,
                  },
                )
              : null,
          payload: target.target == SourceKind.modrinth
              ? {
                  'name': '${yaml.name} ${yaml.version}',
                  'version_number': yaml.version,
                  'changelog': changelog,
                  'dependencies': const <Map<String, dynamic>>[],
                  'game_versions': List<String>.unmodifiable([yaml.mcVersion]),
                  'version_type': versionType,
                  'loaders': List<String>.unmodifiable([
                    _publishLoaderToken(yaml.loader.mods, target.serverUrl),
                  ]),
                  'featured': false,
                  'status': draft ? 'draft' : 'listed',
                  'project_id': yaml.slug,
                  'file_parts': const ['file'],
                  'primary_file': 'file',
                }
              : {
                  'displayName':
                      '${yaml.name} ${yaml.version}${serverOnly ? ' Server' : ''}',
                  'changelog': changelog,
                  'changelogType': 'markdown',
                  'gameVersionNames': List<String>.unmodifiable([
                    yaml.mcVersion,
                  ]),
                  'releaseType': versionType,
                  'isMarkedForManualRelease': draft,
                },
        ),
    ];
  }

  Future<String?> _publish(
    PreparedPublication plan,
    ModsYaml yaml, {
    required bool dryRun,
  }) async {
    if (plan.target == SourceKind.curseforge) {
      if (dryRun) {
        console.message('Dry run: would publish to CurseForge');
        console.message(
          const JsonEncoder.withIndent('  ').convert(plan.payload),
        );
        return null;
      }
      final result =
          await CurseForgeUploadClient(
            read(dioProvider),
            baseUrl: plan.serverUrl,
          ).upload(
            projectId: plan.curseforgeProjectId!,
            token: plan.token,
            archive: plan.artifact,
            metadata: plan.payload,
          );
      console.message(
        'Published ${yaml.slug} v${yaml.version} to CurseForge (file id: ${result.fileId}).',
      );
      return result.fileId.toString();
    }
    if (dryRun) {
      final [sha1Digest, sha512Digest] = await fileDigests(plan.artifact, [
        sha1,
        sha512,
      ]);
      console.message('Dry run: would publish to ${plan.serverUrl}');
      console.message(
        'Pack: ${plan.artifact.path} (sha1=$sha1Digest sha512=$sha512Digest)',
      );
      console.message(const JsonEncoder.withIndent('  ').convert(plan.payload));
      return null;
    }
    final response = await read(dioProvider).post<dynamic>(
      '${plan.serverUrl.replaceFirst(RegExp(r'/$'), '')}/project/${yaml.slug}/version',
      data: FormData.fromMap({
        'data': MultipartFile.fromBytes(
          utf8.encode(jsonEncode(plan.payload)),
          filename: 'data.json',
          contentType: DioMediaType('application', 'json'),
        ),
        'file': await MultipartFile.fromFile(
          plan.artifact.path,
          filename: p.basename(plan.artifact.path),
          contentType: DioMediaType('application', 'x-modrinth-modpack+zip'),
        ),
      }),
      options: Options(
        contentType: 'multipart/form-data',
        headers: {'Authorization': plan.token},
        extra: const {kModrinthAuthRequired: true},
      ),
    );
    final body = response.data;
    final versionId = body is Map ? body['id'] : null;
    console.message(
      'Published ${yaml.slug} v${yaml.version} to ${plan.serverUrl}${versionId == null ? '' : ' (version id: $versionId)'}.',
    );
    return versionId?.toString();
  }

  File _serverArtifactFor(ModsYaml yaml) {
    final raw =
        (argResults!['curseforge-server-pack'] as String?) ??
        p.join('build', '${yaml.slug}-${yaml.version}-server-distribution.zip');
    final file = File(p.normalize(p.absolute(raw)));
    if (!file.existsSync()) {
      throw UserError(
        'Server distribution not found at ${file.path}. Run `gitrinth pack --curseforge --server-distribution` first.',
      );
    }
    return file;
  }

  String _serverRetryCommand(
    String projectDir,
    PreparedCurseForgePublication prepared,
    int parent,
  ) {
    final settings = read(runnerSettingsProvider);
    final config = settings.configPath;
    final descriptors = settings.loaderDescriptorsPath;
    return [
      'gitrinth',
      '-C',
      _shellQuote(p.normalize(p.absolute(projectDir))),
      if (config != null && config.isNotEmpty) ...[
        '--config',
        _shellQuote(read(userConfigPathProvider)),
      ],
      'curseforge',
      'publish',
      if (descriptors != null) ...[
        '--loader-descriptors',
        _shellQuote(p.normalize(p.absolute(descriptors))),
      ],
      '--server-only',
      '--curseforge-project',
      prepared.receipt.projectId.toString(),
      '--curseforge-parent-file',
      parent.toString(),
      '--curseforge-server-pack',
      _shellQuote(prepared.server.artifact.path),
      '--version-type',
      prepared.receipt.releaseType,
      if (prepared.receipt.manualRelease) '--draft',
      '--force',
    ].join(' ');
  }

  String _shellQuote(String value) => Platform.isWindows
      ? "'${value.replaceAll("'", "''")}'"
      : "'${value.replaceAll("'", "'\\''")}'";

  Map<String, String> _readTokens() {
    try {
      return read(userConfigStoreProvider).read().tokens;
    } on UserError {
      return const {};
    }
  }

  String? _bestTokenFor(Map<String, String> tokens, String baseUrl) {
    final key = normalizeServerKey(baseUrl);
    String? best;
    for (final entry in tokens.entries) {
      if ((key == entry.key || key.startsWith('${entry.key}/')) &&
          (best == null || entry.key.length > best.length)) {
        best = entry.key;
      }
    }
    return best == null ? null : tokens[best];
  }

  File _artifactFor(ModsYaml yaml, SourceKind target, bool multiple) {
    final raw = target == SourceKind.modrinth
        ? (argResults!['pack'] as String?) ??
              p.join('build', '${yaml.slug}-${yaml.version}.mrpack')
        : (argResults!['curseforge-pack'] as String?) ??
              (multiple ? null : argResults!['pack'] as String?) ??
              p.join('build', '${yaml.slug}-${yaml.version}.zip');
    return File(p.normalize(p.absolute(raw)));
  }

  String? _resolveChangelog({
    required ModsYaml yaml,
    required Directory projectDir,
  }) {
    final flag = argResults!['changelog'] as String?;
    if (flag != null && flag.isNotEmpty) {
      final file = File(flag);
      if (!file.existsSync()) throw UserError('Changelog not found: $flag');
      return file.readAsStringSync().trim();
    }
    return readChangelogSection(
      changelogFile: File(p.join(projectDir.path, 'CHANGELOG.md')),
      version: yaml.version,
    );
  }

  String _defaultVersionType(String version) {
    final hyphen = version.indexOf('-');
    if (hyphen < 0) return 'release';
    return version.substring(hyphen + 1).toLowerCase().startsWith('alpha')
        ? 'alpha'
        : 'beta';
  }
}
