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
import '../service/manifest_io.dart';
import '../service/modrinth/modrinth_auth_interceptor.dart';
import '../service/modrinth/modrinth_url.dart';
import '../service/user_config.dart';
import '../service/curseforge/curseforge_url.dart';
import '../service/curseforge/curseforge_upload_client.dart';
import 'pack_assembler.dart';
import 'curseforge_pack_assembler.dart';

class ModrinthPublishCommand extends GitrinthCommand {
  final bool platformAware;
  final SourceKind? forcedPlatform;
  bool _confirmed = false;
  @override
  String get name => 'publish';

  @override
  String get description =>
      'Upload a built .mrpack as a new version on the Modrinth-compatible server.';

  @override
  String get invocation => 'gitrinth modrinth publish [arguments]';

  ModrinthPublishCommand({this.platformAware = false, this.forcedPlatform}) {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Assemble the payload, hash the artifact, and print the JSON '
            'without uploading.',
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
            'Upload as a draft (Modrinth `status: draft`) instead of '
            'publicly listed.',
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
            'Modrinth version channel. Defaults to `beta` when '
            '`mods.yaml.version` carries a pre-release suffix, else `release`.',
      )
      ..addOption(
        'changelog',
        valueHelp: 'path',
        help:
            'Path to a Markdown changelog. Defaults to the matching '
            'section of CHANGELOG.md when present.',
      )
      ..addOption(
        'pack',
        valueHelp: 'path',
        help:
            'Path to the .mrpack to upload. Defaults to '
            'build/<slug>-<version>.mrpack.',
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

    final env = read(environmentProvider);
    final targets = platformAware
        ? yaml.publishTargets.keys.toList()
        : [forcedPlatform ?? SourceKind.modrinth];
    for (final target in targets) {
      if (!yaml.publishTargets.containsKey(target)) {
        throw UserError('${target.name} is not selected by publish_to.');
      }
    }
    final lock = io.readModsLock();
    if (lock == null && argResults!['publishable'] as bool) {
      throw const UserError(
        '--publishable requires mods.lock. Run `gitrinth get` first.',
      );
    }
    for (final target in targets) {
      if (target == SourceKind.curseforge &&
          (int.tryParse(argResults!['curseforge-project'] as String? ?? '') ??
                  0) <=
              0) {
        throw const UsageError(
          'CurseForge publishing requires --curseforge-project <numeric id>.',
        );
      }
      final stored = _readTokens();
      if (target == SourceKind.curseforge) {
        if (resolveCurseForgeUploadToken(env: env, userTokens: stored) ==
            null) {
          throw const AuthenticationError(
            'No CurseForge publish token configured. '
            'Set GITRINTH_CURSEFORGE_UPLOAD_TOKEN or run `gitrinth token add curseforge.com`.',
          );
        }
      } else {
        final host = yaml.publishTargets[target] ?? resolveModrinthBaseUrl(env);
        final envTokenApplies =
            normalizeServerKey(host) ==
                normalizeServerKey(resolveModrinthBaseUrl(env)) &&
            (env['GITRINTH_TOKEN'] ?? '').isNotEmpty;
        if (!envTokenApplies && _bestTokenFor(stored, host) == null) {
          throw AuthenticationError(
            'No token configured for $host. Run `gitrinth token add $host`.',
          );
        }
      }
      final pack = _artifactFor(yaml, target, targets.length > 1);
      if (!pack.existsSync()) {
        throw UserError(
          'Pack artifact not found at ${pack.path}. Run `gitrinth pack${target == SourceKind.curseforge ? ' --curseforge' : ''}` first.',
        );
      }
      if (lock != null) {
        if (target == SourceKind.modrinth) {
          buildIndex(
            yaml: yaml,
            lock: lock,
            target: PackTarget.client,
            publishable: argResults!['publishable'] as bool,
          );
        } else {
          buildCurseForgeManifest(
            yaml: yaml,
            lock: lock,
            target: PackTarget.client,
            publishable: argResults!['publishable'] as bool,
          );
        }
        final overrides = collectOverrides(
          lock: lock,
          cache: read(cacheProvider),
          projectDir: io.directory.path,
          target: PackTarget.client,
          platform: target,
          modrinthHost: yaml.modrinthHost ?? resolveModrinthBaseUrl(env),
        );
        for (final entry in overrides.entries.where((e) => e.section != null)) {
          console.message(
            'Warning: ${entry.slug} is unavailable on ${target.name}; '
            'bundled as a loose override with author permission.',
          );
        }
      }
    }
    _resolveChangelog(yaml: yaml, projectDir: io.directory);
    if (!(argResults!['dry-run'] as bool) && !(argResults!['force'] as bool)) {
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
    _confirmed = true;
    var exitCode = exitOk;
    for (final target in targets) {
      if (target == SourceKind.curseforge) {
        exitCode = await _publishCurseForge(yaml, io);
      } else {
        exitCode = await _publishModrinth(yaml, io, env);
      }
      if (exitCode != exitOk) return exitCode;
    }
    return exitCode;
  }

  Future<int> _publishModrinth(
    ModsYaml yaml,
    ManifestIo io,
    Map<String, String> env,
  ) async {
    final baseUrl =
        yaml.publishTargets[SourceKind.modrinth] ?? resolveModrinthBaseUrl(env);

    final hasEnvToken = (env['GITRINTH_TOKEN'] ?? '').isNotEmpty;
    final stored = _readTokens();
    if (!hasEnvToken && _bestTokenFor(stored, baseUrl) == null) {
      throw AuthenticationError(
        'No token configured for $baseUrl. Run `gitrinth modrinth login` '
        '(default host) or `gitrinth modrinth token add $baseUrl`.',
      );
    }

    final pack = _resolvePackPath(yaml: yaml);
    if (!pack.existsSync()) {
      throw UserError(
        'Pack artifact not found at ${pack.path}. Run `gitrinth pack` first '
        'or pass --pack <path>.',
      );
    }

    final bytes = pack.readAsBytesSync();
    final sha1Hex = sha1.convert(bytes).toString();
    final sha512Hex = sha512.convert(bytes).toString();

    final versionType =
        (argResults!['version-type'] as String?) ??
        _defaultVersionType(yaml.version);
    final draft = argResults!['draft'] as bool;
    final changelog = _resolveChangelog(yaml: yaml, projectDir: io.directory);

    final payload = <String, dynamic>{
      'name': '${yaml.name} ${yaml.version}',
      'version_number': yaml.version,
      'changelog': changelog ?? '',
      'dependencies': <Map<String, dynamic>>[],
      'game_versions': [yaml.mcVersion],
      'version_type': versionType,
      'loaders': [yaml.loader.mods.name],
      'featured': false,
      'status': draft ? 'draft' : 'listed',
      'project_id': yaml.slug,
      'file_parts': ['file'],
      'primary_file': 'file',
    };

    final dryRun = argResults!['dry-run'] as bool;
    if (dryRun) {
      console.message('Dry run: would publish to $baseUrl');
      console.message('Pack: ${pack.path} (sha1=$sha1Hex sha512=$sha512Hex)');
      console.message(const JsonEncoder.withIndent('  ').convert(payload));
      return exitOk;
    }

    final force = argResults!['force'] as bool;
    if (!force && !_confirmed) {
      if (!stdin.hasTerminal) {
        throw const UsageError(
          'publish: refusing to upload without --force when stdin is not a '
          'terminal. Re-run with -f / --force.',
        );
      }
      stdout.write('Publish ${yaml.slug} v${yaml.version} to $baseUrl? [y/N] ');
      final answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
      if (answer != 'y' && answer != 'yes') {
        console.message('Aborted.');
        return exitOk;
      }
    }

    final uploadUrl = _joinPath(baseUrl, '/project/${yaml.slug}/version');
    final form = FormData.fromMap({
      'data': MultipartFile.fromBytes(
        utf8.encode(jsonEncode(payload)),
        filename: 'data.json',
        contentType: DioMediaType('application', 'json'),
      ),
      'file': MultipartFile.fromBytes(
        bytes,
        filename: p.basename(pack.path),
        contentType: DioMediaType('application', 'x-modrinth-modpack+zip'),
      ),
    });

    final dio = read(dioProvider);
    final response = await dio.post<dynamic>(
      uploadUrl,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        extra: const {kModrinthAuthRequired: true},
      ),
    );
    final body = response.data;
    final versionId = body is Map ? body['id'] : null;
    console.message(
      'Published ${yaml.slug} v${yaml.version} to $baseUrl'
      '${versionId == null ? '' : ' (version id: $versionId)'}.',
    );
    return exitOk;
  }

  Future<int> _publishCurseForge(ModsYaml yaml, ManifestIo io) async {
    final env = read(environmentProvider);
    final token = resolveCurseForgeUploadToken(
      env: env,
      userTokens: _readTokens(),
    );
    if (token == null) {
      throw const AuthenticationError(
        'No CurseForge publish token configured. '
        'Set GITRINTH_CURSEFORGE_UPLOAD_TOKEN or run `gitrinth token add curseforge.com`.',
      );
    }
    final pack = _artifactFor(
      yaml,
      SourceKind.curseforge,
      platformAware && yaml.publishTargets.length > 1,
    );
    if (!pack.existsSync()) {
      throw UserError(
        'Pack artifact not found at ${pack.path}. Run `gitrinth pack --curseforge` first.',
      );
    }
    final metadata = <String, dynamic>{
      'displayName': '${yaml.name} ${yaml.version}',
      'changelog':
          _resolveChangelog(yaml: yaml, projectDir: io.directory) ?? '',
      'changelogType': 'markdown',
      'gameVersionNames': [yaml.mcVersion],
      'releaseType':
          (argResults!['version-type'] as String?) ??
          _defaultVersionType(yaml.version),
      'isMarkedForManualRelease': argResults!['draft'] as bool,
    };
    if (argResults!['dry-run'] as bool) {
      console.message('Dry run: would publish to CurseForge');
      console.message(const JsonEncoder.withIndent('  ').convert(metadata));
      return exitOk;
    }
    if (!(argResults!['force'] as bool) && !_confirmed) {
      if (!stdin.hasTerminal) {
        throw const UsageError(
          'publish: refusing to upload without --force when stdin is not a terminal.',
        );
      }
      stdout.write(
        'Publish ${yaml.slug} v${yaml.version} to CurseForge? [y/N] ',
      );
      final answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
      if (answer != 'y' && answer != 'yes') {
        console.message('Aborted.');
        return exitOk;
      }
    }
    final client = CurseForgeUploadClient(
      read(dioProvider),
      baseUrl:
          env['GITRINTH_CURSEFORGE_UPLOAD_URL'] ??
          defaultCurseForgeUploadBaseUrl,
    );
    final result = await client.upload(
      projectId: int.parse(argResults!['curseforge-project'] as String),
      token: token,
      archive: pack,
      metadata: metadata,
    );
    console.message(
      'Published ${yaml.slug} v${yaml.version} to CurseForge'
      '${result is Map ? ' (file id: ${result['id']})' : ''}.',
    );
    return exitOk;
  }

  Map<String, String> _readTokens() {
    try {
      return read(userConfigStoreProvider).read().tokens;
    } on UserError {
      return const <String, String>{};
    }
  }

  String? _bestTokenFor(Map<String, String> tokens, String baseUrl) {
    final key = normalizeServerKey(baseUrl);
    String? best;
    for (final entry in tokens.entries) {
      if (key == entry.key || key.startsWith('${entry.key}/')) {
        if (best == null || entry.key.length > best.length) {
          best = entry.key;
        }
      }
    }
    return best == null ? null : tokens[best];
  }

  File _resolvePackPath({required ModsYaml yaml}) {
    final raw =
        (argResults!['pack'] as String?) ??
        p.join('build', '${yaml.slug}-${yaml.version}.mrpack');
    return File(p.normalize(p.absolute(raw)));
  }

  File _artifactFor(ModsYaml yaml, SourceKind target, bool multiple) {
    if (target == SourceKind.modrinth) return _resolvePackPath(yaml: yaml);
    return File(
      p.absolute(
        (argResults!['curseforge-pack'] as String?) ??
            (multiple ? null : argResults!['pack'] as String?) ??
            p.join('build', '${yaml.slug}-${yaml.version}.zip'),
      ),
    );
  }

  /// Reads `--changelog <path>` if provided, else extracts the matching
  /// section from `CHANGELOG.md` in the project directory. Returns null
  /// when neither source yields content.
  String? _resolveChangelog({
    required ModsYaml yaml,
    required Directory projectDir,
  }) {
    final flag = argResults!['changelog'] as String?;
    if (flag != null && flag.isNotEmpty) {
      final file = File(flag);
      if (!file.existsSync()) {
        throw UserError('Changelog not found: $flag');
      }
      return file.readAsStringSync().trim();
    }
    final defaultPath = File(p.join(projectDir.path, 'CHANGELOG.md'));
    return readChangelogSection(
      changelogFile: defaultPath,
      version: yaml.version,
    );
  }

  String _defaultVersionType(String version) {
    final hyphen = version.indexOf('-');
    if (hyphen < 0) return 'release';
    final suffix = version.substring(hyphen + 1).toLowerCase();
    if (suffix.startsWith('alpha')) return 'alpha';
    return 'beta';
  }

  String _joinPath(String baseUrl, String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return path.startsWith('/') ? '$trimmed$path' : '$trimmed/$path';
  }
}
