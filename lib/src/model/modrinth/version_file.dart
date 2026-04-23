import 'package:dart_mappable/dart_mappable.dart';

part 'version_file.mapper.dart';

@MappableClass()
class VersionFile with VersionFileMappable {
  final String url;
  final String filename;
  final Map<String, String> hashes;
  final int size;
  final bool primary;

  const VersionFile({
    required this.url,
    required this.filename,
    required this.hashes,
    required this.size,
    required this.primary,
  });

  String? get sha512 => hashes['sha512'];
}
