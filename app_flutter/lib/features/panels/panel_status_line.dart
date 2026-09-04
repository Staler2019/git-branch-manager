/// Composes P19 rule 6's status-bar text — 「狀態列一律寫實際數量與耗時」.
///
/// Every one of the twelve panels writes the same two clauses (`N <noun>` and,
/// when a filter is narrowing the list, 「命中 K」), so they are composed
/// here rather than hand-copied twelve times. The drift this closes is real
/// and was already under way: three panels had been copied by hand before this
/// function existed, and a single misspelt 命中 in the eleventh copy is
/// invisible to every test that only reads its own panel's string.
///
/// It deliberately does **not** own the widget — [PanelStatusBarText] draws
/// it. This is the sentence, not the bar.
library;

/// Returns the ` · `-joined status line for a panel showing [shown] of [total]
/// items.
///
/// [noun] is the singular; [nounPlural] defaults to `noun + 's'`, which is
/// right for all twelve panels except the ones whose noun needs `-es`
/// (`stash`), so those pass it explicitly. **Zero takes the plural** —
/// 「0 stashes」, not 「0 stash」.
///
/// The 命中 clause appears only when a filter is actually narrowing the list
/// (`shown != total`); an unfiltered panel must not read 「命中 4」 next to
/// 「4 worktrees」, which says the same number twice.
///
/// The two extra slots differ in *what they describe*, which is why they are
/// two parameters rather than one list:
///
/// - [setFacts] is another fact about the same set (「1 個路徑失效」), so it
///   sits beside the total.
/// - [timing] is rule 6's 耗時 — about the *measurement*, not the set — so it
///   goes last, after 命中, which is still a statement about the set.
///
/// Both default to empty, because **only worktrees genuinely times anything**:
/// it runs one `git status` per linked worktree. A panel that runs a single
/// command and measures nothing per row passes no [timing], rather than
/// inventing a duration to satisfy the word 耗時 in the rule.
String panelStatusLine({
  required int total,
  required int shown,
  required String noun,
  String? nounPlural,
  List<String> setFacts = const <String>[],
  List<String> timing = const <String>[],
}) => <String>[
  '$total ${total == 1 ? noun : nounPlural ?? '${noun}s'}',
  ...setFacts,
  if (shown != total) '命中 $shown',
  ...timing,
].join(' · ');
