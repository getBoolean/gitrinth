part of '../parser.dart';

/// Parses a `client:` / `server:` value. When [allowOptional] is true
/// (the default — covers mod entries and lock entries), all three of
/// `required`/`optional`/`unsupported` are accepted. When false (covers
/// `files:` entries), `optional` is rejected because Modrinth's
/// `.mrpack` overrides tree has no toggle metadata to round-trip and
/// `gitrinth build` has no UI toggle.
SideEnv _parseSideEnv(
  dynamic raw,
  String where,
  String fieldName,
  String filePath, {
  bool allowOptional = true,
}) {
  switch (raw?.toString()) {
    case 'required':
      return SideEnv.required;
    case 'unsupported':
      return SideEnv.unsupported;
    case 'optional':
      if (allowOptional) return SideEnv.optional;
      throw _err(
        '$filePath: $where $fieldName "optional" is not supported on '
        '`files:` entries. Modrinth\'s .mrpack overrides tree has no '
        'toggle metadata, and `gitrinth build` has no UI toggle, so '
        '`optional` would have no observable effect. Use `required` '
        'or `unsupported`.',
      );
    default:
      if (allowOptional) {
        throw _err(
          '$filePath: $where $fieldName "$raw" must be one of '
          'required, optional, unsupported.',
        );
      }
      throw _err(
        '$filePath: $where $fieldName "$raw" must be `required` or '
        '`unsupported` (`optional` is reserved).',
      );
  }
}
