/// The sidebar filter's matching rule, spec P02-14.
///
/// Extracted into its own file rather than left inline in
/// `branch_tree_builder.dart` because P02-14 applies the *same* rule to all
/// three sections -- Branches, Tags and Stash -- and `sidebar_panel.dart`
/// filters stashes with its own inline `contains`. One rule written twice is
/// how two rules start; same reasoning as `branchNameError()`'s extraction
/// out of `new_branch_dialog.dart`.
library;

/// Whether [name] should survive the filter [query].
///
/// Two rules, in order:
///
/// 1. **Case-insensitive substring**, which is what spec names first and
///    what the code has always done.
/// 2. **Consecutive word initials**, which is what 「斜線視為分隔（打 `gl`
///    可命中 `feature/graph-lanes`）」 asks for and what was missing --
///    `'feature/graph-lanes'.contains('gl')` is false, so spec's own worked
///    example did not match.
///
/// A word starts at the first character and after any of `/ - _ . space`, or
/// at a lower-to-upper transition (`graphLanes`). Spec names only the slash;
/// it has to be more than the slash, because the `l` in the example comes
/// from *lanes* -- splitting on `/` alone yields the initials `fg`.
///
/// Rule 2 is a **substring** over those initials, not a subsequence: `fgl`,
/// `fg` and `gl` all match `feature/graph-lanes` while `fl` does not. Both
/// readings satisfy spec's single example, and this is the narrower one. See
/// `branch_filter_test.dart`'s 'initials must be consecutive' for the
/// one-line change if a revision ever asks for fuzzy matching.
bool matchesBranchFilter(String name, String query) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;

  final String haystack = name.toLowerCase();
  if (haystack.contains(needle)) return true;

  return initialsOf(name).contains(needle);
}

/// The lower-cased first letter of each word in [name], in order --
/// `feature/graph-lanes` gives `fgl`.
///
/// Exposed (rather than private) so a caller wanting to *explain* a match
/// can show the same string the rule matched against.
String initialsOf(String name) {
  final StringBuffer initials = StringBuffer();
  bool atWordStart = true;

  for (int i = 0; i < name.length; i++) {
    final String char = name[i];
    if (_isSeparator(char)) {
      atWordStart = true;
      continue;
    }
    // A capital following a lower-case letter opens a word without any
    // separator: `graphLanes` is two words, `GL` and `RC1` are not.
    final bool camelBoundary = i > 0 && _isUpper(char) && _isLower(name[i - 1]);
    if (atWordStart || camelBoundary) {
      initials.write(char.toLowerCase());
    }
    atWordStart = false;
  }

  return initials.toString();
}

bool _isSeparator(String char) =>
    char == '/' || char == '-' || char == '_' || char == '.' || char == ' ';

bool _isUpper(String char) {
  final String lower = char.toLowerCase();
  return lower != char && char.toUpperCase() == char;
}

bool _isLower(String char) {
  final String upper = char.toUpperCase();
  return upper != char && char.toLowerCase() == char;
}
