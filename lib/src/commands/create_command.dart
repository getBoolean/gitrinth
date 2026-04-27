import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../app/providers.dart';
import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../cli/offline_flag.dart';
import '../model/manifest/loader_ref.dart';
import '../model/manifest/mods_yaml.dart';
import '../model/templates.dart';
import '../version.dart';

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
        valueHelp: 'loader[:tag]',
        help:
            'Pre-fill loader. One of ${loaderRefNames.join(', ')}, '
            'optionally with a docker-style version tag '
            '(e.g. `neoforge:21.1.50`, `fabric:latest`). Defaults to '
            '$defaultLoader.',
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
    addOfflineFlag(helpOverride: 'Skip the Modrinth slug-availability check.');
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final directoryArg = parseSinglePositional(name: '<directory>');

    final slug = _resolveSlug(results['slug'] as String?, directoryArg);
    final packName = (results['name'] as String?) ?? slug;
    final loader = _resolveLoader(results['loader'] as String?);
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

    // The template inserts `{{loader}}` directly after `mods: ` in
    // mods.yaml. A tagged form like `neoforge:21.1.50` contains a
    // colon, so YAML would otherwise misread it as a nested mapping —
    // quote it for the yaml render. The README receives the bare form
    // so the bullet point stays unquoted.
    final loaderName = loader.split(':').first;
    final loaderForYaml = loader.contains(':') ? '"$loader"' : loader;

    final commonTemplateValues = <String, String>{
      'slug': slug,
      'name': packName,
      'version': '0.1.0',
      'description': 'A new Modrinth modpack.',
      'mc-version': mcVersion,
      'gitrinth-version': packageVersion,
      'gitrinth-next-major': nextMajor(packageVersion),
    };
    final yamlTemplateValues = {
      ...commonTemplateValues,
      'loader': loaderForYaml,
    };
    final readmeTemplateValues = {
      ...commonTemplateValues,
      'loader': loaderName,
    };

    final renderedModsYaml = (loader == 'vanilla')
        ? _stripSeededModsForVanilla(
            render(modsYamlTemplate, yamlTemplateValues),
          )
        : render(modsYamlTemplate, yamlTemplateValues);

    final written = <String>[
      _writeFile(targetDir, 'mods.yaml', renderedModsYaml),
      _writeFile(
        targetDir,
        'README.md',
        render(readmeTemplate, readmeTemplateValues),
      ),
      _writeFile(
        targetDir,
        '.gitignore',
        render(gitignoreTemplate, readmeTemplateValues),
      ),
      _writeFile(
        targetDir,
        '.modrinth_ignore',
        render(modrinthIgnoreTemplate, readmeTemplateValues),
      ),
    ];

    console.message('Created $slug in ${targetDir.path}');
    for (final path in written) {
      console.message('  + $path');
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

  /// Validates the `--loader` flag via the shared [parseLoaderRef]
  /// helper and renders the value to inject into the scaffolded
  /// `mods.yaml`. Re-emits the docker-style form so a tag the user
  /// supplied survives round-trip.
  String _resolveLoader(String? raw) {
    if (raw == null) return defaultLoader;
    final (loader, tag) = parseLoaderRef(
      raw,
      (msg) => throw ValidationError('--loader $msg'),
    );
    if (loader == ModLoader.vanilla) return 'vanilla';
    return tag == null ? loader.name : '${loader.name}:$tag';
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

/// Strips the seeded `mods:` entries from the rendered template when
/// the scaffolded pack has no mod runtime. The default template seeds
/// `globalpacks: stable` under `mods:` so a freshly-created pack picks
/// up the standard helper resource pack collection; under
/// `loader.mods: vanilla`, any `mods:` entry is a parse error
/// (declared mods need a real loader), so the seed must be dropped.
///
/// Uses `yaml_edit` to remove children of `mods:` regardless of how
/// they're formatted (any indentation, future commented-out entries,
/// nested long-form blocks). yaml_edit leaves an explicit `{}`
/// placeholder beneath the header after the last child is removed; we
/// strip that placeholder so the result is a bare `mods:` header.
String _stripSeededModsForVanilla(String rendered) {
  final editor = YamlEditor(rendered);
  final root = editor.parseAt(<Object>[]);
  if (root is! YamlMap) return rendered;
  final mods = root.nodes['mods'];
  if (mods is! YamlMap) return rendered;
  for (final key in mods.keys.toList()) {
    editor.remove(['mods', key.toString()]);
  }
  // Drop the `  {}` placeholder yaml_edit emits for an emptied block
  // map, scoped to the `mods:` header so other empty sections in the
  // template are left untouched.
  return editor.toString().replaceAllMapped(
    RegExp(
      r'^(mods:)[ \t]*(\r?\n)[ \t]+\{\}[ \t]*(?=\r?\n|$)',
      multiLine: true,
    ),
    (m) => '${m[1]}${m[2]}',
  );
}
