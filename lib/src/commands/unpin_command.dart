import 'dart:io';

import '../cli/base_command.dart';
import '../cli/exceptions.dart';
import '../cli/exit_codes.dart';
import '../model/resolver/constraint.dart';
import '../service/manifest_io.dart';
import 'add_command_editor.dart';
import 'entry_lookup.dart';
import 'pin_editor.dart';

class UnpinCommand extends GitrinthCommand {
  @override
  String get name => 'unpin';

  @override
  String get description =>
      "Restore a caret on a pinned entry's version constraint.";

  @override
  String get invocation => 'gitrinth unpin <slug> [arguments]';

  UnpinCommand() {
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
      throw const UsageError('unpin requires a slug: gitrinth unpin <slug>');
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

    final hit = resolveEntry(
      manifest,
      slug: slug,
      preferredSection: preferredSection,
    );
    final channel = hit.entry.channel;
    if (channel != null && hit.entry.constraintRaw == null) {
      throw UserError(
        "'$slug' constraint is the channel token "
        "'${channel.name}', not a pinned version.",
      );
    }
    final raw = hit.entry.constraintRaw;
    if (raw == null || raw.isEmpty) {
      throw UserError(
        "'$slug' has no version constraint to unpin "
        '(likely a url/path entry).',
      );
    }
    if (raw.startsWith('^')) {
      throw UserError("'$slug' is not pinned (constraint is '$raw').");
    }
    if (parseChannelToken(raw) != null) {
      throw UserError(
        "'$slug' constraint is the channel token '$raw', not a pinned "
        'version.',
      );
    }

    final String caret;
    try {
      caret = '^${bareVersionForPin(raw)}';
    } on FormatException {
      throw UserError(
        "cannot unpin '$slug' — constraint '$raw' is not a semver version.",
      );
    }

    final yamlText = File(io.modsYamlPath).readAsStringSync();
    final updated = updateEntryConstraint(
      yamlText,
      section: hit.section,
      slug: slug,
      newConstraint: caret,
    );

    if (dryRun) {
      console.message("Would unpin '$slug' to $caret.");
      return exitOk;
    }

    io.writeModsYaml(updated);
    console.message("Unpinned '$slug' to $caret.");
    return exitOk;
  }
}
