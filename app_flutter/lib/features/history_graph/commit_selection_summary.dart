import '../../data/models/list_selection.dart';

/// Spec page 13's History status-bar summary for a commit multi-selection.
///
/// P13's 「對既有頁面的連帶修改」 list says of P2 History: 「狀態列改為顯示
/// selection 摘要（數量、是否連續、合計 diff）」, and its 多選的共通規則 block
/// repeats the middle one as a hard rule — 「狀態列一律寫出是否連續」 — because
/// contiguity is exactly what gates cherry-pick / revert in `MULTIACTS`. A
/// user looking at three greyed-out menu items needs somewhere that says why.
///
/// **Reduced deliberately: no 合計 diff.** The spec's own mock reads
/// `4 commits · 連續 · 9 files changed · +311 −54`. Half the original reason
/// is gone: `ChangedFile` now *does* carry added/removed line counts, because
/// `DiffService::changedFiles()` joins `diff-tree --numstat` onto the raw list
/// for spec page 02 item 10's per-file badge (see docs/ledger.md's "Changed
/// files line counts").
///
/// The other half stands, and is why this is still absent. A *total* spans a
/// selection, so it needs the counts for every selected commit, not for the
/// one whose panel is open — that means a `changedFiles()` call per commit on
/// every selection change, each of which now runs two git invocations rather
/// than one. Absent rather than faked, same convention as `MULTIACTS`'
/// `Squash`.
///
/// Returns null below two items rather than `1 commit · contiguous`: a single
/// commit has nothing to be contiguous *with*, so the phrase would be filler,
/// and the status bar's usual repo status (branch, ahead/behind, commit
/// count) is the more useful thing to keep in that space. 「單選是多選的特例」
/// governs the selection *model*, which [ListSelection] already honours; it
/// does not require the summary to narrate a selection of one.
///
/// [allOids] is the **unfiltered** snapshot order, not the rendered rows —
/// the same list `commit_graph_view.dart` judges contiguity against, so a
/// filtered view cannot report three commits as a replayable run when the
/// snapshot has others between them.
String? commitSelectionSummary({
  required ListSelection<String> selection,
  required List<String> allOids,
}) {
  if (selection.length < 2) return null;
  final bool contiguous = selection.isContiguousIn(allOids);
  return '${selection.length} commits · '
      '${contiguous ? 'contiguous' : 'not contiguous'}';
}
