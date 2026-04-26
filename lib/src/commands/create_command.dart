import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/templates.dart';
import '../version.dart';

const List<String> _allowedLoaders = ['forge', 'fabric', 'neoforge'];

/// Mirrors Modrinth's project-creation rule (`RE_URL_SAFE` + `length(3, 64)`)
/// so any slug accepted locally is also accepted by Modrinth's project-create
/// endpoint.
final RegExp _slugPattern = RegExp(r'^[a-zA-Z0-9!@$()`.+,_"\-]{3,64}$');
final RegExp _mcVersionPattern = RegExp(r'^\d+\.\d+(?:\.\d+)?$');

class CreateCommand extends GitrinthCommand with OfflineFlag {
  @override
  String get name => 'create';

  @override
  String get description =>
      'Scaffold a new modpack directory with a minimal mods.yaml.';

  @override
  String get invocation => 'gitrinth create [arguments] <directory>';

  CreateCommand() {
    argParser
      ..addOption(
        'loader',
        allowed: _allowedLoaders,
        valueHelp: 'loader',
        help: 'Pre-fill loader. Defaults to $defaultLoader.',
      )
      ..addOption(
        'mc-version',
        valueHelp: 'version',
        help: 'Pre-fill mc-version. Defaults to $defaultMcVersion.',
      )
      ..addOption('slug', valueHelp: 'slug', help: 'Override the derived slug.')
      ..addOption('name', valueHelp: 'name', help: 'Override the display name.')
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Allow scaffolding into a non-empty directory; overwrites existing mods.yaml.',
      );
    addOfflineFlag(
      helpOverride: 'Skip the Modrinth slug-availability check.',
    );
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final rest = results.rest;
    if (rest.isEmpty) {
      throw const UsageError('create requires a target <directory>.');
    }
    if (rest.length > 1) {
      throw UsageError(
        'Unexpected arguments after <directory>: ${rest.skip(1).join(' ')}',
      );
    }
    final directoryArg = rest.first;

    final slug = _resolveSlug(results['slug'] as String?, directoryArg);
    final packName = (results['name'] as String?) ?? slug;
    final loader = (results['loader'] as String?) ?? defaultLoader;
    final mcVersion = _resolveMcVersion(results['mc-version'] as String?);

    final offline = readOfflineFlag();
    if (offline) {
      console.io('Skipping Modrinth slug-availability check (--offline).');
    } else {
      await _warnIfSlugTaken(slug);
    }

    final targetDir = Directory(directoryArg);
    final force = results['force'] as bool;
    _ensureTargetWritable(targetDir, force: force);
    targetDir.createSync(recursive: true);

    final templateValues = <String, String>{
      'slug': slug,
      'name': packName,
      'version': '0.1.0',
      'description': 'A new Modrinth modpack.',
      'loader': loader,
      'mc-version': mcVersion,
      'gitrinth-version': packageVersion,
      'gitrinth-next-major': nextMajor(packageVersion),
    };

    final written = <String>[
      _writeFile(
        targetDir,
        'mods.yaml',
        render(modsYamlTemplate, templateValues),
      ),
      _writeFile(
        targetDir,
        'README.md',
        render(readmeTemplate, templateValues),
      ),
      _writeFile(
        targetDir,
        '.gitignore',
        render(gitignoreTemplate, templateValues),
      ),
      _writeFile(
        targetDir,
        '.modrinth_ignore',
        render(modrinthIgnoreTemplate, templateValues),
      ),
    ];

    stdout.writeln('Created $slug in ${targetDir.path}');
    for (final path in written) {
      stdout.writeln('  + $path');
    }

    return exitOk;
  }

  String _resolveSlug(String? override, String directoryArg) {
    final candidate =
        override ??
        p.basename(p.normalize(p.absolute(directoryArg))).toLowerCase();
    if (!_slugPattern.hasMatch(candidate)) {
      throw ValidationError(
        'Invalid slug "$candidate": must be 3-64 characters from '
        r'[a-zA-Z0-9!@$()`.+,_"-]. Pass --slug to override.',
      );
    }
    return candidate;
  }

  /// Hits Modrinth's `/project/<slug>/check` endpoint and emits a warning if
  /// a project with this slug already exists. Network failures are
  /// non-fatal — they degrade to a warning so offline scaffolding still works.
  Future<void> _warnIfSlugTaken(String slug) async {
    final api = read(modrinthApiProvider);
    try {
      final resp = await api.checkProjectValidity(slug);
      final status = resp.response.statusCode;
      if (status != null && status >= 200 && status < 300) {
        console.warn(
          'Slug "$slug" is already taken on Modrinth. You can still scaffold '
          'and rename later, or rerun with --slug.',
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return;
      console.warn(
        'Could not validate slug "$slug" against Modrinth '
        '(${e.message ?? e.type.name}). Proceeding without check.',
      );
    }
  }

  String _resolveMcVersion(String? override) {
    if (override == null) return defaultMcVersion;
    if (!_mcVersionPattern.hasMatch(override)) {
      throw ValidationError(
        'Invalid --mc-version "$override": expected e.g. "1.21.1".',
      );
    }
    return override;
  }

  void _ensureTargetWritable(Directory dir, {required bool force}) {
    if (!dir.existsSync()) return;
    final entries = dir.listSync();
    if (entries.isEmpty) return;
    if (!force) {
      throw UserError(
        'Refusing to scaffold into non-empty directory "${dir.path}"; '
        'pass --force to overwrite.',
      );
    }
  }

  String _writeFile(Directory dir, String name, String contents) {
    final file = File(p.join(dir.path, name));
    file.writeAsStringSync(contents);
    return p.join(dir.path, name);
  }
}
