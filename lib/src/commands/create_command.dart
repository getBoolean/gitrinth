import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../io/templates.dart';
import '../version.dart';

const List<String> _allowedLoaders = ['forge', 'fabric', 'neoforge'];
final RegExp _slugPattern = RegExp(r'^[a-z][a-z0-9_]*$');
final RegExp _mcVersionPattern = RegExp(r'^\d+\.\d+(?:\.\d+)?$');

class CreateCommand extends GitrinthCommand {
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
      ..addOption(
        'slug',
        valueHelp: 'slug',
        help: 'Override the derived slug.',
      )
      ..addOption(
        'name',
        valueHelp: 'name',
        help: 'Override the display name.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Allow scaffolding into a non-empty directory; overwrites existing mods.yaml.',
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

    // TODO(mvp): Modrinth slug validity check via the projectValidity endpoint.
    console.detail(
      'Skipping Modrinth project-validity check (deferred post-MVP).',
    );

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
      _writeFile(targetDir, 'mods.yaml', render(modsYamlTemplate, templateValues)),
      _writeFile(targetDir, 'README.md', render(readmeTemplate, templateValues)),
      _writeFile(targetDir, '.gitignore', render(gitignoreTemplate, templateValues)),
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
    final candidate = override ??
        p.basename(p.normalize(p.absolute(directoryArg)))
            .toLowerCase()
            .replaceAll('-', '_');
    if (!_slugPattern.hasMatch(candidate)) {
      throw ValidationError(
        'Invalid slug "$candidate": must match ${_slugPattern.pattern}. '
        'Pass --slug to override.',
      );
    }
    return candidate;
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
