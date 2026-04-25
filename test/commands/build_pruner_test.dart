import 'dart:io';

import 'package:gitrinth/src/commands/build_assembler.dart';
import 'package:gitrinth/src/commands/build_pruner.dart';
import 'package:gitrinth/src/model/state/build_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('build_pruner ledger I/O', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gitrinth_pruner_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('readLedgerOrEmpty returns empty when ledger is missing', () {
      final l = readLedgerOrEmpty(
        p.join(tmp.path, '.gitrinth-state.yaml'),
        BuildEnv.client,
      );
      expect(l.files, isEmpty);
      expect(l.env, LedgerEnv.client);
    });

    test('readLedgerOrEmpty tolerates malformed YAML', () {
      final path = p.join(tmp.path, '.gitrinth-state.yaml');
      File(path).writeAsStringSync(': : not valid : :');
      final l = readLedgerOrEmpty(path, BuildEnv.server);
      expect(l.files, isEmpty);
      expect(l.env, LedgerEnv.server);
    });

    test('writeLedger -> readLedgerOrEmpty round-trips both source kinds', () {
      final ledger = BuildLedger(
        gitrinthVersion: '0.2.0',
        env: LedgerEnv.client,
        generatedAt: '2026-04-25T12:00:00.000Z',
        files: const {
          'mods/sodium-0.5.8.jar': LedgerModSource(
            section: 'mods',
            slug: 'sodium',
            sha512: 'AABBCC',
          ),
          'config/sodium-options.json': LedgerFileSource(
            key: 'config/sodium-options.json',
            preserve: true,
            sourcePath: './presets/sodium-options.json',
          ),
        },
      );
      final path = p.join(tmp.path, '.gitrinth-state.yaml');
      writeLedger(path, ledger);

      final text = File(path).readAsStringSync();
      expect(text, contains('gitrinth-version: 0.2.0'));
      expect(text, contains('env: client'));
      expect(text, contains('  mods/sodium-0.5.8.jar:'));
      expect(text, contains('    kind: mod-entry'));
      expect(text, contains('    section: mods'));
      expect(text, contains('    sha512: aabbcc')); // lower-cased
      expect(text, contains('    kind: file-entry'));
      expect(text, contains('    preserve: true'));

      final parsed = readLedgerOrEmpty(path, BuildEnv.client);
      expect(parsed.gitrinthVersion, '0.2.0');
      expect(parsed.env, LedgerEnv.client);
      expect(parsed.generatedAt, '2026-04-25T12:00:00.000Z');
      expect(parsed.files.length, 2);

      final mod = parsed.files['mods/sodium-0.5.8.jar']! as LedgerModSource;
      expect(mod.section, 'mods');
      expect(mod.slug, 'sodium');
      expect(mod.sha512, 'aabbcc');

      final cfg =
          parsed.files['config/sodium-options.json']! as LedgerFileSource;
      expect(cfg.key, 'config/sodium-options.json');
      expect(cfg.preserve, isTrue);
      expect(cfg.sourcePath, './presets/sodium-options.json');
    });

    test('writeLedger emits empty mapping for an empty ledger', () {
      final path = p.join(tmp.path, '.gitrinth-state.yaml');
      writeLedger(
        path,
        BuildLedger(
          gitrinthVersion: '0.1.0',
          env: LedgerEnv.client,
          generatedAt: 'now',
        ),
      );
      final text = File(path).readAsStringSync();
      expect(text, contains('files: {}'));
    });
  });

  group('obsoletePaths', () {
    test('returns prior keys missing from desired', () {
      const prior = BuildLedger(
        gitrinthVersion: '0.1.0',
        env: LedgerEnv.client,
        generatedAt: 'now',
        files: {
          'mods/old.jar': LedgerModSource(section: 'mods', slug: 'old'),
          'mods/keep.jar': LedgerModSource(section: 'mods', slug: 'keep'),
        },
      );
      final obsolete = obsoletePaths(
        prior: prior,
        desired: {'mods/keep.jar'},
      );
      expect(obsolete, {'mods/old.jar'});
    });

    test('filters out protected paths', () {
      const prior = BuildLedger(
        gitrinthVersion: '0.1.0',
        env: LedgerEnv.client,
        generatedAt: 'now',
        files: {
          '.gitrinth-state.yaml': LedgerFileSource(
            key: '.gitrinth-state.yaml',
            preserve: false,
            sourcePath: 'irrelevant',
          ),
          '.gitrinth-installed-forge-47.3.0': LedgerFileSource(
            key: '.gitrinth-installed-forge-47.3.0',
            preserve: false,
            sourcePath: 'irrelevant',
          ),
          'mods/dropped.jar': LedgerModSource(
            section: 'mods',
            slug: 'dropped',
          ),
        },
      );
      final obsolete = obsoletePaths(prior: prior, desired: const {});
      expect(obsolete, {'mods/dropped.jar'});
    });

    test('returns empty when prior is empty', () {
      const prior = BuildLedger(
        gitrinthVersion: '0.1.0',
        env: LedgerEnv.client,
        generatedAt: 'now',
      );
      expect(obsoletePaths(prior: prior, desired: const {'a', 'b'}), isEmpty);
    });
  });

  group('pruneFile', () {
    late Directory envRoot;
    setUp(() {
      envRoot = Directory.systemTemp.createTempSync('gitrinth_prunefile_');
    });
    tearDown(() {
      if (envRoot.existsSync()) envRoot.deleteSync(recursive: true);
    });

    test('deletes the file and prunes empty parents up to envRoot', () {
      final dest = File(p.join(envRoot.path, 'mods', 'old.jar'));
      dest.parent.createSync(recursive: true);
      dest.writeAsStringSync('jar');
      pruneFile(envRoot: envRoot, relPath: 'mods/old.jar');
      expect(dest.existsSync(), isFalse);
      expect(Directory(p.join(envRoot.path, 'mods')).existsSync(), isFalse);
      expect(envRoot.existsSync(), isTrue, reason: 'envRoot itself preserved');
    });

    test('leaves non-empty parents alone after pruning', () {
      File(p.join(envRoot.path, 'mods', 'a.jar'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('a');
      File(p.join(envRoot.path, 'mods', 'b.jar')).writeAsStringSync('b');
      pruneFile(envRoot: envRoot, relPath: 'mods/a.jar');
      expect(File(p.join(envRoot.path, 'mods', 'b.jar')).existsSync(), isTrue);
      expect(Directory(p.join(envRoot.path, 'mods')).existsSync(), isTrue);
    });

    test('no-op for missing file', () {
      // Should not throw.
      pruneFile(envRoot: envRoot, relPath: 'mods/never-existed.jar');
    });
  });
}
