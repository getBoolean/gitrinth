import 'dart:convert';
import 'dart:io';

import 'package:gitrinth/src/model/manifest/mods_lock.dart';
import 'package:gitrinth/src/model/manifest/mods_yaml.dart';
import 'package:gitrinth/src/service/cache.dart';
import 'package:gitrinth/src/service/resolve/lock_graph.dart';
import 'package:gitrinth/src/service/source_identity.dart';
import 'package:gitrinth/src/cli/exceptions.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late GitrinthCache cache;
  const defaultHost = 'https://default.example/v2';
  const hostedHost = 'https://hosted.example:8443/api/v2';
  setUp(() {
    root = Directory.systemTemp.createTempSync('gitrinth_graph_');
    cache = GitrinthCache(root: root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));
  LockedEntry entry(
    String name,
    String project, {
    String? host,
    List<String> parents = const [],
  }) => LockedEntry(
    slug: name,
    kind: LockedEntryKind.resolved,
    modrinth: LockedModrinthSource(
      projectId: project,
      versionId: 'v1',
      host: host,
      file: LockedFile(name: '$name.jar'),
    ),
    requiredBy: parents,
  );
  ModsLock lock(Map<String, LockedEntry> entries) => ModsLock(
    gitrinthVersion: '0.1.0',
    loader: const LoaderConfig(mods: ModLoader.fabric),
    mcVersion: '1.21.1',
    mods: entries,
  );
  void metadata(String host, String project, List<String> children) {
    final file = File(
      cache.modrinthVersionMetadataPath(
        host: host,
        projectId: project,
        versionId: 'v1',
      ),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'dependencies': [
          for (final child in children)
            {'project_id': child, 'dependency_type': 'required'},
        ],
      }),
    );
  }

  test('closure does not follow an identical project ID on another host', () {
    final locked = lock({
      'root-a': entry('root-a', 'root'),
      'child-a': entry('child-a', 'library', parents: ['root-a']),
      'root-b': entry('root-b', 'root', host: hostedHost),
      'child-b': entry(
        'child-b',
        'library',
        host: hostedHost,
        parents: ['root-b'],
      ),
    });
    metadata(defaultHost, 'root', ['library']);
    metadata(hostedHost, 'root', ['library']);
    final closure = walkTransitiveClosure(
      {'root-a'},
      locked,
      cache,
      defaultHost: defaultHost,
    );
    expect(closure, unorderedEquals(['root-a', 'child-a']));
  });

  test(
    'metadata retains multiple local aliases for a project on the same host',
    () {
      final locked = lock({
        'root': entry('root', 'root'),
        'alias-a': entry('alias-a', 'library'),
        'alias-b': entry('alias-b', 'library'),
      });
      metadata(defaultHost, 'root', ['library']);
      final closure = walkTransitiveClosure(
        {'root'},
        locked,
        cache,
        defaultHost: defaultHost,
      );
      expect(closure, unorderedEquals(['root', 'alias-a', 'alias-b']));
    },
  );

  test('parent edges retain cold-cache dependencies and terminate cycles', () {
    final locked = lock({
      'root': entry('root', 'root', parents: ['child']),
      'child': entry('child', 'library', parents: ['root']),
    });
    expect(
      walkTransitiveClosure({'root'}, locked, cache, defaultHost: defaultHost),
      unorderedEquals(['root', 'child']),
    );
  });

  test('section-qualified nodes retain duplicate local names', () {
    final locked = lock({
      'root': entry('root', 'mod-root'),
    }).copyWith(plugins: {'root': entry('root', 'plugin-root')});
    final indexed = LockedDependencyGraph(
      locked,
      cache,
      defaultHost: defaultHost,
    );
    expect(
      indexed.entries.keys,
      unorderedEquals([
        const LocalEntryKey(Section.mods, 'root'),
        const LocalEntryKey(Section.plugins, 'root'),
      ]),
    );
    expect(
      () => walkTransitiveClosure(
        {'root'},
        locked,
        cache,
        defaultHost: defaultHost,
      ),
      throwsA(isA<UserError>()),
    );
  });

  test(
    'a matching child section does not resolve ambiguous parent identity',
    () {
      final locked = lock({
        'root': entry('root', 'mod-root'),
        'child': entry('child', 'child', parents: ['root']),
      }).copyWith(plugins: {'root': entry('root', 'plugin-root')});
      final indexed = LockedDependencyGraph(
        locked,
        cache,
        defaultHost: defaultHost,
      );
      expect(indexed.diagnostics.single, contains('Ambiguous required_by'));
      expect(
        indexed.graph.parents(const LocalEntryKey(Section.mods, 'child')),
        isEmpty,
      );
    },
  );

  test('cold-cache parents match source host before section', () {
    final locked = lock({
      'root': entry('root', 'root-a'),
      'child': entry('child', 'child-b', host: hostedHost, parents: ['root']),
    }).copyWith(plugins: {'root': entry('root', 'root-b', host: hostedHost)});
    final indexed = LockedDependencyGraph(
      locked,
      cache,
      defaultHost: defaultHost,
    );
    expect(indexed.graph.parents(const LocalEntryKey(Section.mods, 'child')), {
      const LocalEntryKey(Section.plugins, 'root'),
    });
  });

  test(
    'ambiguous bare parents are reported and omitted instead of guessed',
    () {
      final locked = lock({'root': entry('root', 'mod-root')}).copyWith(
        plugins: {'root': entry('root', 'plugin-root')},
        dataPacks: {
          'child': entry('child', 'child', parents: ['root']),
        },
      );
      final indexed = LockedDependencyGraph(
        locked,
        cache,
        defaultHost: defaultHost,
      );
      expect(indexed.diagnostics.single, contains('Ambiguous required_by'));
      expect(
        indexed.graph.parents(const LocalEntryKey(Section.dataPacks, 'child')),
        isEmpty,
      );
      expect(
        () => walkTransitiveClosure(
          {'child'},
          locked,
          cache,
          defaultHost: defaultHost,
        ),
        throwsA(isA<UserError>()),
      );
    },
  );
}
