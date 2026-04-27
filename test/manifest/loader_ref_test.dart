import 'package:gitrinth/src/model/manifest/loader_ref.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:test/test.dart';

/// Captures whatever message [parseLoaderRef] passes to its `onError`
/// callback, then throws a `_TestParseError` so the parser stops (its
/// `onError` is typed `Never Function`).
class _TestParseError extends Error {
  final String message;
  _TestParseError(this.message);
  @override
  String toString() => message;
}

LoaderRef _parseOk(String raw) =>
    parseLoaderRef(raw, (msg) => throw _TestParseError(msg));

String _captureError(String raw) {
  try {
    parseLoaderRef(raw, (msg) => throw _TestParseError(msg));
  } on _TestParseError catch (e) {
    return e.message;
  }
  fail('expected onError for input "$raw" but parser returned a ref');
}

void main() {
  group('parseLoaderRef', () {
    test('accepts a bare loader name with no tag', () {
      expect(_parseOk('forge'), (ModLoader.forge, null));
    });

    test('accepts every real loader name', () {
      expect(_parseOk('fabric'), (ModLoader.fabric, null));
      expect(_parseOk('neoforge'), (ModLoader.neoforge, null));
    });

    test('vanilla without a tag returns (vanilla, null)', () {
      expect(_parseOk('vanilla'), (ModLoader.vanilla, null));
    });

    test('preserves the tag verbatim for `latest`', () {
      expect(_parseOk('fabric:latest'), (ModLoader.fabric, 'latest'));
    });

    test('preserves a concrete version tag', () {
      expect(_parseOk('neoforge:21.1.50'), (ModLoader.neoforge, '21.1.50'));
    });

    test('lowercases the loader name but preserves the tag case', () {
      // The shared parser is case-insensitive on the loader name (so the
      // yaml/migrate/create call sites accept any spelling) but treats
      // tags as opaque strings.
      expect(_parseOk('Forge:STABLE'), (ModLoader.forge, 'STABLE'));
    });

    test('rejects vanilla with a tag', () {
      final msg = _captureError('vanilla:1.0');
      expect(msg, contains('vanilla'));
      expect(msg, contains('must not carry a version tag'));
    });

    test('rejects a trailing colon with no tag', () {
      final msg = _captureError('forge:');
      expect(msg, contains('empty version tag'));
    });

    test('rejects a tag containing another colon', () {
      final msg = _captureError('forge:1:2');
      expect(msg, contains('more than one'));
    });

    test('rejects an unknown loader name', () {
      final msg = _captureError('quilt');
      expect(msg, contains('quilt'));
      expect(msg, contains('not a recognized loader'));
    });
  });
}
