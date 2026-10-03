# Twelve former dialogs are `/panel/:tabId` tabs, not dialog routes

- **Kind**: history · **Pins**: was `STRUCT-panels-are-tabs` · **Code**: `GbmPanelKind`, `RoutePaths.panel`

## Situation
Spec page 14's `IAMAP` reassigns every large management panel to the tab carrier (docs/ledger.md's "Tier 6c").

## Task
Move the twelve management dialogs onto tabs.

## Action
`manage-stashes`, `manage-worktrees`, `manage-remotes`, `manage-submodules`, `manage-lfs`, `patches`, `reflog`, `interactive-rebase`, `bisect`, `blame`, `file-history` and `line-history` were deleted along with their routes and helpers; a `RoutePaths.<name>DialogFor` for any of them no longer exists. Dialog routes are top-level (pushed over whatever's underneath), not `ShellRoute` children — see `dialog_route.dart`.

## Result
`GbmPanelKind` holds exactly these twelve kinds. The worktree dialogs added later (add/remove/lock) are spec page 06 dialogs, not panels.
