# The Worktrees panel is a seeded, close-refusing tab — not a third fixed tab

- **Kind**: ruling · **Pins**: was `STRUCT-worktrees-tab-is-pinned` · **Code**: `GbmPanelKind.isPinned`, `PanelTabsNotifier.close()`

## Situation
P14's `IAMAP` puts manage-worktrees on the tab carrier and says nothing about permanence — no spec entry, a user-requested addition (same category as the soft-wrap ruling). Eleven pinned tabs would fill the strip, and **#62**'s TabRow overflow is open.

## Task
Keep the Worktrees panel always present (使用者裁定) without a second copy of `PanelPage` and without startup cost.

## Action
- `GbmPanelKind.isPinned` is true for `manageWorktrees` and nothing else. `PanelTabsNotifier`'s constructor seeds it **through `open()`**, so the seeded tab is indistinguishable from a user-opened one — same id counter, and `Tools → Worktrees…` focuses it through the existing singleton dedupe.
- This reuses the P19 round unchanged — the route, the panel shell, `panelStorageId()` ([FLU-storage-id-not-tab-id]), per-tab scroll and splitter memory — with not one line of the route tree touched. A third fixed tab would need a second copy of `PanelPage`.
- No startup cost: a tab is a strip entry; `PanelPage` mounts only on navigation, so `refreshWorktrees()` and the per-worktree pending counts still wait for the user to look.
- The refusal lives in `PanelTabsNotifier.close()` and only there; `TabRow` draws no ⨯ and `PanelPage`'s Ctrl/Cmd+W returns early, but a third caller gets the refusal for free.
- `PanelPage._closeThisTab` returns before **both** the navigation and the close — keeping the navigation would send the user to History and leave the tab behind; the route half of that test catches the regression.
- The ⨯ is **dropped, not drawn-and-disabled** — a deliberate departure from [FLU-menu-enabled-is-visual-only]'s 「隱藏會讓人以為功能不存在」, which assumes the function exists; here it does not, and a dead ⨯ invites the click it will not honour.

## Result
Pinned by `panel_tabs_repository_test.dart` (「a pinned tab survives an explicit close」, the pinned set) and `tab_row_test.dart`. Evidence: [ledger: Worktree 面板的五個回報](../ledger/2026-09-03-feat-p19-panel-template-conformance-review.md).
