# `TopBar` was removed; the tab row sits inside the centre column

- **Kind**: history · **Pins**: was `STRUCT-no-topbar` · **Code**: `RepoSwitcherButton`, `StatusBar`, `GbmActionId.viewRefresh`

## Situation
P02-13 and P03-9 both say the tab row is 「中央區最上方」, and P02's component table has no top bar row.

## Task
Remove `TopBar` without losing its five elements.

## Action
| Was on `TopBar` | Now |
|---|---|
| Repository name | `RepoSwitcherButton` at the top of the sidebar (P02-15) |
| Back-to-welcome | `File → Close window` (its handler was already `go(welcome)`) |
| Theme switch | `View → Theme` |
| In-progress spinner | status bar's background-task zone |
| `Refresh` | **`View → Refresh` + bare F5**, a deliberate deviation (P04's `MENUS` has no such item); dispatches `refreshRepoStatus()` (see its doc comment). The `refreshRepoHistory()` free function it once named is deleted |

## Result
`RepoState::describe()` is on the status bar now — it was *not* there before, despite a note claiming so; `describe()` is non-empty for sequencer operations **and `indexLocked`**, and nothing rendered the latter.
