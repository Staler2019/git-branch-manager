---
paths:
  - "app_flutter/lib/**"
---

# Flutter: focus, gestures, selection and menus

Pin prefix `FLU-`. Format: [README.md](../../docs/rules/README.md). Rules a site comment and a
test already carry (dialog single-entry push, platform-provided menu items, the macOS bundle
name, `showGbmMenu`'s barrier, hit-test gotchas, select-all scoping) live there.

## [FLU-inkwell-tap-gives-no-focus] Tapping an `InkWell` does not give it focus

- **Do**: call `requestFocus()` first if a focus-scoped shortcut has to work after a click (`sidebar_panel.dart`'s `_onBranchSelect`, `commit_graph_view.dart`'s `_publish`).

## [FLU-hand-rolled-inkwell-hover] A hand-rolled `InkWell` silently inherits `ThemeData.hoverColor`

- **Rule**: about 4% black/white, invisible on a real display; `lib/widgets/gbm_row.dart` exists to pass `surfaceHover`/`surfaceSelected` for you.
- **Do**: reach for `GbmRow` for anything row-shaped and **assert the token by identity**; a hover test that only checks for no exception proves nothing.
- **Do**: at the end of any round that touches widgets, grep every `InkWell(`/`GestureDetector(` in the changed files. It recurred five times (branch rows, `FileTreeFolderRow`, a private mini-button, `_StashRow`, the conflicted-file row).
- **Do**: when `GbmRow` would force an invented interaction (no `onDoubleTap`; an `InkWell` with no callback is not hover-enabled), paint the same token from a `MouseRegion` and say why in the doc comment (`_ConflictedFileRow`).
- **Evidence**: ledger: Sidebar branch rows; [ledger: 側邊欄 STASH 列補上 hover/選取/選單](../../docs/ledger/2026-09-01-claude-sidebar-stash-styling-date-3dvzmu.md); [ledger: Working Copy 檔案清單改成左側垂直](../../docs/ledger/2026-09-05-feat-working-copy-vertical-file-lists.md)

## [FLU-gesture-arena-taxes-double-tap] The gesture arena taxes double-clickable rows, and it is not local

- **Rule**: an `InkWell` holding both `onTap` and `onDoubleTap` withholds the tap for `kDoubleTapTimeout` (~300ms), and a `DoubleTapGestureRecognizer` anywhere on the *ancestor* path does the same to every child button underneath it.
- **Do**: put an immediate action on `Listener(onPointerDown:)` (never enters the arena) and keep the double-tap on the narrowest subtree (`branch_tree_item.dart`, `_ConflictedFileRow`).
- **Note**: `InkResponse` hovers only when `isWidgetEnabled` (`onTap`-family or `onSecondaryTapDown` set), which couples this to [FLU-hand-rolled-inkwell-hover]. Test the tax with one `tap` and one `pump()`, no duration (`working_copy_view_test.dart`, 'a button fires on the frame it is pressed').
- **Evidence**: [ledger: Working Copy 檔案清單改成左側垂直](../../docs/ledger/2026-09-05-feat-working-copy-vertical-file-lists.md)

## [FLU-selectionarea-gives-a-string] `SelectionArea` tells you the selected *string*, not which widgets it covers

- **Rule**: `selection_touch.dart` asks each row's own `SelectionListener`. The traps (a stable `GlobalKey` per row, listen only between pointer-down and pointer-up, draw nothing derived from the set while the pointer is down) are documented there and at `scoped_diff_view.dart`'s `_wellChildren`.
- **Consequence**: all three are 「first frame right, later frames wrong」, so a one-frame assertion cannot see any of them; pinned by `scoped_diff_view_test.dart` ('no one-shot block appears until the pointer comes up') and `soft_wrap_preference_flow_test.dart`.
- **Note**: the honest limit: no synthetic gesture at either tier reproduces 「只能選一行」 (`stage_lines_flow_test.dart`'s row-by-row drag stayed green with the gate removed). The invariant is pinned; the cure is not.
- **Do**: a recorded hazard is a reason to solve the problem, not a licence to change the design; the one-shot block stays nested in its scope card ([record](../../docs/records/2026-10-04-working-copy-layout.md)).

## [FLU-menu-enabled-is-visual-only] `GbmMenuItem.enabled: false` is only a visual signal

- **Do**: set `onTap: null` too, or a "disabled" item still fires.
- **Do**: disabled-with-a-tooltip beats hidden — 隱藏會讓人以為功能不存在.

## [FLU-clear-selection-before-dispatch] The submit path is a diff-change path, one dispatch later

- **Do**: call `clearSelection()` synchronously **before** dispatching a stage; deferred, it lands inside the restructure it caused and throws `ConcurrentModificationError` from `handleClearSelection` (`scoped_diff_view.dart`'s `_submitTemporary`).
- **Note**: **no test pins it.** Moving the clear after the dispatch left `stage_lines_flow_test.dart` green on macOS (7/7): its tap collapses the selection by itself, and the keyboard path (`repositoryStageSelectedLines`) has no device test.
- **Evidence**: [ledger: L1 第九片](../../docs/ledger/2026-10-04-chore-s3-l1-flutter-input.md)
