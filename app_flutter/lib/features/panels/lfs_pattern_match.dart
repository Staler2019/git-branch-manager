/// Does [path] match the `.gitattributes` [pattern] an LFS entry was
/// tracked with?
///
/// Spec page 19's `PANELSPEC` row for manage-lfs wants the list grouped by
/// 追蹤型別 with a 檔數 per group, and nothing in `gbm_capi.h` reports which
/// pattern claimed which file — `gbm_lfs_patterns_json` and
/// `gbm_lfs_files_json` are two independent lists. So the grouping is
/// computed here.
///
/// **This is an approximation of gitattributes matching, not a port of it.**
/// It covers the shapes that actually appear in a `.gitattributes`
/// (`*.psd`, `assets/*.png`, `**/*.bin`, `models/`) and deliberately does
/// not implement character classes (`[a-z]`), escapes, or negation — git's
/// own matcher is `wildmatch()` and reimplementing it faithfully to display
/// a count would be far more code than the count is worth. A pattern this
/// cannot parse simply matches nothing, so a group reads 0 rather than
/// claiming a wrong number.
///
/// Semantics implemented, following gitattributes:
/// - a pattern with **no** `/` matches against the file's **base name**
///   (`*.psd` matches `art/logo.psd`);
/// - a pattern with a `/` matches against the whole repository-relative
///   path, anchored at both ends;
/// - a trailing `/` means "everything under this directory";
/// - `*` and `?` do not cross `/`; `**` does.
bool lfsPatternMatches(String path, String pattern) {
  final String trimmed = pattern.trim();
  if (trimmed.isEmpty) return false;

  // A leading slash only anchors the pattern at the repository root, which
  // is where these paths already start.
  String glob = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;

  // "models/" means everything inside it.
  if (glob.endsWith('/')) glob = '$glob**';

  final String subject = glob.contains('/') ? path : path.split('/').last;

  final RegExp? re = _compile(glob);
  return re != null && re.hasMatch(subject);
}

/// Translates a glob to an anchored [RegExp], or null if it uses syntax
/// this deliberately does not support (see the doc above).
RegExp? _compile(String glob) {
  if (glob.contains('[') || glob.contains(']') || glob.startsWith('!')) {
    return null;
  }

  final StringBuffer out = StringBuffer('^');
  for (int i = 0; i < glob.length; i++) {
    final String c = glob[i];
    if (c == '*') {
      final bool isDoubleStar = i + 1 < glob.length && glob[i + 1] == '*';
      if (isDoubleStar) {
        i++;
        // `a/**/b` should also match `a/b`, so swallow the slash that
        // follows a `**` into the optional part.
        if (i + 1 < glob.length && glob[i + 1] == '/') {
          i++;
          out.write('(?:.*/)?');
        } else {
          out.write('.*');
        }
      } else {
        out.write('[^/]*');
      }
    } else if (c == '?') {
      out.write('[^/]');
    } else {
      out.write(RegExp.escape(c));
    }
  }
  out.write(r'$');

  try {
    return RegExp(out.toString());
  } on FormatException {
    return null;
  }
}
