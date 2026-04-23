// TODO(post-mvp): generate from assets/template/ via build_runner so the
// on-disk files are the single source of truth. Until then, these strings
// mirror assets/template/*; a test in test/templates_drift_test.dart fails
// CI if they drift.

// Hardcoded defaults for `gitrinth create`. Update here to change what the
// scaffolded mods.yaml and README target.
const String defaultLoader = 'neoforge';
const String defaultMcVersion = '1.21.1';

const String modsYamlTemplate = '''
slug: {{slug}}
name: {{name}}
version: {{version}}
description: {{description}}

loader: {{loader}}
mc-version: {{mc-version}}

tooling:
  gitrinth: ">={{gitrinth-version}} <{{gitrinth-next-major}}"

mods:

resource_packs:

data_packs:

shaders:

plugins:
''';

const String readmeTemplate = '''
# {{name}}

{{description}}

## Requirements

- Minecraft {{mc-version}}
- {{loader}}
''';

const String gitignoreTemplate = '''
# Created by `gitrinth create`
.gitrinth_tool/
build/
*.mrpack
''';

const String modrinthIgnoreTemplate = '''
# .modrinth_ignore'd files are excluded from publishing.
# Follows .gitignore syntax.
.gitrinth_tool/
build/
*.mrpack
''';

String render(String template, Map<String, String> values) {
  var out = template;
  values.forEach((key, value) {
    out = out.replaceAll('{{$key}}', value);
  });
  return out;
}

String nextMajor(String semver) {
  final core = semver.split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  if (parts.isEmpty) return '$semver.next';
  final major = int.tryParse(parts.first) ?? 0;
  return '${major + 1}.0.0';
}
