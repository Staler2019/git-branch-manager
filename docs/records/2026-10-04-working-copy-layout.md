# Working Copy (spec P03): no checkbox, stacked lists on the left, unified by default

- **Kind**: ruling · **Pins**: was `STRUCT-working-copy` · **Code**: `working_copy_board.dart`, `splitterWcStack`/`splitterWcFiles` (`tokens.dart`), `working_copy_diff_pane.dart`

## Situation
P03-1 / P03-3 / P03-10 and `SCOPES` rows 1/4/5 each specify a checkbox. Spec page 09's `SPLITTERS` has `wc.columns` `dir: '垂直'` and `wc.diff` `dir: '水平'` — two file lists side by side, left nothing readable for the file *content*, which is what the page is for.

## Task
Three user rulings, each a stated deviation from the spec, that a later reader could "fix back".

## Action
- **No checkbox anywhere** — not on a row, a column header, or a tree-mode folder row. Files move side by **dragging** (a folder row is draggable and takes its subtree); a whole column goes through `Repository → Stage all` (`Ctrl/Cmd+Alt+A`) or the context menu; half-staged is expressed by `+34 −12` line counts. Reasoning and what replaced each removed affordance: ledger 「Working Copy 重新設計」.
- **Stacked, on the left** (使用者裁定, feat/working-copy-vertical-file-lists): Unstaged above Staged (`splitterWcStack`, vertical, 1:1, min 96) inside a fixed-width left column (`splitterWcFiles`, extent 260 / min 180), diff filling the right. Both `SPLITTERS` rows are overruled, not renamed (`dir` is the divider's own direction). New storage keys `wc.stack`, `wc.files` per [FLU-splitpane-axis-change]. The commit box stays full-width along the bottom, outside the splitter. Drop hint 「拖曳檔案到下欄 = stage」 — 「右欄」 would name a column that is not there.
- **Diff area: `2 file` and `unified`, `unified` the default** (same round). ~~`unified` stacks the two sides in one column~~ — that shipped and was 「還是拆成上下檢視」; it is **one list**, cards ordered by index region (`indexPositionOf`), title bar 「N 未暫存 · M 已暫存」, each card carrying its own direction — 使用者裁定 U1–U8. `2 file` is untouched except the Unstage button's `border-strong` ring, 使用者裁定 「這是唯一會影響到 2file 的」.
- Staging is by **scope**: `diff_scopes.dart` merges changes ≤ `kDefaultScopeGap` (2) unchanged lines apart, never crossing a hunk nor, in the merged list, an unchanged line the other side changes ([record: merged diff region order](2026-10-04-merged-diff-region-order.md)); the title bar counts split by the same barriers. A text selection is a one-shot temporary scope **nested inside the cards it covers** (~~a fixed slot at the top of the column~~ — shipped, pointed at, and the demo's DOM nests `.variant-B-temp` inside `.variant-B-card`). Button text is `scopeButtonLabel()`'s only: 匡選行數 primary, 實際變動行數 in parentheses (`Stage 3 lines (1 changed)`), omitted when equal — ~~implementation judgement~~ 使用者裁定, 照建議 on §06 question 7.
- `DiffPage` is read-only; the Working Copy's diff is `ScopedDiffView`. Selecting a file selects the same logical file in both columns, renames included (`logicalFileKey`).

## Result
Pinned by `working_copy_board_test.dart` (「no checkbox anywhere」), `gbm_layout_test.dart` (`wc.files` 260/180 extent, `wc.stack` 1:1 min 96), `working_copy_diff_pane_test.dart` (「unified opens by default」). Evidence: [ledger: Working Copy 檔案清單改成左側垂直](../ledger/2026-09-05-feat-working-copy-vertical-file-lists.md), [ledger: unified 合成單一清單](../ledger/2026-09-05-fix-working-copy-unified-single-view.md).
