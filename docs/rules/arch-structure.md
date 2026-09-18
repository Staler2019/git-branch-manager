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
`AppPreferences.softWrapEnabled` (Preferences → Appearance → 程式碼, G1i; the section header
was English "CODE" before that round's Chinese-copy pass) decides how
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

**The two columns are stacked, and the whole stack is on the left.** Unstaged
above, Staged below (`splitterWcStack`, vertical, 1:1, min 96), inside a
fixed-width left column (`splitterWcFiles`, extent 260 / min 180) with the
diff filling everything to its right. Both dividers ran the other way until
feat/working-copy-vertical-file-lists — **使用者裁定**, because two file
lists side by side left nothing readable for the file *content*, which is the
thing the page is for. This is a stated deviation from spec page 09's
`SPLITTERS`, whose `wc.columns` row says `dir: '垂直'` and whose `wc.diff`
row says `dir: '水平'` — the `dir` is the divider's own direction, so both
rows are overruled, not renamed. Each divider therefore got a **new storage
key** (`wc.stack`, `wc.files`) rather than inheriting a number that had
stopped meaning anything, per [FLU-splitpane-axis-change]. The commit box is
untouched: still full-width along the bottom, outside the splitter. The drop
hint reads 「拖曳檔案到下欄 = stage」 — 「右欄」 would now name a column that
is not there, and a hint pointing the wrong way is worse than none.

To the right of the columns, the diff area has **two modes** (`2 file`:
unstaged left / staged right, and `unified`, **which is the default** as of
the same round — a right-hand pane split into two monospace columns would
have reproduced the very complaint). ~~`unified` stacks the two sides in one
column~~ — that shipped, and it was 「還是拆成上下檢視」: two columns rotated
rather than merged. **It is now one list**, its cards ordered by where each
region sits on the index (`indexPositionOf`), with the two column heads
replaced by 「N 未暫存 · M 已暫存」 in the title bar and each card carrying
its own direction — 使用者裁定 U1–U8. `2 file`'s layout and behaviour are
untouched; the one thing that crosses into it is the Unstage button's
`border-strong` ring, 使用者裁定 「這是唯一會影響到 2file 的」. It stages by
**scope**, not by
line-checkbox: `diff_scopes.dart` merges changes separated by ≤
`kDefaultScopeGap` (2) unchanged lines, never crossing a hunk — and, in the
merged list, never crossing an unchanged line the *other* side changes
([FLU-other-side-changes-are-barriers]); the title bar's own counts are split
by those same barriers, because they are the list's number. Each scope
card carries its own end-of-run button. An ordinary text selection is a
**one-shot temporary scope**, rendered **nested inside the cards it covers**
— the head and button on the first card the selection reaches, the rest
carrying the dashed body and touched tint. ~~It was a fixed slot at the top
of the column~~ — that shipped, the user pointed at it, and the demo's own
DOM nests `.variant-B-temp` inside `.variant-B-card`. Button text is
`scopeButtonLabel()`'s and only its: 匡選行數 primary, 實際變動行數 in
parentheses (`Stage 3 lines (1 changed)`), parentheses omitted when equal.
~~That last half is an implementation judgement, not the user's verdict~~ —
it is **使用者裁定** now, ruled 照建議 on the same round's §06 question 7.

`DiffPage` is **read-only** and has no staging callbacks; the Working Copy's
diff is `ScopedDiffView`. Selecting a file selects the same *logical* file in
both columns, renames included (`logicalFileKey`).

## [STRUCT-two-column-switches] Three two-column switches that look alike and are not

Two views now carry a `GbmSegmentedControl` in a diff titlebar, and a third
surface is two-column with no switch at all. They mean different things, and
conflating them is the easy mistake:

| Where | Enum / storage | Left ↔ right means |
|---|---|---|
| Working Copy diff pane, `2 file` | `WorkingCopyDiffMode.twoFile`, **widget state, not persisted** | unstaged ↔ staged |
| Working Copy diff pane, `unified` | `WorkingCopyDiffMode.unified`, same storage, **the default** since feat/working-copy-vertical-file-lists | **nothing** — one merged list, ordered by index region; direction is per card |
| History commit detail | `DiffViewMode` (`side by side` / `unified`), persisted app-wide under the flat key `diffViewMode`, default `unified` | 變更前 (old) ↔ 變更後 (new) |
| Conflict window | no switch; always three panes | ours ↔ result ↔ theirs |

`unified` is **one list, not two stacked columns**, since
fix/working-copy-unified-single-view. It had shipped as two `ScopedDiffView`s
one above the other — two columns rotated, which is 「還是拆成上下檢視」 and
what the user rejected. So the row above is two rows now: in `2 file` a
position still means a direction, and in `unified` it means only where the
region sits in the file. The card's own left edge, dot and verb are what
carry direction there ([SPEC-demo-dom-is-the-spec]'s `.variant-B-btn-stage` /
`.variant-B-btn-unstage`), and `ScopedDiffView` takes a **list** of
`ScopedDiffSource` for exactly this reason — one element in `2 file`, two in
`unified` ([FLU-merged-diff-keys-by-source]).

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
column, and a different shape because it is not a commit. **Hollow is a
geometric premise, not just a look**: a commit dot is filled and haloed, so
`GraphRowPainter` starts its edges at the dot's centre and the join is covered;
this shape has no fill, so a connector started at the centre crosses the
transparent interior and pokes out through the lower vertex. It leaves from the
vertex (`centerY + kWorkingCopyDotRadius`), with the lanes' own
`kGraphEdgeStrokeWidth` and round cap rather than a copied literal. The painter
is public for exactly this reason — it was private, so nothing could see its
geometry at all. It is suppressed entirely under a commit search, for the reason `CommitRowColumnPlan.drawsGraph`
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

## [STRUCT-worktrees-tab-is-pinned] The Worktrees panel is a seeded, close-refusing tab — not a third fixed tab

- **Rule**: `GbmPanelKind.isPinned` is true for `manageWorktrees` and nothing else
  (使用者裁定; eleven pinned tabs would fill the strip, and **#62**'s TabRow overflow is open).
  `PanelTabsNotifier`'s constructor seeds it **through `open()`**, so the seeded tab is
  indistinguishable from a user-opened one — same id counter, and `Tools → Worktrees…` focuses it
  through the singleton dedupe that already exists rather than needing a second code path.
- **Rule**: doing it this way reuses the whole P19 round unchanged — the route, the panel shell,
  [FLU-storage-id-not-tab-id]'s `panelStorageId()`, the per-tab scroll and splitter memory — with
  **not one line of the route tree touched**. A third fixed tab would need a second copy of
  `PanelPage`.
- **Rule**: it costs nothing at startup. A tab is a strip entry; `PanelPage` mounts only once
  something navigates to it, so `refreshWorktrees()` and the per-worktree pending counts still wait
  for the user to look.
- **Do**: the refusal lives in `PanelTabsNotifier.close()` and **only** there
  ([CULT-single-source-of-truth]) — `TabRow` draws no ⨯ and `PanelPage`'s Ctrl/Cmd+W returns early,
  but a third caller added later gets the refusal without having to remember it.
- **Do**: `PanelPage._closeThisTab` returns before **both** the navigation and the close. Keeping
  the navigation would send the user to History and leave the tab behind — half an action, worse
  than none, and it is the *route* half of that test which catches the regression.
- **Rule**: the ⨯ is **dropped, not drawn-and-disabled** — a deliberate departure from
  [FLU-menu-enabled-is-visual-only]'s 「隱藏會讓人以為功能不存在」, which assumes the function
  exists and is merely unavailable. Here it does not exist, and a dead ⨯ invites the click it will
  not honour.
- **Note**: **no spec entry.** P14's `IAMAP` puts manage-worktrees on the tab carrier and says
  nothing about permanence. Same category as [STRUCT-soft-wrap-preference] — a user-requested
  addition, not a conformance item.
- **Evidence**: [ledger: Worktree 面板的五個回報](../ledger/2026-09-03-feat-p19-panel-template-conformance-review.md)

## [STRUCT-leaf-label-from-switcher] A file list's leaf label is handed down by `FileListModeSwitcher`, never derived from the item

- **Rule**: `leafBuilder(context, item, label)` takes the label as its third argument. List mode
  passes `pathOf(item)` (the full path); tree mode passes `node.name` (the folded segment). A call
  site that reads the path off the item itself draws the same string in both modes.
- **Consequence**: that is exactly what shipped, on **all six** surfaces at once — Working Copy's
  two columns, History's Changed files, Compare's Files, the Conflict window and
  `panel_file_diff_detail`. Tree mode nested the row under a folder row and then spelled the
  prefix again on the leaf, so 「摺成樹狀」 cost indentation and bought nothing. P03 item 10's own
  wording is 「平鋪完整路徑，或依資料夾摺成樹狀」 — full path is what *list* mode is for.
- **Rule**: ~~the second half is `FileTreeNode`'s. `_collapseIfSingleChild` must keep the whole
  concatenated prefix in `name` when it collapses a chain down to a **file**~~ — **overruled the
  next day, 使用者裁定**: 「樹狀模式下，我想要的是像 vscode 一樣，folder 可以堆疊名稱，但是檔案
  不會有 folder」. A chain of single-child *folders* still stacks into one row (that is P03-10's
  own 「只有一個子項的資料夾會自動串接成 `lib/app/views` 一列」, untouched); the collapse now
  **stops at the file**, which gets a real folder row above it and draws its bare basename. What
  was retired is the previous round's extension of the spec's example to a file child, not the
  example. VS Code's `explorer.compactFolders` is the same rule.
- **Rule**: a folder's `displayPath` is **root-anchored** (`parentPath/label`) while its `name` is
  only the label it draws. `FileTreeList` keys expand/collapse on `displayPath`, so a level-local
  prefix made `lib/features` and `test/features` share one key and open together.
- **Do**: fix this at the switcher, never at one call site. Six call sites each deciding what a
  leaf label is are six chances to disagree ([CULT-single-source-of-truth]); the parameter makes
  it a compile error instead.
- **Do**: ~~the discriminating fixture needs a folder with more than one child~~ — that was true
  only while a lone file collapsed into its parent. Now **any** nested file tells the two modes
  apart, because tree mode draws its basename and list mode its full path. The multi-child fixture
  is still what the *`displayPath`* rule needs: a single-child folder is collapsed into its parent,
  which anchors its prefix as a side effect and hides the shared-key defect
  ([TEST-fixture-cannot-disagree]).
- **Evidence**: [ledger: Working Copy 檔案清單改成左側垂直](../ledger/2026-09-05-feat-working-copy-vertical-file-lists.md);
  [ledger: 追加三，樹狀模式改成 VS Code 語意](../ledger/2026-09-05-fix-working-copy-unified-single-view.md)

## [STRUCT-developer-preferences-tab] Preferences has a seventh, Developer section, and it has no spec basis

- **Rule**: `PreferencesSection` (`preferences_dialog.dart`) has a seventh value, `developer`,
  rendering `_DeveloperSection` — three toggles for this round's own feature flags
  (`showRefreshTimings`, `keepDiffDuringRefresh`, `tieredRefresh`) so the old and new
  refresh behaviour can be compared on real hardware without rebuilding.
- **Note**: **no spec entry.** `PREFNAV` lists six sections; a seventh Developer tab is a
  user-requested addition, same category as [STRUCT-soft-wrap-preference] — not a conformance
  item, and not something a future spec audit should expect to find quoted anywhere in the 21
  pages.
- **Do**: all three toggles reuse the section's existing `_SectionHeading`/`_NavItem`/toggle-row
  widgets — no new drawn value was invented for this section, which is why a `spec-auditor` pass
  before this shipped had nothing new to audit beyond confirming that.
- **Evidence**: [ledger: fix/refresh-ui-first-tiering](../ledger/2026-09-17-fix-refresh-ui-first-tiering.md)
