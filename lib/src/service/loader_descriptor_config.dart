import 'dart:io';

import 'package:yaml/yaml.dart';

import '../cli/exceptions.dart';
import '../model/loader/loader_descriptor.dart';
import '../model/loader/loader_id.dart';
import 'modrinth/modrinth_url.dart';

/// User-owned, declarative mappings. No executable fields are accepted.
class LoaderDescriptorConfig {
  static LoaderRegistry read(String path, {bool required = false}) {
    final file = File(path);
    if (!file.existsSync()) {
      if (required) {
        throw ValidationError('Loader descriptor file not found: $path');
      }
      return LoaderRegistry.builtins;
    }
    try {
      return parse(file.readAsStringSync());
    } on GitrinthException {
      rethrow;
    } on Object catch (e) {
      throw ValidationError('Invalid loader descriptors at $path: $e');
    }
  }

  static LoaderRegistry parse(String yaml) {
    final raw = loadYaml(yaml);
    if (raw is! Map || raw['version'] != 1 || raw['loaders'] is! Map) {
      throw const ValidationError(
        'Loader descriptors require version: 1 and a loaders mapping.',
      );
    }
    _keys(raw, const {'version', 'loaders'});
    final additions = <LoaderDescriptor>[];
    final tags = <String, String>{};
    for (final entry in (raw['loaders'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const ValidationError(
          'Loader descriptors must map names to objects.',
        );
      }
      final id = LoaderId(entry.key as String);
      if (LoaderRegistry.builtins[id] != null) {
        throw ValidationError(
          'Loader ${id.name} cannot shadow a built-in identity or alias.',
        );
      }
      final data = entry.value as Map;
      _keys(data, const {
        'role',
        'modrinth',
        'curseforge_type',
        'curseforge_plugins',
        'archive',
        'version_source',
        'installer_family',
        'compatible_mods',
        'server_launch_jar',
        'server_run_script',
      });
      final role = _enum(LoaderRole.values, data['role'], 'role');
      final mr = <String, String>{};
      final provider = data['modrinth'];
      if (provider != null) {
        if (provider is! Map) {
          throw const ValidationError(
            'modrinth must map provider hosts to tags.',
          );
        }
        for (final mapping in provider.entries) {
          if (mapping.key is! String || mapping.value is! String) {
            throw const ValidationError('Modrinth mappings must be strings.');
          }
          final host = normalizeServerKey(mapping.key as String);
          final tag = LoaderId(mapping.value as String).name;
          final key = '$host/$tag';
          if (tags.containsKey(key) ||
              LoaderRegistry.builtins.descriptors.values.any(
                (d) => d.modrinthTag(host) == tag,
              )) {
            throw ValidationError('Modrinth alias collision for $key.');
          }
          tags[key] = id.name;
          mr[host] = tag;
        }
      }
      final cf = data['curseforge_type'];
      if (cf != null && (cf is! int || cf <= 0)) {
        throw const ValidationError(
          'curseforge_type must be a positive integer.',
        );
      }
      if (cf != null &&
          [
            ...LoaderRegistry.builtins.descriptors.values,
            ...additions,
          ].any((d) => d.curseforgeType == cf)) {
        throw ValidationError(
          'CurseForge type $cf already belongs to another loader.',
        );
      }
      final archive = data['archive'];
      if (archive != null && archive is! Map) {
        throw const ValidationError('archive must be a mapping.');
      }
      final archiveMap = archive as Map? ?? const {};
      _keys(archiveMap, const {'modrinth', 'curseforge'});
      String? token(Object? value) =>
          value == null ? null : LoaderId(value as String).name;
      final compatible = data['compatible_mods'];
      if (compatible != null && compatible is! List) {
        throw const ValidationError('compatible_mods must be a list.');
      }
      final jar = data['server_launch_jar'];
      if (jar != null &&
          (jar is! String ||
              !RegExp(r'^[a-zA-Z0-9_.-]+\.jar$').hasMatch(jar))) {
        throw const ValidationError(
          'server_launch_jar must be a plain JAR filename.',
        );
      }
      for (final key in ['curseforge_plugins', 'server_run_script']) {
        if (data[key] != null && data[key] is! bool) {
          throw ValidationError('$key must be boolean.');
        }
      }
      additions.add(
        LoaderDescriptor(
          id: id,
          role: role,
          modrinthTags: mr,
          curseforgeType: cf as int?,
          curseforgePlugins: data['curseforge_plugins'] == true,
          modrinthArchiveKey: token(archiveMap['modrinth']),
          curseforgeArchiveToken: token(archiveMap['curseforge']),
          versionSource: data['version_source'] == null
              ? VersionSourceFamily.catalog
              : _enum(
                  VersionSourceFamily.values,
                  data['version_source'],
                  'version_source',
                ),
          installer: data['installer_family'] == null
              ? null
              : _enum(
                  InstallerFamily.values,
                  data['installer_family'],
                  'installer_family',
                ),
          compatibleMods: [
            for (final value in compatible as List? ?? [])
              LoaderId(value as String),
          ],
          serverLaunchJar: jar as String?,
          serverRunScript: data['server_run_script'] == true,
        ),
      );
    }
    return LoaderRegistry.builtins.merge(additions);
  }

  static T _enum<T extends Enum>(List<T> values, Object? raw, String key) {
    final found = values.where((value) => value.name == raw).firstOrNull;
    if (found == null) {
      throw ValidationError(
        'Unknown $key "$raw"; use ${values.map((v) => v.name).join(', ')}.',
      );
    }
    return found;
  }

  static void _keys(Map data, Set<String> allowed) {
    for (final key in data.keys) {
      if (!allowed.contains(key)) {
        throw ValidationError('Unknown loader descriptor key "$key".');
      }
    }
  }
}
