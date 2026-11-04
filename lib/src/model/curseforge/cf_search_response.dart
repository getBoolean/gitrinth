import 'package:dart_mappable/dart_mappable.dart';

import 'cf_mod.dart';
import 'cf_mod_file.dart';

part 'cf_search_response.mapper.dart';

/// Pagination block returned alongside CurseForge list endpoints.
@MappableClass()
class Pagination with PaginationMappable {
  final int index;
  final int pageSize;
  final int resultCount;
  final int totalCount;

  const Pagination({
    required this.index,
    required this.pageSize,
    required this.resultCount,
    required this.totalCount,
  });
}

/// `{ "data": <Mod> }` — CurseForge wraps every single-resource
/// response in a `data` envelope. Concrete (non-generic) wrappers
/// avoid dart_mappable / retrofit generics complications.
@MappableClass()
class ModEnvelope with ModEnvelopeMappable {
  final Mod data;
  const ModEnvelope({required this.data});
}

/// `{ "data": <ModFile> }`.
@MappableClass()
class ModFileEnvelope with ModFileEnvelopeMappable {
  final ModFile data;
  const ModFileEnvelope({required this.data});
}

/// `{ "data": [<Mod>...], "pagination": ... }` — search-by-slug and
/// search-by-query endpoints.
@MappableClass()
class ModSearchResponse with ModSearchResponseMappable {
  final List<Mod> data;
  final Pagination pagination;

  const ModSearchResponse({required this.data, required this.pagination});
}

/// `{ "data": [<ModFile>...], "pagination": ... }` — `/v1/mods/{id}/files`.
@MappableClass()
class ModFileSearchResponse with ModFileSearchResponseMappable {
  final List<ModFile> data;
  final Pagination pagination;

  const ModFileSearchResponse({required this.data, required this.pagination});
}
