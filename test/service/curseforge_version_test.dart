import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/model/curseforge/cf_search_response.dart';
import 'package:gitrinth/src/service/curseforge/curseforge_version.dart';
import 'package:test/test.dart';

void main() {
  test(
    'JEI fixture extracts mod version after Minecraft and loader labels',
    () {
      final response = ModFileSearchResponseMapper.fromMap(
        jsonDecode(
              File(
                'test/fixtures/curseforge/mod_files_response.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      expect(curseForgeFileVersion(response.data.first), '19.27.0.340');
      expect(curseForgeFileSatisfies(response.data.first, '^19.0.15'), isTrue);
      expect(curseForgeFileSatisfies(response.data.first, '^1.21.1'), isFalse);
    },
  );
}
