# CLAUDE.md

Root-level guide for Claude Code (and other AI assistants) working in this
repo. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/FEATURES.md](docs/FEATURES.md) first — this file adds the Flutter UI's
structure, its session state machine, the UX acceptance bar `app_flutter/`
changes are held to, and the invariants and traps that keep being rediscovered.

## Where a round's write-up goes

**This file is auto-loaded into every session; [docs/ledger.md](docs/ledger.md)
is not.** That difference is the whole filing rule, and it exists because every
round used to append its narrative here until the file reached ~176KB.

When you finish a round of work:

1. **The narrative goes to `docs/ledger.md`** — a new section at the end, named
   for its branch, in the shape the sections already there use: what changed,
   which premises did not survive the source, what was found by *running*
   rather than reading, and what was deliberately reduced or left open.
   Length is free there.
2. **Only what a future session must know *before* it starts comes back here**,
   and only as a distilled entry under "Invariants and traps" — a rule, its
   consequence, and an anchor (issue number or ledger section) pointing at the
   evidence. If an existing entry already covers it, add the new shape to that
   entry rather than a second one.
3. **Current-state facts belong here too** — a route, a field, a state
   transition, a CI constraint, a still-open drift. History does not: if the
   sentence only makes sense as "what happened in round N", it is ledger
   material.

Adding a round-shaped section to this file is the thing that broke it before.

## Structure

### Layering

```
src/core/   headless C++20, no Qt/Dart (docs/ARCHITECTURE.md)
  -> src/capi/                        gbm_capi.h, extern "C", JSON/event bridge
  -> app_flutter/lib/data/ffi/        gbm_bindings.dart (dart:ffi)
  -> app_flutter/lib/data/repositories/  Riverpod state (RepoSessionState, ...)
  -> app_flutter/lib/features/**      views
```

### Screen / route tree

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

/dialogs/about                            \  app-wide (not repo-scoped: discovery
/dialogs/keyboard-shortcuts                > and app settings aren't tied to any
/dialogs/manage-base-folders               > one open repository, see gbm_capi.h's
/dialogs/preferences                      /  Discovery section, and spec page 11)

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

**Twelve former dialogs are now `/panel/:tabId` tabs**, not dialog routes —
spec page 14's `IAMAP` reassigns every large management panel to the tab
carrier (see docs/ledger.md's "Tier 6c"). `manage-stashes`, `manage-worktrees`,
`manage-remotes`, `manage-submodules`, `manage-lfs`, `patches`, `reflog`,
`interactive-rebase`, `bisect`, `blame`, `file-history` and `line-history`
were deleted along with their routes and helpers; a `RoutePaths.<name>DialogFor`
for any of them no longer exists.

Dialog routes are top-level (pushed over whatever's underneath), not
`ShellRoute` children — see `dialog_route.dart`.

**Preferences vs Repository settings.** These are two different dialogs and
the split is deliberate (spec pages 11 and 06): `/dialogs/preferences` is
application-level (six sections: General / Repository sources / Git /
Appearance / Shortcuts / Advanced) and opens with no repository at all, while
`/repo/:repoId/dialogs/repository-settings` is per-repository (four tabs:
General / Remotes / Identity / Performance). They were previously one
repo-scoped dialog that both `filePreferences` and `repositorySettings`
opened, so Ctrl/Cmd+, landed on Git identity.

**Soft wrap is an app-level preference, and it is off by default.**
`AppPreferences.softWrapEnabled` (Preferences → Appearance → CODE) decides how
*every* file-content surface handles a line too wide for its pane. Off — the
shipped default — means the line runs to the right behind a horizontal
scrollbar with the line-number gutter pinned at the viewport's left edge; on
means it wraps. **Off is a change from what shipped before it**: nothing was
configurable and every surface wrapped unconditionally, because a bare `Text`
defaults to `softWrap: true` inside an `Expanded`. The surfaces are
`DiffLineView`/`DiffPage` (History detail, Compare, file-history and stashes
panels all render through `DiffPage`), `ScopedDiffView` (Working Copy),
`PanelDiffText` (patches and line-history panels), `BlamePanel` and
`ConflictResolveWindow`; the commit-message box is deliberately untouched. The
machinery is `lib/widgets/gbm_code_hscroll.dart` (`GbmCodeHScroll`,
`GbmPinnedGutter`, `GbmPinnedGutterClip`) plus `lib/widgets/code_line_metrics.dart`,
which measures the widest line with one `TextPainter.layout` and memoises it —
5,000 lines costs 46ms, so that memo is a correctness requirement, not an
optimisation. The spec has no wrap row anywhere in its 21 pages; this is a
user-requested addition, not a conformance item (ledger: soft-warp).

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

### Feature directory layout

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
    diff/            DiffPage (read-only), ScopedDiffView + diff_scopes.dart
                      + selection_touch.dart (Working Copy's staging diff)
    conflict_resolution/  ConflictResolveWindow (standalone window, not a dialog)
    compare/         ComparePage
    panels/          PanelPage + GbmPanelTabShell (spec P19's shared
                      〈toolbar + left list + right detail〉 template) +
                      one file per ported management panel
    status_bar/      StatusBar, BackgroundTask
    log_drawer/      LogDrawer
    context_menus/   Shared GbmContextMenuItemSpec builders (9 right-click targets)
    dialogs/         The 34 repo-scoped dialog contents listed above, plus the 4 app-wide ones
```

Presentational/container split: `MenuBarRow`, `ActionToolbar`, `TabRow`
(`features/workspace/widgets/`) take plain callbacks/values and hold
no Riverpod dependency, so they're tested directly against a bare `GoRouter`
(see `test/features/workspace/*_test.dart`). `WorkspaceScreen` is the
container: it watches `repoSessionProvider` and wires the callbacks in.

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
| `Refresh` | **`View → Refresh` + bare F5**, a deliberate deviation (P04's `MENUS` has no such item) — `refreshRepoHistory()` had exactly one caller in all of `lib/` and it was `TopBar` |

Repo state (`RepoState::describe()`) is also on the status bar now — it was
*not* there before, despite a note claiming so: `describe()` is non-empty for
sequencer operations **and `indexLocked`**, and nothing rendered the latter.

### Working Copy (spec P03), as it now stands

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

## State Machine

### RepoSessionState

`app_flutter/lib/data/repositories/repo_session_repository.dart` — one
immutable snapshot per `RepoIdentity`, republished via `copyWith()` on every
relevant FFI event (never mutated in place; docs/ARCHITECTURE.md invariant 2
applies to the Flutter layer too).

| Field | Type | Meaning |
|---|---|---|
| `isOpen` | `bool` | FFI session handle is allocated and listening |
| `repoState` | `RepoState?` | detached / on-branch / rebasing / merging / ... |
| `refs` | `RefSnapshot` | branches, tags, HEAD |
| `graph` | `GraphSnapshotView` | commit history DAG |
| `isRefreshing` | `bool` | history/graph fetch in flight |
| `lastError` | `GitError?` | most recent operation error |
| `workingCopyStatus` | `WorkingCopyStatus` | staged/unstaged/untracked/conflicted paths |
| `workingCopyDiffs` | `Map<String, WorkingCopyDiffReply>` | diffs keyed by `workingCopyDiffKey(path, staged:)`; merged, never replaced wholesale. **Not reducible back to a single `lastDiff` slot** — P03 shows unstaged and staged at once, and two replies to one selection race |
| `lastWorkingTreeContent` | `WorkingTreeContentReply?` | file content incl. conflict markers |
| `stashes` | `List<StashEntry>` | all stash entries |
| `lastStashDiff` | `StashDiffReply?` | diff of a stash |
| `worktrees` | `List<WorktreeInfo>` | linked worktrees |
| `remotes` | `List<RemoteInfo>` | remote URLs + tracking |
| `credentialPrompt` | `String?` | outstanding askpass prompt text |
| `operationLog` | `List<OperationRecord>` | newest-last, capped at 500 |
| `lastBlame` | `BlameResult?` | blame result for a file |
| `commitMetaCache` | `Map<String, CommitMeta>` | author/subject/body keyed by OID; merged via `{...state.commitMetaCache, ...new}` as the viewport scrolls, never replaced wholesale |
| `lastFileHistory` | `List<FileHistoryEntry>` | file history for a path |
| `lastLineHistory` | `List<LineHistoryChunk>` | line history for a range |
| `lastReflog` | `List<ReflogEntry>` | newest-first |
| `undoJournal` | `List<UndoEntry>` | oldest-first, refreshed post-operation |
| `lastCleanPreview` | `List<CleanEntry>` | `git clean --dry-run` output |
| `lastRebasePlan` | `List<RebaseTodoEntry>` | oldest-first interactive rebase plan |
| `submodules` | `List<SubmoduleInfo>` | submodule list + status |
| `bisectStatus` | `BisectStatus` | current bisect state |
| `lfsInstallation` | `LfsInstallation?` | null until first `refreshLfs()` |
| `lfsPatterns` | `List<String>` | LFS-tracked patterns |
| `lfsFiles` | `List<LfsFileInfo>` | LFS file status |
| `localIdentity` | `LocalIdentity` | local git config user.name/email |
| `effectiveIdentity` | `EffectiveIdentity` | local or global identity in effect |
| `hasCommitGraph` | `bool` | commit-graph file exists on disk |
| `lastCommitGraphWriteSucceeded` | `bool?` | null until first write |
| `checkoutChoices` | `List<OperationChoice>` | recovery choices from a failed checkout |
| `deleteBranchChoices` | `List<OperationChoice>` | recovery choices from a failed branch delete |
| `commitFiles` | `List<ChangedFile>` | changed-files list for the selected commit |
| `selectedCommitFileDiff` | `ParsedDiff?` | diff for one file within the selected commit |
| `compareResults` | `Map<String, CompareResult>` | Compare tab results, keyed by tab |
| `compareFileDiffResults` | `Map<String, CompareFileDiffResult>` | per-file diff within a Compare tab |
| `lastRemotePrunePreview` | `RemotePrunePreview?` | `git remote prune --dry-run` preview |
| `compareWithWorkingCopyResults` | `Map<String, CompareWithWorkingCopyResult>` | Compare tab results against the working copy |
| `originalOperationMessage` | `String?` | original commit message read mid-conflict (see `gbm_*_continue_with_message`) |
| `gonePendingByRemote` | `Map<String, List<String>>` | remote name → full names of its remote-tracking refs that no longer exist upstream; accumulated per remote from `git remote prune --dry-run` (never replaced wholesale — `fetch --all` fires one preview per remote and the replies race). Distinct from `lastRemotePrunePreview`, which stays last-write-wins for the Prune dialog |

Plus two derived getters, not fields.

The single source of truth for conflict state, read by every conflict-aware
surface and by `lib/actions/gbm_action_availability.dart` (see "Action
availability state machine" below):

```dart
bool get conflictActive =>
    (repoState?.isSequencerOperation ?? false) ||
    workingCopyStatus.conflicted.isNotEmpty;
```

And the flattened gone-pending set — the only form UI code should read, since
no surface cares which remote a stale ref came from:

```dart
Set<String> get gonePendingRefs =>
    gonePendingByRemote.values.expand((refs) => refs).toSet();
```

Neither `gonePendingRefs` nor `RefInfo.isGone` is read directly by a render
site: both go through `features/sidebar/gone_marking.dart`'s
`isEffectivelyGone()`, so the sidebar rows, the bulk-select set and the status
bar cannot disagree about whether a branch is gone.

### Lifecycle

```
closed --(RepoSessionController ctor calls sessionOpen())--> opening
opening --(handle allocated, event stream subscribed)--> open
open --(last watcher unmounts, e.g. every child route under the repo's
         ShellRoute is popped)--> disposed (sessionClose())
```

`isOpen`, `isRefreshing`, `repoState`, `workingCopyStatus.conflicted`,
`credentialPrompt`, `checkoutChoices` and `deleteBranchChoices` are
independent flags layered on top of `open`, not separate top-level phases —
e.g. a session can be `open`, not refreshing, mid-merge
(`workingCopyStatus.conflicted` non-empty) *and* have `credentialPrompt` set
(a push during conflict resolution asked for a password) at the same time.
The provider is a Riverpod family keyed by `RepoIdentity`; disposal is
automatic, not manually triggered by any view.

### FFI events → state (`GbmEventType`, `gbm_bindings.dart`, values 0–33)

| # | Event | # | Event |
|---|---|---|---|
| 0 | graphUpdated | 17 | rebasePlanReady |
| 1 | refsUpdated | 18 | submodulesUpdated |
| 2 | errorOccurred | 19 | bisectStatusUpdated |
| 3 | operationFinished | 20 | lfsUpdated |
| 4 | workingCopyStatusUpdated | 21 | cleanPreviewReady |
| 5 | workingCopyOperationFinished | 22 | localIdentityUpdated |
| 6 | workingCopyDiffReady | 23 | effectiveIdentityUpdated |
| 7 | stashesUpdated | 24 | commitGraphWriteFinished |
| 8 | stashDiffReady | 25 | workingTreeContentReady |
| 9 | worktreesUpdated | 26 | commitMetaReady |
| 10 | remotesUpdated | 27 | commitFilesReady |
| 11 | credentialRequested | 28 | commitFileDiffReady |
| 12 | operationLogRecord | 29 | compareReady |
| 13 | blameReady | 30 | compareFileDiffReady |
| 14 | fileHistoryReady | 31 | remotePrunePreviewReady |
| 15 | lineHistoryReady | 32 | compareWithWorkingCopyReady |
| 16 | reflogReady | 33 | originalOperationMessageReady |

`event_dispatcher.dart` is a thin bridge only: a `NativeCallable.listener`
copies each native event's payload bytes (avoiding dangling pointers), frees
the native buffer, and pushes a `GbmEvent` onto a broadcast `Stream`. All
per-event-type interpretation — which of the 34 event types updates which
`RepoSessionState` field — lives in `RepoSessionController._onEvent()` inside
`repo_session_repository.dart`, one `copyWith()` per case.

### Credential and recovery flows

- **Credential prompt**: `credentialRequested` sets `credentialPrompt`.
  `WorkspaceScreen` auto-pushes `/repo/:repoId/dialogs/credential` on the
  `null -> non-null` transition (not user-initiated, unlike every other
  dialog route). Cleared by `provideCredential(secret)` or
  `cancelCredential()`.
- **Checkout recovery**: a checkout refused on a dirty work tree returns
  `choices` on the operation outcome; `WorkspaceScreen` auto-pushes the
  checkout-recovery dialog on `[] -> non-empty`. `retryCheckoutWithChoice(kind)`
  resubmits with the chosen recovery (stash-first / force);
  `dismissCheckoutChoices()` clears without retrying.
- **Delete-branch recovery**: same pattern for a delete refused because the
  branch isn't fully merged — `retryDeleteBranchWithChoice(kind)` /
  `dismissDeleteBranchChoices()`.

### Intent / Action layer

`lib/actions/` holds three pure-data files with no Riverpod/FFI dependency:
`gbm_action_id.dart` (the `GbmActionId` enum, 64 values), `gbm_menu_model.dart`
(the menu-bar/label/shortcut-string model `MenuBarRow` and the keyboard
shortcuts dialog both read), and `gbm_shortcuts.dart`
(`GbmActionId -> GbmKeyboardShortcut`, platform-aware Cmd/Ctrl binding).

A `GbmActionId` is dispatched by three independent paths, which **must all
read the same `Map<GbmActionId, VoidCallback?> actionHandlers`** — the one
`WorkspaceScreen._buildActionHandlers()` builds once per build and hands to
all three:

1. **Keyboard** — `WorkspaceActionShortcuts` (`workspace_action_shortcuts.dart`)
   wraps the shell in `Shortcuts` + `Actions`; a bound key press dispatches a
   `GbmActionIntent(id)`, whose `CallbackAction` calls `handlers[id]?.call()`.
2. **macOS system menu bar** — `PlatformMenuBarHost` builds a real
   `PlatformMenuBar` from the same map; `PlatformMenuItem(onSelected:
   handlers[item.id])` — a `null` value is what makes macOS grey the item
   out natively.
3. **In-window menu** — `MenuBarRow` (rendered instead of (2) on non-macOS,
   spec page 01) resolves most ids via `Actions.maybeInvoke(context,
   GbmActionIntent(id))`, which reaches the same `Actions` block as (1). Five
   ids (`repositoryFetch`/`Pull`/`Push`, `viewToggleSidebar`, `fileExit`) are
   special-cased to named constructor params instead, because their
   real implementation predates the shared-map refactor and still lives
   there — see `MenuBarRow._resolveHandler`'s doc comment.

**A real, previously-shipped bug came directly from breaking this
invariant**: `_buildActionHandlers()` once hardcoded `repositoryFetch`/
`Pull`/`Push`/`viewToggleSidebar` to `null` in the map "because MenuBarRow
handles them via its own params" — which made the in-window menu click work
(path 3 bypasses the map for those ids) while the keyboard shortcut and the
macOS menu item (paths 1–2, which both read the map directly) silently
no-op'd. `test/integration/workspace_intent_dispatch_parity_test.dart`
exists specifically to catch a regression of this shape. **Rule**: when
wiring or changing what a `GbmActionId` does, change
`_buildActionHandlers()` (or the policy function below it calls) — never
add a fix that only touches `MenuBarRow`'s named params.

**An action whose meaning depends on a mode must read the mode, not assume
it.** Amend is a mode (`WorkingCopyDraft.amending`), so `repositoryCommit`
passes `amend: amending` rather than a hardcoded `false` — otherwise
`Ctrl/Cmd+Enter` writes a second commit while the button in front of the user
says `Amend`. The mirror case matters more: `repositoryAmendLastCommit`
*enters* the mode when it is off, instead of rewriting HEAD sight-unseen.
Both live in `workspace_screen.dart`; `beginAmendMode()` and `submitCommit()`
in `working_copy_repository.dart` are the single sources the box's buttons
call too.

### Action availability state machine

`lib/actions/gbm_action_availability.dart`'s `isActionEnabled(GbmActionId,
RepoSessionState)` is the single source of truth for which actions a
state-dependent gate disables — every other call site (`workspace_screen.dart`'s
`_buildActionHandlers()`, `sidebar_panel.dart`'s `BranchTreeItem.conflictActive`,
`working_copy_view.dart`'s commit-box `canCommit`, `MenuBarRow`'s
`GbmMenuItem.enabled` grey-out, and `ActionToolbar`'s five buttons, which take
their `null`-means-disabled straight out of the handler map) reads through this
function rather than re-deriving `session.conflictActive` locally.

Twelve ids are gated straight off spec page 07's STATES table — disabled
whenever `RepoSessionState.conflictActive` is true, because each would move
HEAD, start a second sequencer operation, or commit while one is already in
progress: `repositoryFetch`, `repositoryPull`, `repositoryPush`,
`remoteFetchAllRemotes`, `repositoryCommit`, `repositoryAmendLastCommit`,
`branchNewBranch`, `branchCheckout`, `branchMergeIntoCurrent`,
`branchRebaseOnto`, `branchStashChanges`, `branchDeleteBranch`. The banner's
Abort/Skip/Continue/Resolve… stay the only way forward until then.

Two more gates are folded into the same function despite **not** being from
spec page 07 — kept there anyway so every state-dependent availability
decision in the app lives in exactly one place, not because they share the
conflict/clean distinction the twelve above do:

- `branchRenameCurrentBranch` — additionally requires
  `refs.head.branchName.isNotEmpty` (a detached HEAD has no branch to rename).
- `repositoryStageAll` — `workingCopyStatus.unstaged.isNotEmpty` only,
  independent of `conflictActive` entirely (nothing to stage with an empty
  unstaged list, regardless of conflict state).

Every id the switch doesn't cover returns `true` — read that as "the state
machine does not forbid this," not "this is implemented" (see
`_buildActionHandlers()`'s own null entries for ids with no backing feature).

### Testing tiers

- **Unit** (`test/actions/gbm_action_availability_test.dart`, and pure-model
  tests elsewhere) — no widgets, no Riverpod. Exercises `isActionEnabled()`
  directly against every id + a representative `RepoSessionState`.
- **Widget** (`test/features/**/*_test.dart`) — a single presentational
  widget (`MenuBarRow`, `TabRow`, `BranchTreeItem`, ...) pumped with plain
  callbacks/`ProviderContainer` overrides and a fake session, per-widget in
  isolation. This is where most of the suite lives, and it cannot catch a
  dispatch-path bug like the one above, because it never goes through
  `WorkspaceScreen._buildActionHandlers()` — it feeds a handler map (or
  named callback) directly to the widget under test.
- **Integration** (`test/integration/`, run by the same `flutter test`, no
  separate `integration_test/` device harness) — the real
  `WorkspaceScreen` behind a `GoRouter`, driven by
  `test/support/pump_workspace.dart`'s `pumpWorkspace()`. Exists
  specifically to cross the seam widget tests can't: does a keyboard
  shortcut/menu click/system-menu path really reach the controller, does a
  state transition (conflict ↔ clean, an interrupt overlay opening) leave
  every gated surface consistent with no residue, does navigating into
  `ConflictResolveWindow` and back preserve the right content. Use
  `pumpWorkspace`'s `extraRoutes` for a route that's a ShellRoute child in
  the real router (Compare tab) and `topLevelRoutes` for one that's a
  sibling of it (any `dialogRoute(...)`, `conflicts`) — mixing them up tests
  the wrong route structure and can pass for the wrong reason.

**Fake session seam** (`test/support/fake_repo_session.dart`):
`FakeRepoSessionController extends RepoSessionController`, constructed with
a `FakeGbmBindings` whose `sessionOpen()` returns `nullptr` — the real
`_open()` sees that as "open failed" and returns before touching bindings or
recents again, so every controller method the fake doesn't override hits its
own `if (_session == nullptr) return;` guard and safely no-ops. Overridden
methods do the opposite: they record the call into `commandLog` (or a
bespoke field, for the handful of tests written before `commandLog` existed)
instead of no-opping. `FakeGbmBindings`/`FakeRecentsRepository` throw via
`noSuchMethod` on anything not explicitly implemented — a provider a test
forgot to override fails loudly instead of quietly reaching a real
`.dylib`/`.so`. Call `controller.emit(nextState)` to simulate an FFI event
publishing a new `RepoSessionState`, exactly as `_onEvent()` would.

**Rule**: a new state-dependent gate goes into `isActionEnabled()` (or, if
it's not action-shaped, gets an equally-named single function) *and* gets an
integration test asserting the gated surface actually changes when the
state transitions — a widget test alone proves the widget renders `null`
correctly, not that the real dispatch path ever produces that `null`.

## UX Goals

Evaluated with the `product-design-harness` UX3 framework (User Flow led;
Business/Evidence Flow lightly weighted — this is an internal tool's
usability pass, not a stakeholder business decision), Standard Gate mode.
**Evidence tier: T2** — static code analysis plus reachability/step-count
inspection, not moderated user testing. Treat the scores below as a
code-verifiable floor, not a substitute for real usability testing before a
1.0 release.

### Scoring rubric (100 pts)

| Dimension | Weight | What's measured |
|---|---|---|
| A. High-frequency action reachability | 30 | stage/unstage, commit, checkout, fetch/pull/push, view diff, switch pane — each should be reachable in ≤2 steps |
| B. Full-action discoverability | 25 | Every feature in docs/FEATURES.md has a UI entry point (menu / context menu / shortcut); no orphaned routes |
| C. Step efficiency | 25 | Sampled flows (merge, cherry-pick, stash, conflict resolve, bulk branch delete) measured against comparable desktop Git clients |
| D. View necessity & information architecture | 20 | No redundant views; no *hidden material state* — see `ux3.rule.human_factors_load` |

### Score trajectory

| Round | A | B | C | D | Total | Change |
|---|---|---|---|---|---|---|
| 0 (baseline) | 27/30 | 20/25 | 22/25 | 15/20 | 84/100 | — |
| 1 | 29/30 | 24/25 | 24/25 | 18/20 | **95/100** | +11 |

Stop condition (≥90) met after one round; the two-consecutive-round plateau
safety-stop was never triggered.

**What actually changed in Round 1** — most of the delta was correcting
Round 0's unverified assumptions, not new code, and that's disclosed
deliberately rather than let the number imply more work happened than did:

1. *Real fix (D, +3)*: `TabRow`'s Working Copy tab was plain text with no
   signal that changes were pending while the user was looking at History —
   a `material_state_hidden` violation of `ux3.rule.human_factors_load`.
   Added a `GbmBadge` count badge sourced from
   `session.workingCopyStatus.entries.length`. Extracted
   `_TabRow`/`_Tab`/`_MoreMenu` into
   `features/workspace/widgets/tab_row.dart` (mirroring the
   `MenuBarRow`/`ActionToolbar` presentational split) so it's independently
   testable; 4 new widget tests in `tab_row_test.dart`.
2. *Corrected assumption (A, +2)*: Round 0 assumed a missing "checkout
   commit" affordance from History cost points. Grepping `history_graph/`
   found no such feature anywhere in the code or docs/FEATURES.md — it was
   never in product scope, not a discoverability gap.
3. *Corrected assumption (B, +4)*: Round 0 assumed some of the dialog routes
   might be orphaned. A full audit (not sampling) found zero: see the route
   tree section above.
4. *Corrected assumption (C, +2)*: Round 0 estimated bulk "delete gone
   branches" at 3–4 steps. Reading `sidebar_panel.dart` showed it's 2 steps
   (select-all-gone icon → Delete), with no intermediate confirmation dialog.

## Invariants and traps

Distilled from [docs/ledger.md](docs/ledger.md) — every entry here happened,
and the round that found it is named so the original measurement, the
counter-example and the issue number stay one grep away. Organised by what
you are touching, not by when it was learned.

### Toolchain and CI

- Flutter with **Dart ≥ 3.12.2** (`app_flutter/pubspec.yaml`'s `sdk: ^3.12.2`);
  Flutter 3.44.x ships it.
- **`flutter analyze` must stay at zero issues.** CI runs it with no tolerance
  flags and it exits non-zero on *info*-level lints too.
- CI is split: `ci.yml` builds and tests (the Flutter UI job sits behind
  `needs: capi-build`, so it does not run at all while any capi job is red —
  a green capi run can surface Flutter problems that were previously
  invisible rather than absent); `cq.yml` holds the two pure static checks,
  `dart format --set-exit-if-changed .` and `clang-format`, so a format
  failure surfaces on its own check instead of aborting the build job.
- **Both formatters drift by version, in both directions.** `dart format`'s
  output is not stable across Dart SDKs and `subosito/flutter-action@v2`'s
  `channel: stable` floats with no SDK pinned, so a file can flap between two
  valid formattings. `clang-format` is pinned to v18 in `cq.yml` and
  `.pre-commit-config.yaml`; a local v22 reformats lines v18 left alone.
  Never run either wholesale — restore the file, re-apply only the intended
  edit, and check the new lines survive byte-for-byte. But check
  `.clang-format` first: a suggestion coming from the repo's own config
  (e.g. `SeparateDefinitionBlocks: Always`, an option since v14) applies to
  CI's v18 too and is safe to take.
- **PR CI compiles Linux only** (`flutter build linux --debug`).
  `windows/runner/` and `macos/Runner/` are built by nothing until a release
  tag — assume any edit there reaches `main` uncompiled (**#69**).
  `test/platform/window_title_test.dart` asserts those runner sources as
  strings, which catches a drifting literal but never a compile error.
- **Windows refuses to rename or delete any process's current working
  directory**, and `Process.start` inherits the parent's when given no
  `workingDirectory`. An app launched by double-clicking its `.exe` has the
  install directory as its CWD, so the detached updater stood inside the very
  folder it then tried to move aside — `Move-Item` lost every retry and the
  self-install died silently with the app already gone. POSIX permits the
  rename, so macOS and Linux never showed it. Any detached process that will
  touch the install tree must be given an explicit `workingDirectory` outside
  it; inside a PowerShell script, `Set-Location` alone is **not** enough —
  it moves the provider location while the Win32 process directory (the one
  holding the handle) stays put, so `[System.Environment]::CurrentDirectory`
  has to be assigned too (ledger: 更新流程的三個缺陷).
- **`powershell.exe` reads a BOM-less `.ps1` as ANSI, not UTF-8.** Windows
  PowerShell 5.1 is what `-File` resolves to on a stock machine, and the
  updater bakes its three paths in as literals — a user name in Chinese was
  enough to mojibake all of them into the same silent failure. Write generated
  `.ps1` as UTF-8 **with** a BOM; `sh` needs the opposite (a BOM on line 1 is
  a syntax error), so the two generators differ deliberately.

### Tests and fixtures

- **A fixture that cannot disagree with the code proves nothing.** Four
  recorded shapes, each of which passed identically before and after a real
  fix: a fixture that *derives* one field from another
  (`hasTrackingInfo: upstream.isNotEmpty`, Tier 0c); one *borrowed* from a
  test whose subject contradicts yours (`_mergeState()`'s
  `isSequencerOperation`, cancel-surface round); one that *cannot express*
  the case at all (a single shared `GraphRow` instance, graph-edge round);
  one that *cannot shrink* (a `repoRefsProvider` override pinned to one
  snapshot, so no selected branch can ever vanish); and one whose *two
  subjects are indistinguishable to the assertion* — `ActionToolbar`'s Branch
  and Stash share a gate and both only `context.push(...)`, so asserting
  `onPressed != null` stayed green with the two handlers swapped (P02-2
  round). Sentinel `dialogRoute`s are what told them apart. A sixth: one whose
  *content contradicts its own name* — a "same-size edit must be re-read" test
  wrote 8 bytes then 7, so the mutation that removes mtime from the cache key
  stayed green because size really had changed (C18). Count the bytes the
  fixture actually writes, not the bytes the test's name claims. A seventh:
  one whose *premise a later decision revoked* — 05-G's device fixture put
  its two insertions one line apart, which was "two separate changes" until
  變體 B made the default scope merge anything ≤ 2 unchanged lines apart, at
  which point the same bytes meant *one* scope and the line-granularity test
  was silently testing something else (C18). **When a rule about how input is
  grouped changes, every fixture that encodes a gap, a count or an adjacency
  has to be re-read against the new rule** — nothing else will notice. An
  eighth is not a fixture at all but the *assertion*: one weak enough that
  both candidate implementations satisfy it. «the controls are to the right
  of the status text» is true under `WrapAlignment.spaceBetween` **and**
  under `start`, so the mutation between them stayed green; «the controls'
  right edge equals the Wrap's right edge» is the same claim stated tightly
  enough to fail (conflict-banner round). A mutation that comes back green
  is as often a weak assertion as a missing one.
- **Mutation-check every new test**, and check the red is *narrow* — a broad
  red means the test is pinning something else. Copy the file to the
  scratchpad first (`cp file "$SCRATCH/x.bak"` → mutate → `cp` back);
  **never `git checkout -- <file>`** to revert a mutation, which once
  discarded an entire uncommitted implementation. Have the mutation script
  assert `count(old) == 1` before writing — two mutations in one round
  silently matched nothing after a formatter reflowed an argument list, and a
  `JsonCodec.cpp` anchor named only by its field matched **two** serializers
  (`DiffFile`'s and `ChangedFile`'s both emit `addedLines`). Anchor on a
  neighbouring line that is actually unique.
- **Count, don't `any`.** `commandLog.where((c) => c.name == …).length` —
  `.any(...)` is blind to a double dispatch, which is exactly what several
  of these fixes could regress into.
- **The default widget-test canvas is 800×600**, and a `SizedBox` wider than
  it is silently clamped. A widget test that sizes its own canvas proves
  nothing about layout under real constraints, and a placement bug is
  invisible to any tier whose canvas is bigger than the real window (the
  column-picker popover shipped off-screen for exactly this reason; later, a
  deliberate overflow in the Changed files row was caught **only** by the one
  test sized to `GbmLayout.splitterMainFiles.defaultExtent` — three others on
  the default canvas passed with the broken layout). Compounding it:
  **`flutter_test`'s default font draws every glyph `fontSize` wide**, so a
  42-character status line measures 548px in a test where the real
  proportional font is far narrower. Any width a widget test measures or
  asserts is in test-font terms; say so next to the number, and pick which
  direction the distortion is safe in (a banner asserted to wrap at 440px
  wraps at a *narrower* real window, which is the harmless direction).
  A recorded pixel figure taken this way is not portable between fixtures
  either — an audit's «overflows by 6.3px» measured 27px on a different
  session shape, and the gap changed the fix from «move one child to its own
  run» to «both levels have to wrap».
- **`RenderFlex` reports only main-axis overflow**, so a `takeException()`
  test cannot see a cross-axis defect. Check which axis the defect is on
  before writing a no-exception test.
- **Never `pumpAndSettle()` while an indeterminate `CircularProgressIndicator`
  is on screen** — it schedules frames forever, so `pumpAndSettle` can only
  time out. This is the confirmed mechanism behind the device-tier batch
  flake (**#101**), and it is *not* **#70** (a fixed 10s C++ `waitFor` budget
  losing to parallel load) — read the failure text before picking a family.
  The rule used to name `top_bar.dart`'s `isRefreshing` spinner; that file is
  deleted and the trap is now **narrower and elsewhere** —
  `CommitGraphView` draws one only while `isRefreshing && graph.rows.isEmpty`,
  `ScopedDiffView` while a diff request is in flight, and eight panels for
  their own loads. `StatusBar` is *not* one of them: `BackgroundTask.progress`
  is never null, so its `LinearProgressIndicator` is always determinate.
- `StatusBar` lingers a finished task for 3 seconds (`_lingerTimer`), so
  "the task cleared" cannot be asserted on the next frame.
- **Real async inside `testWidgets` needs `tester.runAsync()`.**
  `Picture.toImage()` (and asset decoding through `vg.loadPicture`) never
  completes in flutter_test's fake-async zone: no output, no timeout of its
  own, just a hang — eight minutes of silence in the recorded case. This is
  how an asset-rendering check is written when a string-level "it ships and
  parses" assertion is not enough (`docs/ledger.md`, P02 item 2's toolbar).
- **The fake seam fails loudly on purpose.** `FakeGbmBindings` /
  `FakeRecentsRepository` throw via `noSuchMethod` for anything not
  explicitly implemented, so a provider a test forgot to override never
  silently reaches a real `.dylib`. The opposite risk is inside
  `RepoSessionController`: a method the fake does not override hits its own
  `if (_session == nullptr) return;` guard and **no-ops silently**, so a
  test cannot tell a dead button from a dispatched one until that method is
  overridden to record into `commandLog`.
- **Device tier (`integration_test/`) runs one file at a time per platform**
  (`-d macos` / `-d linux` / `-d windows`); the whole directory in one
  command is unreliable. Never reduce a device batch's output to `tail -1` —
  on failure the last line is the *test name*, not the error. Never edit
  `lib/` while a device run is in flight: each run recompiles from the
  working tree, so a green from such a run attests nothing. A stale
  `gbm_flutter` process blocks the entire tier and looks exactly like a
  broken test — `pkill -f "gbm_flutter.app/Contents/MacOS/gbm_flutter"`, and
  run one pre-existing device test as a control before believing a new one.
  **Run the control on the *parent commit*, not just on a different test.** A
  device failure here can be entirely pre-existing: soft-warp's
  `stage_lines_flow_test` hung on test 4 after 7m50s, and the same file on the
  commit *before* the round died at test 2 in 25s — both with `Failed to
  foreground app; open returned 1`. The honest conclusion is "the tier cannot
  attest anything this session", which is neither "green" nor "I broke it";
  reaching it costs one detached-HEAD run.
- **The device tier is in no CI job and is not part of `flutter test`**, so a
  UI redesign can leave it broken for rounds with every other tier green. C18
  swept all ten files and found two red — neither from that round's own
  commits, both from the Working Copy redesign four rounds earlier: a test
  still tapping a deleted checkbox, and two finders that a new titlebar had
  made ambiguous. **A round that removes or replaces a user affordance owns
  grepping `integration_test/` for it**, the same way it owns `lib/`.
- `build/native/libgbm_capi.dylib` is a **copy**: a stale one loads happily,
  and a new capi entry point then appears to be a Dart bug. A stale one is
  *three days old and silent* in practice — C18 found one predating that
  round's own capi fields, where the symptom was a badge that simply never
  rendered, not an error of any kind. Run `app_flutter/scripts/build_capi.sh`
  before any device-tier run that is meant to attest a capi change.
- **`dart:ffi`'s `lookupFunction` matches by symbol name only, never by
  signature.** Changing a capi parameter list and its Dart typedef in
  lockstep is checked by nothing — it compiles, analyzes and unit-tests
  clean, then corrupts the stack at runtime. Only a device-tier test crosses
  that seam.
- `pumpRealAppOn` clears `panelLayout.*` and `graphColumns.*`, because device
  tests share the machine's real `shared_preferences` — a splitter ratio or a
  hidden column the developer once set silently changes what later tests
  render.
- **A memory-ordering race *is* falsifiable here.** `CMakeLists.txt`'s
  `GBM_SANITIZE` option and the configured `build/tsan` / `build/asan-ubsan`
  presets turn "a race in principle" into a test:
  `cmake --build build/tsan --target gbm_capi_tests`. A *timing* race
  (**#70**, **#77**) still cannot be reproduced on demand — its evidence is a
  deterministic mechanism test plus the causal chain, never an A/B.
- Swapping a widget for a design-system one can break device-tier finders
  nothing else uses (`find.byType(ListTile)` → `GbmRow`), so a round touching
  shared row widgets has to rerun all device tests, one at a time.
- **Asserting that a `Draggable` exists is not asserting that a drop works**,
  and the gap between them is where a shipped defect lived: the Working Copy
  board's empty column drew its "No staged changes" placeholder *instead of*
  the `DragTarget`, so the one column every repository starts with could not
  be dropped on — and with 變體 B's checkboxes gone, dragging is the only way
  a file changes side. An empty-state placeholder belongs **inside** the
  target's builder, never in place of it. The gesture recipe that actually
  drops in a widget test is `startGesture` → `pump()` → `moveTo(target)` →
  `pump()` → `up()` → `pump()`; extra intermediate moves are not needed.
- **A pointer drag can never carry `PointerDeviceKind.trackpad`, so "test the
  trackpad path" is not a thing you do by changing the kind.**
  `PointerDownEvent`, `PointerMoveEvent`, `PointerUpEvent`, `PointerCancelEvent`
  and the two hover events each assert `kind != PointerDeviceKind.trackpad` in
  their own constructor, and `TestGesture.moveTo` asserts it again — the kind is
  reserved for `PointerPanZoom*` (two-finger pan/zoom), which is also the only
  route by which it reaches the `dragDevices` set (`_kTouchLikeDeviceTypes`)
  it is a member of. A trackpad **click and drag** must therefore arrive as
  one of the permitted kinds — `mouse`, on macOS — so a mouse-kind synthetic
  drag already *is* the trackpad path. This killed an otherwise well-evidenced hypothesis — that four green
  mutations of the Working Copy's mid-drag gate were green only because the
  synthetic drag never said "trackpad" while the reporting user's did (ledger:
  「因為我是用觸控板」). The kinds a drag *can* vary over change hit/pan slop
  and scrollable claiming (`mouse` vs `touch`), and that is a different claim
  from the one hardware makes.
  **The same two facts settle whether a `Scrollable` competes with a drag, and
  they cut the opposite way from the obvious guess.** `ScrollBehavior.dragDevices`
  defaults to `_kTouchLikeDeviceTypes`, which **has no `mouse` in it** — so a
  scroller never contests a desktop selection drag, and "protecting" the
  selection by clearing that set is unnecessary. It is also actively harmful:
  trackpad two-finger pan reaches a `Scrollable` *through* membership of that
  very set, so an empty set deletes the main scroll input and leaves only the
  scrollbar thumb and Shift+wheel. Never override `dragDevices` to guard a
  selection; `gbm_code_hscroll_test.dart` pins the premise with a mouse-kind
  drag that must **not** scroll (ledger: soft-warp).

### Flutter, Riverpod and widgets

- **`addPostFrameCallback` does not ask for a frame.** It registers a callback
  for the end of the *next* frame, and if nothing else schedules one the
  callback simply never runs. A drag hides this — the drag itself keeps
  frames coming — so a notification coalesced onto a post-frame callback can
  work for months and then not arrive at all the first time a plain click
  drives it (`selection_touch.dart`'s `_scheduleNotify`; the scope a
  hunk-heading click had already recorded stayed invisible). In a widget test
  the gap is total rather than intermittent, because `tester.pump()` runs a
  frame only `if (hasScheduledFrame)` — six pumps in a row did nothing.
  Pair every deferred notification with
  `SchedulerBinding.instance.ensureVisualUpdate()`.
- **`ref` inside a `ConsumerState.dispose()` always throws.**
  `_assertNotDisposed()` gates every `ref` member on `context.mounted`, and
  the element is already unmounted by then. Capture the notifier in
  `initState()` into a field and guard on `StateNotifier.mounted`.
- **Never write a provider from `build()`.** Riverpod's guard is
  `assert`-wrapped, so debug crashes but **release strips it and lets the
  write land mid-frame**. Defer to a post-frame callback and recompute from
  then-current state, not from a captured list.
- **`ref.listen` never fires for the value already present when it
  registers.** Every `ref.listen`-driven piece of session state needs
  something else covering the value that was already there — a filter query
  surviving a repository close is the recorded case. The test that sees it is
  the one that seeds the provider *before* pumping.
- **An entry point gated on one resting state replays stale answers forever
  once the machine has terminal states.** The update dialog checked on mount
  only from `idle`, but `upToDate` / `failed` / `developmentBuild` are
  terminal — nothing returns them to `idle` — so re-opening it re-showed the
  previous answer for the rest of the session. Gate on a *named predicate*
  over the whole enum (`UpdateState.wantsFreshCheck`) rather than on one
  value, and check whether every state the machine can rest in has a way
  out. Note the partition is rarely two-way: a **standing offer** the user
  has not acted on is neither stale nor in-flight, and refreshing it costs an
  API call on the commonest path. Where a `ref.listen` fills the remaining
  gap, key it on the specific *transition*, never on "arrived at X" — `idle`
  is also where `dismiss()` lands, and re-checking there re-offers the very
  thing the user just declined (ledger: 更新流程的三個缺陷).
- **A finder proves existence, never position.** `TabRow` shipped spanning
  the whole window, covering the sidebar, and all **2039** tests stayed green
  through the fix — not one asserted where it was. Assert `getRect()` against
  a *neighbour's* rect (「left edge not before the sidebar's right edge」),
  never against a pixel constant, and never `findsOneWidget` for a layout
  claim (ledger: "Working Copy 重新設計"). **One level deeper: the right finder
  can still resolve to the wrong render object.** `find.byType(X)` takes X's
  first descendant RenderBox, and if that is a `RenderTransform` — or any
  render object whose effect applies to its *children* — `localToGlobal`
  reports the untransformed position, so a pinned widget measures as if it
  never moved and the test goes red while the code is correct. Measure a node
  *below* the transform. Corollary for clipping: `ClipRect` does not change
  `getRect` at all, so a clip's geometry can only be asserted by asking its
  `CustomClipper` directly (ledger: soft-warp).
- **`RenderFlex` lays out non-flex children first**, then divides what is
  left — so a `Flexible` child can never rescue an overflow that non-flex
  children caused. Six surfaces overflowed at the app's own default 1280×720
  for exactly this. Related: `Spacer` is itself a flex child and competes for
  the space it looks like it is donating; and `Expanded` satisfies "no
  overflow" while collapsing its child to zero, so assert visibility, not
  absence of exception.
- Tapping an `InkWell` does **not** give it focus — call `requestFocus()`
  first if a focus-scoped shortcut has to work after a click. In the sidebar
  that call lives in `_onBranchSelect`, so it now runs on *every* click; the
  clause that used to be here ("a plain click on a branch row routes through
  checkout") stopped being true when single-click became selection.
- **A hand-rolled `InkWell` silently inherits `ThemeData.hoverColor`** — about
  4% black/white, invisible on a real display. `lib/widgets/gbm_row.dart`
  exists to pass `surfaceHover`/`surfaceSelected` for you; the sidebar shipped
  with no visible hover for months because its row built its own `Container` +
  `InkWell` instead (ledger: "Sidebar branch rows"). Reach for `GbmRow` for
  anything row-shaped, and assert the token by identity — hover cannot be
  proven by a widget test that only checks for no exception. It recurred twice
  more in C18, both found by *sweeping every `InkWell(`/`GestureDetector(` in
  the round's changed files*: `FileTreeFolderRow` (folder rows had no hover
  while the file rows around them in the same list did) and a private
  `_MiniButton` in `working_copy_view.dart` that also re-implemented
  `GbmButton(secondary, sm)`'s border, text size and padding by hand. That
  grep is worth running at the end of any round that touches widgets.
- **The gesture arena taxes double-clickable rows, and it is not local.** An
  `InkWell` holding both `onTap` and `onDoubleTap` withholds the tap for
  `kDoubleTapTimeout` (~300ms), and a `DoubleTapGestureRecognizer` anywhere on
  the *ancestor* path does the same to every child button underneath it — a
  row's own ⋯ button waits out the row's double-tap timer. Put an immediate
  action on `Listener(onPointerDown:)` (never enters the arena) and keep the
  double-tap on the narrowest subtree that needs it. `InkResponse` stays
  hover-enabled with no primary callback at all, because `isWidgetEnabled` is
  `_primaryButtonEnabled || _secondaryButtonEnabled` and `onSecondaryTapDown`
  satisfies the second half.
- **`SelectionArea` tells you the selected *string*, not which widgets it
  covers.** `selection_touch.dart` asks each row's own subtree via a
  `SelectionListener`, which brings three traps: a row moving between subtrees
  builds its new listener before the old unmounts (two listeners, one
  notifier, framework assert — give each row a stable `GlobalKey` so Flutter
  reparents one element); inserting a widget *among* keyed rows reparents
  everything below it and perturbs the selection, so a derived card takes a
  **fixed slot**; and reacting to every report is a feedback loop
  (`setState` → geometry moves → delegates re-report), so listen only between
  pointer-down and pointer-up. **Draw nothing derived from that set while the
  pointer is down**: the one-shot block sits inside the scope card, so
  drawing it mid-drag reparents the rows whose listeners are still reporting.
  The live feedback during a drag is `SelectionArea`'s own text highlight;
  the block is what the drag settles into, so `endGesture()` is what
  notifies. Note the honest limit — **no synthetic gesture at either tier
  reproduces the symptom this was reported for** (「只能選一行」): with the
  gate removed, row-by-row and sub-row device drags both stayed green. The
  invariant is pinned; the cure is not. All three are 「first frame right,
  later frames wrong」 — a one-frame assertion cannot see any of them. But note
  what the second one is *not* an argument for: the one-shot block's fixed
  slot at the top of the column was justified by it and **was not the
  design** (the demo nests it inside the scope card, wrapping the selected
  rows in place). What makes the nested form safe is the same sentence the
  hazard note rests on — those keys are `GlobalKey`s, so Flutter *moves* the
  element into its new parent rather than rebuilding it. A recorded hazard
  is a reason to solve the problem, not a licence to change the design. A fourth is
  not about frames at all: **the submit path is a diff-change path, one
  dispatch later.** `_dropSelection` documented that clearing the highlight
  is unsafe while the tree restructures, and staging *is* what restructures
  it — so a `clearSelection()` deferred to after the dispatch lands inside
  the restructure it caused and the framework throws
  ConcurrentModificationError out of `handleClearSelection`. Clear
  synchronously **before** dispatching. Nothing below the device tier can see
  it: the fakes never restage, so the diff never changes and the clear always
  finds a settled tree.
- **`SelectableRegion` clears its selection when it loses focus**
  (`_handleFocusChanged`, non-web), and it requests focus for itself as a
  drag begins — so an *ancestor* that calls `requestFocus()` on every pointer
  down is a live way to wipe out the selection the gesture is still making.
  Guard on `!node.hasFocus`: `hasFocus` is true for an ancestor of the
  primary focus, so the guard already covers "the region below me is the one
  holding it", and key events reach an ancestor `CallbackShortcuts` either
  way.
- **`Ctrl/Cmd+A` must be bound inside the list's own focus scope**, never
  app-wide: a `Shortcuts` closer to a focused editor than
  `DefaultTextEditingShortcuts` steals text select-all.
- **`GbmMenuItem.enabled: false` is only a visual signal** — set `onTap: null`
  too, or a "disabled" item still fires. Disabled-with-a-tooltip beats
  hidden: 隱藏會讓人以為功能不存在.
- `showGbmMenu` is built on Material's `showMenu`, whose modal barrier makes
  a hover-opened flyout unhoverable from its own parent — submenus open on
  tap, and the parent is popped *before* the child's action runs (menu items
  routinely push a dialog). **#87**.
- `RadioListTile` needs a `Material` ancestor; `Container(color:)` builds an
  opaque hit-test box while `Listener` defaults to `deferToChild`;
  `ReorderableDragStartListener` accepts at `kPrecisePointerHitSlop` (**1.0px**
  for a mouse), so a whole-row drag handle loses ordinary clicks.
- `Paint.color` quantises on read-back — compare `.toARGB32()`, or a mismatch
  prints Expected and Actual identically.
- **A widget that paints over a row to hide something has to know whose
  background it is covering.** `GbmPinnedGutter` holds a line-number gutter at
  the viewport edge while code scrolls under it, so it must be opaque — and
  opaque is right only when the row paints its own full-width background (a
  `DiffLineView` does). A `GbmRow` does not: its hover and selection tints are
  drawn by an *ancestor*, and an opaque strip covers them **at every scroll
  offset including zero**, silently killing hover feedback the way the sidebar
  once did. That case takes `opaque: false` + `GbmPinnedGutterClip`, which
  clips the content in viewport coordinates instead of painting over it. The
  rule lives on `GbmPinnedGutter.opaque`: own full-width background → opaque;
  ancestor-drawn background that must stay visible → clip (ledger: soft-warp).
- **Changing a `GbmSplitPane`'s axis obliges you to decide what happens to its
  stored value**; only ratio mode survives the change, extent mode persists a
  raw pixel number and must be re-keyed. Its fixed pane's end is the explicit
  `fixedPaneEnd`, not implied by the axis.

### Refs, git and the core's own vocabulary

- **`RefInfo.upstream` is the full ref name** (`refs/remotes/origin/x`), from
  `%(upstream)` not `%(upstream:short)`. Splitting on the first slash yields
  `"refs"` — use `remoteBranchParts()`. `delete_branch_dialog.dart`'s
  `_remoteOf()` still does the wrong split (**#74**).
- **`RefInfo.hasTrackingInfo` does not mean "has an upstream"** — it mirrors
  `%(upstream:track)`, which is *empty* for a branch exactly in sync. Ask
  "does this track a remote?" with `upstream`; reserve `hasTrackingInfo` for
  "did git report ahead/behind numbers".
- **`RefInfo.ahead` means nothing when `upstream` is empty** — a branch that
  never had one reports `0`, which rendered literally claims the opposite of
  the truth.
- **The current branch is pinned inside its own folder, by the tree's
  comparator.** `BRANCH_STATES`: 「永遠置頂於所屬資料夾內，且不受 filter
  影響」 — first among its *siblings*, not hoisted to row zero, and not only
  while filtering. It lives in `branch_tree_builder.dart`'s
  `_compareTreeNodes` because sorting a level is the only place that knows
  what "its own folder" means, and it outranks the folders-before-leaves rule
  (`BRANCH_TREE` draws `main` above the folders at its depth). The filter
  half is `sidebar_panel.dart` adding HEAD *back into the builder's input*
  when a query drops it — a row rendered outside the tree has no folder to
  sit in, which is exactly why the previous version had to hoist it. **P02-14
  rule 7's bare 「永遠置頂顯示」 does not overrule this**: `BRANCH_STATES` is
  the specific rule, so when a matching folder sorts before HEAD's folder,
  HEAD renders *second* and that is correct
  (`sidebar_current_branch_pin_test.dart` asserts it).
- **`RefInfo.isGone` can only be true after a prune** (git reports `[gone]`
  only once the remote-tracking ref is already deleted). Gone *marking* comes
  from `git remote prune --dry-run`, deliberately not from `fetch --prune` —
  the spec's three stages are mark → badge → explicit Prune, and `--prune`
  skips to the end. Read gone-ness through
  `features/sidebar/gone_marking.dart`'s `isEffectivelyGone()`, never
  `isGone` or `gonePendingRefs` directly.
- `RemotePrunePreviewEntry.ref` is a **short** name while `upstream` and a
  remote row's `fullName` are full — normalise through `fullRemoteRefName()`.
  Every *comparison* in this codebase is on the full form; the short form is
  display only.
- `git branch -m` **keeps** `branch.<name>.remote/.merge`, so a local-only
  rename needs an explicit `git branch --unset-upstream`.
- **`git diff-tree` silently ignores `--first-parent`** — the correct spelling
  is `--diff-merges=first-parent` (git 2.31+). `git log --raw` honours
  `diff.renames` while `git diff-tree --raw` ignores it entirely, so the
  rename flag is passed **explicitly on both** from one shared
  `rawRenameFlag()`.
- **git's diff output-format is a single slot**: `--raw` and `--numstat`
  cannot both take effect in one invocation, so a file list that needs kinds
  *and* line counts runs two commands and joins them by path
  (`DiffService::attachLineCounts()`, `CompareOps.cpp`'s `readFiles()`). The
  second command must repeat **every** flag the first passed — drop `--root`
  and root commits return nothing, drop `--diff-merges=first-parent` and
  merges return nothing, use a different rename flag and the two disagree
  about which paths exist. All three land as a row with no count and no error
  anywhere. Under `-z`, numstat spends **three** records on a rename (empty
  path field, old path, new path) where every other kind spends one, so a
  one-record-per-entry loop mis-reads every count after the first rename. Join
  on `path`, the only field `parseRawRecords()` fills for all kinds; `oldPath`
  is empty except for renames and copies. `-` means binary, not a number.
  Ledger: "Changed files line counts".
- **`WorkingCopyEntry`'s four line-count fields: `0` always means "not
  measured", never "measured zero".** `git status --porcelain=v2` reports no
  counts and git's diff output-format is a single slot, so they come from two
  extra `git diff --numstat -z` passes (work tree↔index, `--cached`) joined by
  path — and from **reading the file** for untracked paths, which `git diff`
  cannot see at all. Binary, mode-only, and untracked over **1 MiB** all land
  as 0 (the cap exists because `--untracked-files=all` enumerates every file
  in an unbuilt output directory). The UI draws no badge at 0 for exactly
  this reason. `-M` is passed explicitly to both passes rather than trusting
  `diff.renames`, or the rename detection drifts from the one
  `--porcelain=v2` already did.
- **A background `git diff` that reads the work tree needs
  `GitCommand::worktreeReadFlags()`** (`-c core.fsmonitor=false`), or on a
  machine with `core.fsmonitor=true` the user's own writes start losing
  `.git/index.lock` — measured at 12 runs / 9 failures. Deliberately *not* in
  `globalFlags()`: that would disable fsmonitor for `git status` too, on
  exactly the machines that opted into it. The `--cached` side never reads the
  work tree and does not pay it. **The process creating that lock was never
  identified** (ledger: "Working Copy 重新設計"); if anyone ever identifies it,
  the flag can be deleted — the comment says so.
- `git log --no-walk` sorts by commit date, not by the order the oids were
  given, so a batch reply must echo each oid rather than be index-aligned.
  And **absent is not zero**: a commit git never answered for is omitted, not
  cached as `0`.
- `git push` with no refspec pushes through the configured upstream and
  *refuses* when there is none — not equivalent to naming the current branch.
- `--topo-order` / `--date-order` stay unconditional in `toRevListArgs()`;
  the History branch filter's single-line rendering depends on a parent never
  being printed before its children.

### C++ core

- **`IProcessRunner::run()` is not byte-exact.** It reassembles stdout from
  the line splitter, dropping the final separator and stripping `\r` before
  every `\n` — a text blob comes back one byte short and a binary blob is
  silently corrupted. For verbatim bytes use `CatFileBatch`, which reads
  exactly the count `cat-file --batch`'s header declares.
- **Reads and writes are not serialised against each other.** Background
  status/diff runs on `sharedReadPool()` while writes run on
  `OperationRunner`'s single serial worker, and a plain `git status` rewrites
  the index and takes `.git/index.lock`. `GitCommand::globalFlags()` carries
  `--no-optional-locks` globally for this (**#77**).
- **Attribution goes through `Operation::kind()` and
  `PendingOperationTracker`** — never "the next completion event is mine",
  and never a match on `describe()`, whose user-facing English is not a
  protocol. The `PendingOperationKind` switches carry no `default` so a new
  kind is a compile error at the place the new arm belongs.
- Anything paired unconditionally (`beginAskpass`/`endAskpass`) needs the
  `onAlways` hook on `submitOperation` / `submitWorkingCopyOperation`, not
  `onSuccess`.
- **`RefreshCoalescer` needs `onFinished()` on every terminal path** — use a
  `ScopeExit`. Miss one and it stays `running_` forever, every later request
  folds into a batch nothing drives, and **refreshes stop happening at all,
  silently, with no error anywhere.** Publishing needs the monotonic
  generation gate inside the same mutex as the snapshot write, or a stale
  walk's `complete:true` answers for a newer one.
- `~Session()` ordering is load-bearing: `operations_->drain()` →
  `refreshTimer_.stop()` → `sharedReadPool().cancelQueuedAndDrain()`.
- **`GraphAsciiRenderer.cpp` is the reference renderer** — when it and the
  Dart painter disagree, the C++ one is right. `edge.lane ==
  rows[parentRow].lane` is a **false** invariant: `patchIncoming()` never
  rewrites `edge.lane`, so bending an arriving edge into the parent's lane is
  the renderer's job, not the builder's.
- A `std::span<const ObjectId>` does not accept a braced list in C++20.

### Reading the spec

- **A spec table's `how` column is a requirement, not an illustration**, and
  「this granularity is reachable」 is not evidence for it. `SCOPES` row 6's
  `how` is 「點 hunk 標頭列」 and the heading was a bare `Text` with no
  gesture; row 7's is 「拖過多行，**或 Shift + ↑ ↓**」 and only the drag
  existed — so every non-drag way of staging a line was missing while the
  matrix read 符合 off "reachable through the scope card and a text
  selection". This is the gate-vs-surface trap one level in: the cell named
  the *capability* and the spec named the *input*. It took a user report to
  surface, twice over — the same row had already been rewritten once for the
  same class of error. Related: a row's `note` conforming says nothing about
  its `how` (row 6's right-click Stage hunk was implemented all along).
- **The style demo is a spec too, and its DOM is the readable part.** The
  artifact at `claude.ai/code/artifact/bd3d9fdf-…` ("Diff Scope Studies")
  carries 變體 B's real structure — `.variant-B-temp` nested inside
  `.variant-B-card`, `.variant-B-card-muted`, `.variant-B-btn-off` — and the
  class names already appear in `scoped_diff_view.dart`'s comments. Fetch it
  with WebFetch and read the HTML, not only the CSS: the CSS says what a
  block looks like and only the DOM says **where it goes**, which is the half
  that shipped wrong.
- **A mockup shows what the user sees, not who draws it.** A conformance
  verdict has to rest on the spec's prose — reading an illustration as a
  requirement is what produced an issue asking for the *opposite* of what the
  spec wanted (#60, closed as not-planned). The same rule settled the
  fetch/prune contradiction: P10's mockup draws `--prune`, its own prose says
  「標記為 gone（尚未 prune）」, and the prose wins.
- **P13's `MULTIKEYS` is the authority for the branch list's selection
  model, and it contains no checkbox** — 「單擊 ＝ 只選這一項」, Ctrl/Cmd toggles,
  Shift ranges, Ctrl/Cmd+A, Esc. Checkout is a *double* click
  (`BRANCH_STATES`). A selection UI that needs a checkbox to be visible is a
  sign the row is missing its selected background, not that the spec wants a
  box (ledger: "Sidebar branch rows").
- **Any "range" over a list must be measured in the order the rows are
  painted**, not the order the model happens to hold them. The sidebar's tree
  sorts folders before leaves and each group alphabetically, so ref order and
  render order disagree the moment a folder exists; Shift-click and Shift+↑/↓
  both spanned the wrong rows until they read a list walked out of the built
  tree. A `containsAll` assertion cannot see this — use set equality. **The
  painted order is per display mode, not per widget**: the Working Copy board
  failed the same clause a second time because `FileListModeSwitcher` builds a
  tree only in tree mode and hands `items` straight to a `ListView` in list
  mode — the default — so one range implementation cannot serve both (C18).
- **The spec HTML has 21 pages**
  (`docs/claude-design-demo/Flutter Desktop Spec (standalone).html`), and
  `docs/reports/spec-conformance-matrix.md` was written against 12. **P16's
  `REVISIONS` table revises earlier pages**, so check whether a later page
  overrules a verdict written before it — two issues went stale exactly that
  way. P13 B, P15 and P17–P21 remain unaudited (**#76**). **P16's
  `REVISIONS` is now fully honoured** (its four shortcut rows, #75) and
  **P14's `IAMAP` was checked** — the twelve management panels share the one
  tab row, and the tab row's own placement gap is fixed.
- **A conformance cell whose evidence is `isActionEnabled()` proves the gate
  exists, never the gated surface.** P02 item 2 and P07's `Toolbar` row both
  read 符合 off `gbm_action_availability.dart` while the toolbar they describe
  was drawn by nothing — Fetch/Pull/Push had only a shortcut and a menu item
  (feat/p02-action-toolbar). Items 11, 12 and 14 on the same page fell the same
  way. Check the row's *title* against the spec's own wording before trusting
  its evidence: 「三顆同組。Push 為主要樣式。」 describes buttons, and the
  disabled-during-conflict clause hangs off them. **The trap is not specific
  to `isActionEnabled()`** — any helper can stand in for the surface. P03's
  「all 7 `SCOPES` granularities implemented」 rested on
  `WorkingCopySelectionState.getCheckState()` and `FileTreeNode.getCheckState()`,
  which exist, are correct and are unit-tested, and which **nothing under
  `lib/` has ever called** — orphan wiring dressed as evidence. The tell is
  the same every time: the cell names a *capability* instead of the widget
  that draws it. It also cuts the other way — removing the surface then
  leaves the cell looking unchanged (ledger: "Working Copy 重新設計").
- **When an issue's premise does not survive the source, correct the issue
  text in place and record the evidence** — close as not-planned rather than
  quietly retitle (#45/#50/#51/#60 precedent). Several rounds found the
  premise wrong in a way that moved the work; that correction is the most
  valuable thing the ledger carries.
- **Where a spec row cannot be honoured, the feature is absent and recorded,
  never faked.** Conversely, where working capi has no spec entry point it
  stays rather than being orphaned (**#92**–**#95**).
- 標題列 means four different things across this spec (**#68**) — settle the
  reading before moving code.

### Repo culture

**Three standing rules about how a round is run** (set by the user, not
derived from the code — they outrank convenience every time):

1. **Hitting a related issue means reading the spec and the decision record
   and *fixing it*.** Ask only when neither has the answer. An issue number
   is not permission to stop.
2. **Never produce a 「本輪不做」 without the user's decision.** A reduction
   is the user's call to make, not the implementer's; where something truly
   cannot be done, say what blocks it and finish everything else.
3. **Never open an issue without the user's consent.** Existing issues may be
   updated or closed; a new one is a decision, not a filing action.

- **Every cache in this repo documents three things in source, and needs a
  test that invalidation really recomputes.** The three: what the key is *and
  why it distinguishes every case it must*; which named events invalidate it;
  what symptom appears if invalidation is missed. Note that "which events"
  can legitimately be **none** — `UntrackedLineCountCache` has no event to
  subscribe to because an editor saving a file emits no `GBM_EVENT_*`, so the
  key *is* the invalidation, and saying so is part of the documentation rather
  than a gap in it. The test must count (`hits()`/`misses()`, an injected
  counting stand-in), never assert on the result alone: **a cache that
  recomputed every time and answered correctly is indistinguishable from a
  working one by its output.** And prefer removing the recomputation to
  caching it — C18's `FileTree` candidate turned out to be a code path that
  should not have run at all in the default mode.
- **Measure before caching, and put the number in the ledger.** C18's two
  numbers, debug JIT: splitting a 40×200 `DiffFile` into scopes is 197µs and
  ran *every frame* of a selection drag (cached); `FileTree.fromPaths` over
  100 paths is 41µs and runs per click (not cached). The second is written
  down precisely so the next round re-decides from a number rather than from
  the same guess.

- **Orphan wiring is the recurring defect shape here**: a route, provider,
  preference or capi field with no caller under `lib/`. It has shipped at
  least five times (`deleteRemoteBranchDialog`, `readVisibility()`,
  `readOrder()`/`readWidths()`, `RefreshCoalescer`, the `autoFetch*`
  settings — **#102**). Grep for a caller before adding a field, and before
  deleting the last one. The sixth instance was worse than dead weight:
  `ProcessStarter`'s `workingDirectory` parameter existed and no caller ever
  passed it, and passing it was the whole fix for the Windows self-install.
  The seventh and eighth were checkbox-era leftovers deleted in C18 — nine
  methods across `WorkingCopySelectionState` and `file_tree.dart`, all
  unit-tested and all uncalled, one of which was standing in as a conformance
  cell's evidence. **Not every uncalled function is an orphan**: the same
  sweep kept `sameLogicalFile` by moving it into its test file, because it is
  the independently-written *oracle* `logicalFileKey` is checked against —
  keeping it in `lib/` was the actual defect, since a bug in the key could
  otherwise hide inside the thing that checks it.
- **A second source of truth for a computed fact is how a bug hides** — it
  cannot disagree with itself. Folder identity, column order, selection sets,
  `conflictActive`, `submitCommit()` (the only place a commit message is
  composed and dispatched) and `scopeButtonLabel()` are each deliberately
  single-sourced.
- **Nothing is silently dropped.** A capability removed for spec conformance
  gets its reason recorded (the operation-log dialog's `Clear`, the
  per-remote Pull/Push), and a reduction made for a cap or a missing capi is
  written down rather than left for the next audit to file as a bug. But
  **a reduction note names one victim of a missing capability, not all of
  them**: `commit_selection_summary.dart` recorded P13's 合計 diff as absent
  because `ChangedFile` had no line counts, and P02-10's badge — same missing
  field, no running total needed — went unfiled for rounds. Grep for other
  readers of whatever a note calls absent before trusting its blast radius
  (ledger: "Changed files line counts").
- **A note explaining why a test avoids a code path deserves the same
  scrutiny as the code path itself** — one correct observation with a wrong
  cause became a permanent workaround and hid a real defect for months. The
  same holds for a comment explaining why the *implementation* is shaped as it
  is: `_keysInRenderOrder` built a `FileTree` unconditionally on a comment
  claiming 「both list and tree mode render through `FileTree.fromPaths`」, and
  list mode does not — so Shift-ranging in the default mode spanned tree order
  over rows painted in entry order, and the test that should have caught it
  pumped the default mode while asserting tree order, repeating the same wrong
  premise in its own comment (C18). **When a comment states what two code
  paths have in common, pump both and look**, rather than trusting the
  sentence.
  A mutation is how you check one: **a mutation that fails to land where the
  comment predicted means the comment is wrong**, not the mutation. Keying
  `attachLineCounts()` on `oldPath` was supposed to break deletes and broke
  only renames — `oldPath` is empty for every kind but rename/copy — so both
  the comment and the test's rationale were corrected.
- **A comment claiming its bounds are measured must be re-measured when
  anything upstream of the measurement moves.** A page recomposition is
  upstream of every width in the row. The same holds for a comment claiming a
  *performance* property: `ChangedFile`'s 「Cheap: no content is read, so
  clicking through commits stays instant」 stopped being true the round a
  second git invocation was added, and that round owned rewriting it.
- Stage by file when two changes are live in one directory: `git add -A <dir>`
  once swept an unrelated in-progress change into a `refactor:` commit. The
  opposite error is filing a file by where its *assertions* belong rather than
  where its *compilation* does: a commit that adds a `required` field to a
  model must carry every fixture that constructs **or feeds** it — a raw-JSON
  fixture is invisible to a grep for the constructor name, and a missing key
  is `null as int` at runtime. Only a per-commit checkout sees this; every
  run at the branch tip is green (line-counts round).

### Current known drift

- **Context menus**: `features/context_menus/gbm_context_menus.dart` declares
  all 11 of spec page 05's groups and is the parity test's acceptance
  baseline, but no file under `lib/` imports it — each render site
  hand-writes its list. Nine groups now conform; **05-B and 05-E are the only
  drifted ones left**. The `*_menu_items.dart` pure-function extraction is the
  template to follow. The catalog itself can drift from the spec, which the
  per-render-site audit method cannot detect (**#71**).
- **Absent for lack of a capi entry point**: per-object transfer counts for
  fetch/pull/push, `git init` / clone, removing a *scanned* repository from
  the switcher, squashing N commits, per-remote Pull/Push, and seven
  `PANELSPEC` detail fields (待提交數, 最後 fetch, 預期 commit, 大小,
  剩餘步數, 自訂測試指令, 欄位選擇器). All tracked on **#76**.
- `lfs_pattern_match.dart` is an **approximation** of gitattributes matching,
  not a port of `wildmatch()`; a pattern it cannot parse matches nothing, so
  a group reads 0 rather than a wrong number.
- **No pull dialog route exists**, so P17's 「選單的 Pull… 或 Alt + 點工具列才
  開」 has nothing to open: `ActionToolbar`'s Pull only runs `pullChanges()`
  with the configured default (**#109**).
- **The updater script's Windows half is text-asserted only.** The `sh` half
  is genuinely *executed* by `update_installer_script_test.dart`; PowerShell
  cannot be, and PR CI compiles no Windows at all (**#69**). The real
  install-and-restart still has no automated coverage on any platform — the
  device-tier test deliberately stops at `readyToInstall`. What does exist
  now is `<systemTemp>/gbm-update.log` (`updateLogPath()`), which every arm
  of both scripts writes its exit code to, and a relaunch on every failure
  path reached after the app has exited — so the next failure is diagnosable
  rather than a vanished window (ledger: 更新流程的三個缺陷).
- **Open issues**: **#62** (TabRow overflow menu), **#67**–**#71**,
  **#74**, **#76**, **#84**–**#89** (Tier 6 spec blockers), **#92**–**#95**
  (capi with no spec entry point), **#99**, **#101**, **#102**, **#109**.
  **#75 is closed** (all four 260820 `REVISIONS` shortcut gaps landed in
  feat/p03-working-copy-redesign). `gh issue list` is authoritative; the
  ledger's mentions are historical.

## Engineering ledger

[docs/ledger.md](docs/ledger.md) holds every round's narrative, moved here
verbatim (the moved block is byte-identical; nothing was reworded, dropped, or
summarised away). Filing rule for a new round: see the top of this file.

**Everything a source comment cites as "CLAUDE.md's Tier 0c note",
"Known gaps", "Tier 6c", "Spec conformance audit" or any other `Tier N` /
round heading is in `docs/ledger.md` now**, under the same heading text. The
comments were left alone rather than rewritten across ~30 files; this
paragraph is the redirect.
