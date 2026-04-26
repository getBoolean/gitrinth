/// Replaces `{key}` placeholders in [template] with the corresponding entries
/// in [values]. Keys without surrounding braces in [values] are wrapped at
/// substitution time.
String fillUrlTemplate(String template, Map<String, String> values) {
  var result = template;
  for (final entry in values.entries) {
    result = result.replaceAll('{${entry.key}}', entry.value);
  }
  return result;
}
