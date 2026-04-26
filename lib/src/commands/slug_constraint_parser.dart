import '../service/modrinth_project_url.dart';

/// Parses an `add`/`override` positional of the form
/// `<slug>[@<constraint>]`, accepting full Modrinth project URLs in
/// place of bare slugs.
///
/// Returns the slug + the optional constraint string. Constraint
/// validation (parseConstraint / parseChannelToken) is left to the
/// caller because failure messages differ between commands.
({String slug, String? constraintRaw}) parseSlugConstraint(String input) {
  final atIndex = input.lastIndexOf('@');
  String prefix;
  String? maybeConstraint;
  if (atIndex <= 0 || atIndex == input.length - 1) {
    prefix = input;
    maybeConstraint = null;
  } else {
    prefix = input.substring(0, atIndex);
    maybeConstraint = input.substring(atIndex + 1);
  }

  final urlRef = parseModrinthProjectUrl(prefix);
  if (urlRef != null) {
    return (slug: urlRef.slug, constraintRaw: maybeConstraint);
  }

  // Not a URL — maybe `@` was actually part of the URL? Try the whole
  // input once more to catch `modrinth.com/mod/foo@bar` shapes.
  final urlRefFull = parseModrinthProjectUrl(input);
  if (urlRefFull != null) {
    return (slug: urlRefFull.slug, constraintRaw: null);
  }

  return (slug: prefix, constraintRaw: maybeConstraint);
}
