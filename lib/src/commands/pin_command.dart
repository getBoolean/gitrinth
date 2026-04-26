import 'dart:io';

import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/manifest/mods_lock.dart';
import '../model/resolver/constraint.dart';
import '../service/manifest_io.dart';
import 'add_command_editor.dart';
import 'entry_lookup.dart';
import 'pin_editor.dart';

class PinCommand extends GitrinthCommand {
  @override
  String get name => 'pin';

  @override
  String get description =>
      "Freeze an entry's version constraint to the currently-locked version.";

  @override
  String get invocation => 'gitrinth pin <slug> [arguments]';

  PinCommand() {
    argParser
      ..addOption(
        'type',
        allowed: typeFlagValues,
        help:
            'Disambiguate <slug> when it exists in multiple sections of '
            'mods.yaml.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: "Report what entries would change but don't change any.",
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw const UsageError('pin requires a slug: gitrinth pin <slug>');
    }
    if (rest.length > 1) {
      throw UsageError(
        'Unexpected arguments after slug: ${rest.skip(1).join(' ')}',
      );
    }
    final slug = rest.first;
    final preferredSection = sectionFromTypeFlag(
      argResults!['type'] as String?,
    );
    final dryRun = argResults!['dry-run'] as bool;

    final io = ManifestIo();
    final manifest = io.readModsYaml();
    final lock = io.readModsLock();
    if (lock == null) {
      throw const UserError(
        'mods.lock not found; run `gitrinth get` first to establish a '
        'baseline lock.',
      );
    }

    final hit = resolveEntry(
      manifest,
      slug: slug,
      preferredSection: preferredSection,
    );
    final locked = lock.sectionFor(hit.section)[slug];
    if (locked == null) {
      throw UserError(
        "no lock entry for '$slug' in section '${sectionKeyFor(hit.section)}' "
        '— run `gitrinth get`.',
      );
    }
    if (locked.sourceKind != LockedSourceKind.modrinth) {
      throw UserError(
        "'$slug' is a ${locked.sourceKind.name} source; only Modrinth "
        'entries can be pinned.',
      );
    }
    final rawVersion = locked.version;
    if (rawVersion == null || rawVersion.isEmpty) {
      throw UserError(
        "lock entry for '$slug' has no version — re-run `gitrinth get`.",
      );
    }

    final String bare;
    try {
      bare = bareVersionForPin(rawVersion);
    } on FormatException {
      throw ValidationError(
        "cannot pin '$slug' — locked version '$rawVersion' does not parse "
        'as semver. Edit mods.yaml manually.',
      );
    }

    final yamlText = File(io.modsYamlPath).readAsStringSync();
    final updated = updateEntryConstraint(
      yamlText,
      section: hit.section,
      slug: slug,
      newConstraint: bare,
    );

    if (dryRun) {
      console.message("Would pin '$slug' to $bare.");
      return exitOk;
    }

    io.writeModsYaml(updated);
    console.message("Pinned '$slug' to $bare.");
    return exitOk;
  }
}
