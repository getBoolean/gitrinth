import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:mime/mime.dart';

/// One decoded `multipart/form-data` part as the server received it.
class ReceivedPart {
  final String name;
  final String? filename;
  final String? contentType;
  final Uint8List bytes;

  const ReceivedPart({
    required this.name,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  String get text => utf8.decode(bytes);

  Map<String, dynamic> get json => jsonDecode(text) as Map<String, dynamic>;

  /// Decodes the part as a ZIP archive, keyed by entry name.
  Map<String, List<int>> get zipEntries {
    final archive = ZipDecoder().decodeBytes(bytes);
    return {
      for (final file in archive.files)
        if (file.isFile) file.name: file.content as List<int>,
    };
  }
}

/// Parses a real multipart request body, keyed by form field name.
///
/// Fails loudly on a non-multipart request or a duplicated field so a
/// receiver cannot silently accept a malformed upload.
Future<Map<String, ReceivedPart>> readMultipart(HttpRequest request) async {
  final contentType = request.headers.contentType;
  final boundary = contentType?.parameters['boundary'];
  if (contentType?.mimeType != 'multipart/form-data' || boundary == null) {
    throw StateError('Expected multipart/form-data, got $contentType.');
  }
  final parts = <String, ReceivedPart>{};
  await for (final part in MimeMultipartTransformer(boundary).bind(request)) {
    final disposition = HeaderValue.parse(
      part.headers['content-disposition'] ?? '',
      preserveBackslash: true,
    );
    final name = disposition.parameters['name'];
    if (name == null) throw StateError('Multipart part without a name.');
    if (parts.containsKey(name)) {
      throw StateError('Duplicate multipart field "$name".');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in part) {
      builder.add(chunk);
    }
    parts[name] = ReceivedPart(
      name: name,
      filename: disposition.parameters['filename'],
      contentType: part.headers['content-type'],
      bytes: builder.takeBytes(),
    );
  }
  return parts;
}
