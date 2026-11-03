import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/exceptions.dart';
import 'cache.dart';

/// Provider/host-scoped raw catalogs. Remote metadata cannot carry recipes.
class LoaderCatalogCache {
  final GitrinthCache cache;
  const LoaderCatalogCache(this.cache);
  String path(String provider, String host) => p.join(
    cache.root,
    'loader-catalogs',
    provider,
    GitrinthCache.hostCacheSegment(host),
    'catalog.json',
  );
  List<Map<String, dynamic>>? read(String provider, String host) {
    final file = File(path(provider, host));
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map ||
          raw['version'] != 1 ||
          raw['provider'] != provider ||
          raw['host'] != host ||
          raw['entries'] is! List) {
        throw const FormatException('catalog envelope mismatch');
      }
      return (raw['entries'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } on Object catch (e) {
      throw ValidationError(
        'Invalid loader catalog ${file.path}: $e. Refresh it online.',
      );
    }
  }

  void write(String provider, String host, List<Map<String, dynamic>> entries) {
    final file = File(path(provider, host));
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    try {
      temp.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'provider': provider,
          'host': host,
          'entries': entries,
        }),
        flush: true,
      );
      temp.renameSync(file.path);
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  }
}
