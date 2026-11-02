import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../app/env.dart';
import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_yaml.dart';
import '../service/changelog_reader.dart';
import '../service/curseforge/curseforge_upload_client.dart';
import '../service/curseforge/curseforge_url.dart';
import '../service/manifest_io.dart';
import '../service/modrinth/modrinth_auth_interceptor.dart';
import '../service/modrinth/modrinth_url.dart';
import '../service/prepared_publication.dart';
import '../service/user_config.dart';
import 'curseforge_pack_assembler.dart';
import 'pack_assembler.dart';

class PublishCommand extends PublicationCommand {
  PublishCommand() : super(platformAware: true);

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
  final bool platformAware;
  final SourceKind? forcedPlatform;

  @override
  String get name => 'publish';

  PublicationCommand({this.platformAware = false, this.forcedPlatform}) {
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
    final targets = platformAware
        ? yaml.publishTargets.keys.toList()
        : [forcedPlatform ?? SourceKind.modrinth];
    for (final target in targets) {
      if (!yaml.publishTargets.containsKey(target)) {
        throw UserError('${target.name} is not selected by publish_to.');
      }
    }
    final plans = _preparePublications(yaml, io, targets);
    final dryRun = argResults!['dry-run'] as bool;
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
    for (final plan in plans) {
      await _publish(plan, yaml, dryRun: dryRun);
    }
    return exitOk;
  }

  List<PreparedPublication> _preparePublications(
    ModsYaml yaml,
    ManifestIo io,
    List<SourceKind> targets,
  ) {
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
      final artifact = _artifactFor(yaml, target, targets.length > 1);
      if (!artifact.existsSync()) {
        throw UserError(
          'Pack artifact not found at ${artifact.path}. Run `gitrinth pack${target == SourceKind.curseforge ? ' --curseforge' : ''}` first.',
        );
      }
      if (lock != null) {
        if (target == SourceKind.modrinth) {
          buildIndex(
            yaml: yaml,
            lock: lock,
            target: PackTarget.client,
            publishable: publishable,
          );
        } else {
          buildCurseForgeManifest(
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
          payload: target.target == SourceKind.modrinth
              ? {
                  'name': '${yaml.name} ${yaml.version}',
                  'version_number': yaml.version,
                  'changelog': changelog,
                  'dependencies': const <Map<String, dynamic>>[],
                  'game_versions': List<String>.unmodifiable([yaml.mcVersion]),
                  'version_type': versionType,
                  'loaders': List<String>.unmodifiable([yaml.loader.mods.name]),
                  'featured': false,
                  'status': draft ? 'draft' : 'listed',
                  'project_id': yaml.slug,
                  'file_parts': const ['file'],
                  'primary_file': 'file',
                }
              : {
                  'displayName': '${yaml.name} ${yaml.version}',
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

  Future<void> _publish(
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
        return;
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
        'Published ${yaml.slug} v${yaml.version} to CurseForge${result is Map ? ' (file id: ${result['id']})' : ''}.',
      );
      return;
    }
    final bytes = plan.artifact.readAsBytesSync();
    if (dryRun) {
      console.message('Dry run: would publish to ${plan.serverUrl}');
      console.message(
        'Pack: ${plan.artifact.path} (sha1=${sha1.convert(bytes)} sha512=${sha512.convert(bytes)})',
      );
      console.message(const JsonEncoder.withIndent('  ').convert(plan.payload));
      return;
    }
    final response = await read(dioProvider).post<dynamic>(
      '${plan.serverUrl.replaceFirst(RegExp(r'/$'), '')}/project/${yaml.slug}/version',
      data: FormData.fromMap({
        'data': MultipartFile.fromBytes(
          utf8.encode(jsonEncode(plan.payload)),
          filename: 'data.json',
          contentType: DioMediaType('application', 'json'),
        ),
        'file': MultipartFile.fromBytes(
          bytes,
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
  }

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
