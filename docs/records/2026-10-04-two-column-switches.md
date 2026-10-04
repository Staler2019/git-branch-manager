# Three two-column switches that look alike and are not — and they do not share a preference

- **Kind**: ruling · **Pins**: was `STRUCT-two-column-switches` · **Code**: `WorkingCopyDiffMode`, `DiffViewMode` (`diff_view_mode_repository.dart`)

## Situation
Two views carry a `GbmSegmentedControl` in a diff titlebar and a third surface is two-column with no switch; conflating them is the easy mistake.

| Where | Enum / storage | Left ↔ right |
|---|---|---|
| Working Copy, `2 file` | `WorkingCopyDiffMode.twoFile`, widget state, not persisted | unstaged ↔ staged |
| Working Copy, `unified` | `WorkingCopyDiffMode.unified`, same storage, **the default** since feat/working-copy-vertical-file-lists | nothing — one merged list; direction per card |
| History commit detail | `DiffViewMode` (`side by side` / `unified`), persisted app-wide under flat key `diffViewMode`, default `unified` | 變更前 ↔ 變更後 |
| Conflict window | no switch, always three panes | ours ↔ result ↔ theirs |

## Task
Decide whether the two switches share one setting.

## Action
They **deliberately do not share a preference** — one flipping both surprises the user in the view they were not looking at. History's switch is its only entry point (no menu item, no shortcut), matching the Working Copy's. Scope is History only; Compare, the panels and the Working Copy render `DiffPage` unchanged. Since fix/working-copy-unified-single-view `unified` is one list, so the card's left edge, dot and verb carry direction ([SPEC-demo-dom-is-the-spec]'s `.variant-B-btn-stage` / `.variant-B-btn-unstage`), and `ScopedDiffView` takes a **list** of `ScopedDiffSource` ([record: merged diff region order](2026-10-04-merged-diff-region-order.md)). Side-by-side pairing is `pairHunkForSideBySide` (`side_by_side_diff.dart`), a line-for-line Dart port of the live C++ reference (`SideBySideDiff.h` says so).

## Result
`diff_view_mode_repository.dart`'s doc comment states the separation; tests `diff_view_mode_repository_test.dart`, `history_diff_view_mode_test.dart`, `working_copy_diff_pane_test.dart`.
