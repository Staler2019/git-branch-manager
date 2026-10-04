# The merged (unified) diff list orders by index region, splits at the other side's changes, and hides the row the other side draws

- **Kind**: ruling · **Pins**: was `FLU-merged-diff-keys-by-source`, `FLU-index-position-is-two-part`, `FLU-other-side-changes-are-barriers` · **Code**: `ScopedDiffView` (`_orderedBlocks`, `_rowsInRenderOrder`), `diff_scopes.dart` (`indexPositionOf`, `compareIndexPositions`, `splitHunkIntoScopes`, `changedIndexLines`, `barrierLineIndices`, `DiffBarrierMemo`)

## Situation
`unified` mode draws the unstaged and staged diffs of one file as one list. The two diffs carry the *same* hunk and line numbers, and an untracked file numbers its added lines only on the worktree side. The reported case: an untracked file whose middle line is staged — the unstaged side reads `+ + . + +`, and git's three regions were drawn as **two** cards.

## Task
Decide what the merged list is ordered by and where its scopes may split, so that direction (stage vs unstage) can never be confused.

## Action
- **Order by region, not line** — 使用者裁定 U1: 「我要對齊的不是行號，是 git 判斷出的區域變更，每個區塊會是一個 scope，然後 unstage, stage 必定是不同 scope」. `indexPositionOf` reads the coordinate both diffs share (unstaged is index→worktree, so its *old* side is the index; staged is HEAD→index, so its *new* side is). Ordering regions asserts precedence only, so 變體 B's ban on hard line alignment survives.
- `ScopedDiffView` takes a **list** of `ScopedDiffSource` (one in `2 file`, two in `unified`); direction, callbacks, empty wording and in-flight/refused flags are per source. Row key `'$sourceIndex:$hunkIndex:$lineIndex'` — a two-part key collides and two `SelectionListener`s share one notifier, a framework assert.
- Sort **decorated with the original index** (`List.sort` is not stable; tie → unstaged first). Never derive 「am I merged?」 from `sources.length` — a unified view of a staged-only file has one source; the owner passes `showColumnHeads`. Build the ordered blocks **once** (`_orderedBlocks` feeds both the widgets and `_rowsInRenderOrder`); two traversals once inverted a drag's direction when regions interleaved. Scope numbering (`變更 N`) is assigned after the sort; `hunkSegments`' `firstOrdinal` and `DiffScopeSegment.ordinal` were deleted.
- A source that is in flight or refused still says so when the other has rows (「Diff too large to display」, `diff_truncation.dart`); only the plain 「nothing on this side」 is suppressed.
- **`IndexPosition` is `({int line, int offset})`**: offset 0 is the line itself, offset 1 sits strictly between `line` and the next; a row before a hunk's first index line takes `start - 1` with offset 1. A one-part position made every inserted row of an untracked file report the same number, a tie the sort cannot break. Compare with `compareIndexPositions` only.
- **Barriers**: `splitHunkIntoScopes` merges changes ≤ `kDefaultScopeGap` unchanged lines apart, but in a merged list an unchanged line of source A that source B draws as a change is a region boundary — a scope may not swallow it (it does not *end* a scope; a barrier outside a gap changes nothing). `changedIndexLines(otherFile, staged:)` and `barrierLineIndices(hunk, …)` compute them, through one `DiffBarrierMemo` shared with the title bar's 「N 未暫存 · M 已暫存」 (two derivations once said 1 over two Stage cards). Memoise on both `DiffFile` identities and `staged` flags; hand back the same `Set`s and `const <int>{}` for a lone side.
- **使用者裁定 B**: a row whose index line the other source already draws as a change is **hidden**, not drawn twice; `hunkSegments` takes `hiddenLines` and *splits the gap run* around each one.
- Discriminating fixtures: sides at **different** index positions (staged at 10, unstaged at 100) plus a guard asserting the reversal; one side's region *between* two of the other's, with a **context** line; an **untracked** file for the two-part position; sides close enough that a barrier falls in a gap.

## Result
Pinned by `scoped_diff_view_test.dart` (staged card painted above unstaged; a drag from the staged row to an unstaged row reads 「Unstage 3 lines」), `diff_scopes_test.dart` (`(line: 10, offset: 1)`, barrier splits, hidden-line split, untracked middle line → two scopes), `working_copy_diff_pane_test.dart` (title bar `2 未暫存 · 1 已暫存`). Evidence: [ledger: 沒寫出來的那條驗收](../ledger/2026-09-05-fix-working-copy-unified-single-view.md).
