# Structure

Pin prefix `STRUCT-`. Format: [README.md](README.md).

Current-state reference: layering, the route tree, where each feature's files live, and
the surfaces whose shapes are routinely confused for each other. Moved here whole —
nothing in this file was condensed, because there is no narrative to condense out of it.

## [STRUCT-layering] Layering

```
src/core/   headless C++20, no Qt/Dart (docs/ARCHITECTURE.md)
  -> src/capi/                        gbm_capi.h, extern "C", JSON/event bridge
  -> app_flutter/lib/data/ffi/        gbm_bindings.dart (dart:ffi)
  -> app_flutter/lib/data/repositories/  Riverpod state (RepoSessionState, ...)
  -> app_flutter/lib/features/**      views
```

## [STRUCT-route-tree] Screen / route tree

(`app_flutter/lib/routing/route_paths.dart`, `app_router.dart`)

```
/                                  WelcomeScreen (only when no repo is open)
/repo/:repoId                      redirect -> /repo/:repoId/history
/repo/:repoId  (ShellRoute: WorkspaceScreen = menu bar + action toolbar +
                 sidebar | 〈tab row + route content〉)
  /history                         CommitGraphView
  /working-copy                    WorkingCopyView
  /compare/:tabId                  ComparePage (one ShellRoute child per open Compare tab)
  /panel/:tabId                    PanelPage (one per open management-panel tab, spec P14)
/repo/:repoId/conflicts            ConflictResolveWindow (standalone window, not a dialog overlay)

/dialogs/about                            \  app-wide (not repo-scoped: discovery,
/dialogs/keyboard-shortcuts                | app settings and the update check
/dialogs/manage-base-folders               > aren't tied to any one open repository
/dialogs/preferences                       | -- see gbm_capi.h's Discovery section
/dialogs/update                           /  and spec page 11)

/repo/:repoId/dialogs/<name>       22 repo-scoped dialogs: reset-branch, merge,
                                    cherry-pick, stash-changes, create-tag,
                                    credential, undo-last, clean-untracked,
                                    checkout-recovery, delete-branch-recovery,
                                    prune-remote-branches, repository-settings,
                                    new-branch, checkout, delete-branch,
                                    rebase-onto, force-push, delete-remote-branch,
                                    restore-file, discard-changes,
                                    rename-branch, delete-branches
```

## [STRUCT-panels-are-tabs] Twelve former dialogs are `/panel/:tabId` tabs, not dialog routes

**Twelve former dialogs are now `/panel/:tabId` tabs**, not dialog routes —
spec page 14's `IAMAP` reassigns every large management panel to the tab
carrier (see docs/ledger.md's "Tier 6c"). `manage-stashes`, `manage-worktrees`,
`manage-remotes`, `manage-submodules`, `manage-lfs`, `patches`, `reflog`,
`interactive-rebase`, `bisect`, `blame`, `file-history` and `line-history`
were deleted along with their routes and helpers; a `RoutePaths.<name>DialogFor`
for any of them no longer exists.

Dialog routes are top-level (pushed over whatever's underneath), not
`ShellRoute` children — see `dialog_route.dart`.

## [STRUCT-update-dialog-no-menu] `/dialogs/update` has no menu-bar entry, by design

**`/dialogs/update` has no menu-bar entry, by design.** Its three producers
are `about_dialog.dart`'s primary button, `preferences_dialog.dart`'s
「Check for updates now」 (Advanced), and `app.dart`'s `AutoUpdateCheck` at
startup. A `Help → Check for updates…` item existed and was removed — the
spec's P04 `MENUS` gives Help four items and that was a fifth, so the menu
is now conformant rather than deviating. About's button is the one that
matters: `WelcomeScreen` renders no menu bar at all, so with no repository
open it is the only reachable route to the check.

## [STRUCT-preferences-vs-repo-settings] Preferences vs Repository settings

**Preferences vs Repository settings.** These are two different dialogs and
the split is deliberate (spec pages 11 and 06): `/dialogs/preferences` is
application-level (six sections: General / Repository sources / Git /
Appearance / Shortcuts / Advanced) and opens with no repository at all, while
`/repo/:repoId/dialogs/repository-settings` is per-repository (four tabs:
General / Remotes / Identity / Performance). They were previously one
repo-scoped dialog that both `filePreferences` and `repositorySettings`
opened, so Ctrl/Cmd+, landed on Git identity.

## [STRUCT-soft-wrap-preference] Soft wrap is an app-level preference, and it is off by default

**Soft wrap is an app-level preference, and it is off by default.**
`AppPreferences.softWrapEnabled` (Preferences → Appearance → CODE) decides how
*every* file-content surface handles a line too wide for its pane. Off — the
shipped default — means the line runs to the right behind a horizontal
scrollbar with the line-number gutter pinned at the viewport's left edge; on
means it wraps. **Off is a change from what shipped before it**: nothing was
configurable and every surface wrapped unconditionally, because a bare `Text`
defaults to `softWrap: true` inside an `Expanded`. The surfaces are
`DiffLineView`/`DiffPage` (History detail, Compare, file-history and stashes
panels all render through `DiffPage`), `SideBySideDiffView` (History's 並排
mode), `ScopedDiffView` (Working Copy), `PanelDiffText` (patches and
line-history panels), `BlamePanel` and `ConflictResolveWindow`; the
commit-message box is deliberately untouched. **`SideBySideDiffView` pins
neither gutter** — two columns have two, only the left one is at the
viewport's edge, and freezing that one alone desynchronises the pair; its
two columns share one scroller so a pair stays aligned. That last one is
the implementer's judgement, **not the user's ruling**, and the user's
standing position on pinning is the opposite — it is open on **#119**
pending a real-hardware check, so do not read it as settled either way. The
machinery is `lib/widgets/gbm_code_hscroll.dart` (`GbmCodeHScroll`,
`GbmPinnedGutter`, `GbmPinnedGutterClip`) plus `lib/widgets/code_line_metrics.dart`,
which measures the widest line with one `TextPainter.layout` and memoises it —
5,000 lines costs 46ms, so that memo is a correctness requirement, not an
optimisation. The spec has no wrap row anywhere in its 21 pages; this is a
user-requested addition, not a conformance item (ledger: soft-warp).

## [STRUCT-repo-selection] Where repository selection lives

**Where repository selection lives.** The spec has no repository-list page:
the window *is* a repository (pages 01–03), so the app's default route is
the last-opened repository's workspace and `/` is only the fallback for
"nothing open yet". Selecting a repository is a popover anchored under a
button at the top of the sidebar (spec page 02 item 15, Ctrl/Cmd+R,
`features/repo_switcher/repo_switcher_popover.dart`) — searchable, recents
first, `Open` / `Clone` pinned at the bottom, Esc closes without switching,
right-click on a row is context menu 05-A. Configuring *where* repositories
are discovered from — base folders, scan depth, the manually-opened list —
is Preferences → Repository sources (spec page 11), not part of picking one.
Before this split, `/` was a repository dashboard that also owned the
base-folder quick-add, and Ctrl/Cmd+R opened a modal dialog listing recents;
both are gone. `WelcomeScreen` embeds the same `RepoSwitcherList` the
popover shows, because with no repository open there is no sidebar to hang a
popover off.

## [STRUCT-feature-dirs] Feature directory layout

```
lib/
  data/
    ffi/            gbm_bindings.dart (dart:ffi bindings, GbmEventType enum),
                     event_dispatcher.dart (NativeCallable.listener -> broadcast Stream<GbmEvent>)
    models/          Immutable DTOs mirroring capi JSON shapes
                      (RepoState, WorkingCopyStatus, CommitMeta, ...)
    repositories/    repo_session_repository.dart (RepoSessionState +
                      RepoSessionController), history_repository.dart, repo_identity.dart
  routing/           route_paths.dart, app_router.dart, dialog_route.dart
  theme/             gbm_theme.dart, tokens.dart, theme_mode_provider.dart, ref_chip_colors.dart
  widgets/           Design-system components shared across features
                      (GbmBadge, GbmButton, GbmPanel, GbmRow, ...) — reach for
                      one of these before hand-rolling a Container; see
                      docs/ledger.md's "Known gaps" for a case where that was missed.
  features/
    welcome/         WelcomeScreen (route `/`, no repository open)
    repo_switcher/   RepoSwitcherButton (sidebar top) + popover + RepoSwitcherList
    workspace/       WorkspaceScreen (shell) + widgets/ (MenuBarRow,
                      ActionToolbar, TabRow — presentational, no
                      Riverpod dependency)
    history_graph/   CommitGraphView, commit_row.dart
    working_copy/    WorkingCopyView
    sidebar/         SidebarPanel
    diff/            DiffPage (read-only, unified), SideBySideDiffView
                      (read-only, 舊/新 two-column) + side_by_side_diff.dart,
                      ScopedDiffView + diff_scopes.dart
                      + selection_touch.dart (Working Copy's staging diff)
    conflict_resolution/  ConflictResolveWindow (standalone window, not a dialog)
    compare/         ComparePage
    panels/          PanelPage + GbmPanelTabShell (spec P19's shared
                      〈toolbar + left list + right detail〉 template) +
                      one file per ported management panel
    status_bar/      StatusBar, BackgroundTask
    log_drawer/      LogDrawer
    context_menus/   Shared GbmContextMenuItemSpec builders (9 right-click targets)
    dialogs/         The 22 repo-scoped dialog contents listed above, plus the 5 app-wide ones
```

Presentational/container split: `MenuBarRow`, `ActionToolbar`, `TabRow`
(`features/workspace/widgets/`) take plain callbacks/values and hold
no Riverpod dependency, so they're tested directly against a bare `GoRouter`
(see `test/features/workspace/*_test.dart`). `WorkspaceScreen` is the
container: it watches `repoSessionProvider` and wires the callbacks in.

## [STRUCT-no-topbar] `TopBar` no longer exists

**`TopBar` no longer exists**, and the tab row is inside the centre column,
not spanning the window. Both are spec (P02-13 and P03-9 both say 「中央區
最上方」; P02's component table has no row for a top bar at all). Where its
five elements went, so a future round does not re-add them:

| Was on `TopBar` | Now |
|---|---|
| Repository name | `RepoSwitcherButton` at the top of the sidebar (P02-15) |
| Back-to-welcome | `File → Close window` — its handler was already `go(welcome)` |
| Theme switch | `View → Theme` |
| In-progress spinner | Status bar's background-task zone |
| `Refresh` | **`View → Refresh` + bare F5**, a deliberate deviation (P04's `MENUS` has no such item). It now dispatches `refreshRepoStatus()`, not just the history — see "Refs, git and the core's own vocabulary" below. The `refreshRepoHistory()` free function this once named is deleted; it had no caller left |

Repo state (`RepoState::describe()`) is also on the status bar now — it was
*not* there before, despite a note claiming so: `describe()` is non-empty for
sequencer operations **and `indexLocked`**, and nothing rendered the latter.

## [STRUCT-working-copy] Working Copy (spec P03), as it now stands

**There is no checkbox anywhere in the two columns** — not on a row, not in a
column header, not on a tree-mode folder row. This is a **user-ratified
deviation** from P03-1 / P03-3 / P03-10 and `SCOPES` rows 1/4/5, which all
specify one; do not "fix" it back. Files move side by **dragging** (a folder
row is itself draggable and takes its whole subtree); a whole column goes
through `Repository → Stage all` (`Ctrl/Cmd+Alt+A`) or the context menu;
half-staged is expressed by the `+34 −12` line counts, which say more than a
tri-state box could. The reasoning and what replaced each removed affordance
is in the ledger under "Working Copy 重新設計".

Below the columns, the diff area has **two modes** (`2 file`: unstaged left /
staged right, and `unified`) and stages by **scope**, not by line-checkbox:
`diff_scopes.dart` merges changes separated by ≤ `kDefaultScopeGap` (2)
unchanged lines, never crossing a hunk, and each scope card carries its own
end-of-run button. An ordinary text selection is a **one-shot temporary
scope** rendered in a fixed slot at the top. Button text is
`scopeButtonLabel()`'s and only its: 匡選行數 primary, 實際變動行數 in
parentheses (`Stage 3 lines (1 changed)`), parentheses omitted when equal —
that last half is an implementation judgement, not the user's verdict.

`DiffPage` is **read-only** and has no staging callbacks; the Working Copy's
diff is `ScopedDiffView`. Selecting a file selects the same *logical* file in
both columns, renames included (`logicalFileKey`).

## [STRUCT-two-column-switches] Three two-column switches that look alike and are not

Two views now carry a `GbmSegmentedControl` in a diff titlebar, and a third
surface is two-column with no switch at all. They mean different things, and
conflating them is the easy mistake:

| Where | Enum / storage | Left ↔ right means |
|---|---|---|
| Working Copy diff pane | `WorkingCopyDiffMode` (`2 file` / `unified`), **widget state, not persisted** | unstaged ↔ staged |
| History commit detail | `DiffViewMode` (`side by side` / `unified`), persisted app-wide under the flat key `diffViewMode`, default `unified` | 變更前 (old) ↔ 變更後 (new) |
| Conflict window | no switch; always three panes | ours ↔ result ↔ theirs |

They deliberately **do not share a preference** — one setting flipping both
would surprise the user in whichever view they were not looking at. History's
switch is the only entry point to its mode: no menu item, no shortcut, which
matches the Working Copy's switch exactly and is an alignment, not an
omission. Scope is History only; Compare, the panels and the Working Copy
render `DiffPage` as before, and `DiffPage` itself was not modified.

Side-by-side pairing is `pairHunkForSideBySide` (`side_by_side_diff.dart`),
a line-for-line Dart port of the still-live C++ reference implementation —
see the two orphan-wiring entries under "Repo culture" before deleting either.

## [STRUCT-history-uncommitted-row] History pins one uncommitted-changes row above the list

**History pins one uncommitted-changes row above the commit list**, present only
when `workingCopyStatus.entries` is non-empty and a commit search is not
running. It is **not a `ListView` item**: the graph's edge lookups, its span
index and every selection range are keyed on row indices, and
[STATE-unfiltered-row-indices]'s `UnfilteredRowIndices` is an O(1) identity view
precisely because those indices *are* the row numbers — prepending would shift
all of it. It also costs no history walk, so saving a file updates it on the
same frame as the tab badge without an O(rows) `publish()`.

It sits in lane 0 because lane 0 is HEAD's branch
([SPEC-lane-zero-is-head]), drawn as a **hollow diamond** at
`kGraphLaneInset` — the same 5.0 radius as a commit dot, so the two read as one
column, and a different shape because it is not a commit. It is suppressed
entirely under a commit search, for the reason `CommitRowColumnPlan.drawsGraph`
already gives for the lanes themselves.

**The join down to HEAD's dot is two half-lines from one boolean, and must stay
that way.** The row paints from its diamond to its own bottom edge and can go no
further — `commit_row.dart` clips its graph column. The other half is
`GraphRowPainter.connectsUpToUncommitted` on the topmost *painted* row, and it
exists because a row's segments come from `graph.edges` while the topmost row
has no incoming edge — nothing in the view is its child — so that half was drawn
by nothing at all and the line stopped dead on the row boundary, half a row
short of the dot it pointed at. `CommitGraphView` computes `connectsToHead` once
and hands it to both consumers; deriving the two conditions separately is
precisely how you get half a line ([CULT-single-source-of-truth]). **Not** a
synthesised `GraphEdge`: its `childRow` would not exist, and it would flow into
`edgesSpanning`, the span index and the ASCII reference renderer
([CPP-ascii-renderer-is-reference]), none of which know what a working copy is.
The condition is «the first painted row is HEAD's tip **and** that row sits in
lane 0» — the diamond is fixed at lane 0, and a filtered walk gets no `trunkTip`
reservation ([SPEC-lane-zero-is-head]), so joining across lanes would draw a
lane change no commit made. Every fixture in this area left `refs` at its
default until this was found, so `head.target` was `''` and the connector was
covered by nothing in either direction.

**Selection shares `commitSelectionProvider`** under the sentinel
`kWorkingCopySelectionId` — one selection state, not two that could disagree
([CULT-single-source-of-truth]). `selectedCommitProvider` reports `null` for it,
which is what every one-commit surface already gates on. Plain ↑/↓
(`GbmMoveSelectionIntent`) treats it as index 0 of the painted order; Shift+↑/↓
deliberately does not, because a range spanning it is not a range git could
replay.

**Selecting it shows a summary, not files** — user-ratified: 「可選取，但只顯示
摘要」. `CommitDetailPanelCore` draws the count plus one 「Open in Working Copy」
button (equivalent to Ctrl/Cmd+2), and `ChangedFilesPanelCore` draws a pointer at
the Working Copy tab rather than a list. The file-level diff stays in the Working
Copy, which is the only surface that can stage, discard or commit any of it; a
second list that could not would be [UX-rubric] dimension D's redundant view.
Note the changed-files list is suppressed by that flag and **not** by an empty
`commitFilesProvider`, which still holds the previously-selected commit's files.

**Under this row, 05-K has no dialog and no functionality** — user-ratified,
「之後有需要再設計」. That follows from the paragraph above rather than being a
separate decision: 05-K's items hang off the changed-files list, and this row
draws a pointer instead of one. **The three actions people reach for first are
not the ones affected**: Cherry-pick, Revert and Reset here are 05-E items
carrying the right-clicked row's own oid, and read nothing about the selection —
a claim that they were gated on `selectedCommitProvider` stood in this codebase
for one round and was wrong.

**Selecting it and then discarding is a real transition, and the anchor alone
does not survive it.** The row exists only while the working copy is dirty, so
`workingCopyRowSelectedProvider` requires *both* the sentinel anchor and
`pendingChangeCount > 0`; on the anchor alone, discarding every change deletes
the row out from under the selection and both panels go on drawing 「0 changed
files」 for a clean working copy. It is a pure derivation rather than a widget
clearing the selection, because the latter is a provider write from `build()`
([FLU-never-write-provider-in-build]) plus a second predicate a later surface
could forget. The commit search that also hides the row is deliberately **not**
part of the condition — a filter hiding a row does not make the summary untrue.

**No spec entry.** The 21 pages have no uncommitted row anywhere (searched
未提交 / 虛擬 / uncommitted / 工作區) and `spec_logic.js`'s own History mock starts
at a real commit. This is a user-requested addition like
[STRUCT-soft-wrap-preference], not a conformance item.
