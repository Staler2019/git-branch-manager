# The log drawer starts collapsed on every launch, and dragging it to the bottom closes it

- **Kind**: ruling · **Pins**: was `FLU-collapsed-drawer-stores-height`, `FLU-clamp-loses-drag-overshoot` · **Code**: `GbmSplitPane` (`split_pane.dart`), `GbmSplitterSpec.collapsedByDefault`, `splitterMainLog`

## Situation
`collapsedByDefault` was read as `stored == null && collapsedByDefault`, so it held only until the pane was first opened — an open persists a non-zero extent through `_setExtent` → `_persistFlexes`. The log drawer was 使用者回報 as always open once `View → Log` became a real toggle (`GbmActionId.viewLog`). Separately, 「拖到底關閉」 was asked for, and `_onDividerDelta` clamps every step to `minExtent`, so `_currentFlexes[0] + delta` never falls far below it however far the pointer travels.

## Task
使用者裁定 「log不預設打開，使用者toggle才開」, plus drag-to-close, without disturbing any non-drawer pane.

## Action
- A `collapsedByDefault` pane starts collapsed on **every** launch; its storage holds the height to *reopen to*, never an open/closed state, and `initState` ignores it when deciding the starting state.
- `_persistFlexes` never writes such a pane's 0 (that would erase the dragged height); `_openToMinimum` reads `_reopenExtent`, because `_currentFlexes[0]` is what the collapse set to 0. `_resetToSpecDefault` clears `_reopenExtent` too.
- Drag overshoot: `_dragRawExtent` accumulates the *unclamped* travel, opened on `onDragStart`, cleared on **both** `onDragEnd` and `onDragCancel`. It is clamped per step with a floor of 0 when the pane may collapse and `minExtent` otherwise, so every non-collapsible pane behaves byte-for-byte as before. The gate is `collapsedByDefault` (a drawer has a reopen affordance; another pane dragged to 0 would be lost). Keyboard steps are excluded (`_dragRawExtent == null`).
- The height left behind is drag-speed dependent, deliberately: a real drag passes through the clamp region (last height `minExtent`); one frame large enough to skip it leaves the previous height.
- The `stored[0] > 0` guard of `GbmSplitPane`'s `initState` clamp now covers only a non-drawer extent pane.
- No migration: a profile stuck open keeps its stored number, startup ignores it, the first toggle restores it.

## Result
Pinned by `workspace_log_drawer_reachability_test.dart` (seeds `panelLayout.main.log: '[200.0]'` via `pumpWorkspace`'s `initialPrefs`; drawer height 0; Ctrl+Shift+L reopens to 200) and `split_pane_test.dart` (many small `moveBy` steps close the drawer; a non-drawer floors at its minimum; persisted value never 0). A virgin-profile test cannot see the first defect, and one large `moveBy` cannot see the second. Open: `_resetToSpecDefault`'s `_reopenExtent` clearing has no test. Evidence: [ledger: 追加五](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md), [ledger: 追加六](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md).
