import 'package:dart_mappable/dart_mappable.dart';

part 'cf_file_hash.mapper.dart';

/// Algorithm used for a [FileHash]. CurseForge encodes the algorithm as
/// an integer code on the wire (1=sha1, 2=md5); [FileHash.algo] decodes
/// it. Unknown codes fall through to [HashAlgo.unknown] to keep parsing
/// forward-compatible.
@MappableEnum()
enum HashAlgo { sha1, md5, unknown }

/// One entry in CurseForge's `ModFile.hashes` list.
@MappableClass()
class FileHash with FileHashMappable {
  final String value;

  /// Raw `algo` integer from the API. Use [algo] for the decoded enum.
  @MappableField(key: 'algo')
  final int algoCode;

  const FileHash({required this.value, required this.algoCode});

  HashAlgo get algo => switch (algoCode) {
    1 => HashAlgo.sha1,
    2 => HashAlgo.md5,
    _ => HashAlgo.unknown,
  };
}
