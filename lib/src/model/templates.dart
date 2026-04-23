export '../asset_strings.g.dart';

// Hardcoded defaults for `gitrinth create`. Update here to change what the
// scaffolded mods.yaml and README target.
const String defaultLoader = 'neoforge';
const String defaultMcVersion = '1.21.1';

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
