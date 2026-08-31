# CLAUDE.md

Root-level guide for Claude Code (and other AI assistants) working in this
repo. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/FEATURES.md](docs/FEATURES.md) first — this file adds the Flutter UI's
structure, its session state machine, the UX acceptance bar `app_flutter/`
changes are held to, and the invariants and traps that keep being rediscovered.

**This file is an umbrella.** The rules themselves live in one file per
category under [docs/rules/](docs/rules/) and are pulled in by the `@` imports
below, so everything is still auto-loaded into every session — what changed is
that two parallel branches now edit two different files instead of two regions
of one 1,742-line one.

## Three layers, and what belongs in each

```
CLAUDE.md                        this file — filing rules + imports. No rule text.
  └─ docs/rules/<category>.md    the rules. Short, pinned, four fields each.
       └─ docs/ledger/<date>-<branch>.md   the decision record. Length is free.
```

| Layer | Holds | Auto-loaded | Conflict shape |
|---|---|---|---|
| `CLAUDE.md` | filing rules, imports, redirects | yes | rarely edited |
| `docs/rules/*.md` | current-state facts + distilled invariants | yes (via `@`) | different categories → different files |
| `docs/ledger/*.md` | one round's narrative and evidence | no | one round → one new file |

## Where a round's write-up goes

When you finish a round of work:

1. **The narrative goes to its own file** —
   `docs/ledger/<YYYY-MM-DD>-<branch>.md`, plus one line appended to
   [docs/ledger/INDEX.md](docs/ledger/INDEX.md). Date first, because branch
   names are too arbitrary to find a round by. Shape and rationale:
   [docs/ledger/README.md](docs/ledger/README.md). Length is free there.
2. **Only what a future session must know *before* it starts is distilled into
   [docs/rules/](docs/rules/)** — as a `## [PIN] Title` block with
   `Rule` / `Consequence` / `Do` / `Evidence`, `Evidence` pointing back at the
   round's file. Short and precise; the long form stays in the ledger. Format:
   [docs/rules/README.md](docs/rules/README.md). If an existing rule already
   covers it, edit that rule's lines rather than adding a second one.
3. **Current-state facts are rules too** — a route, a field, a state
   transition, a CI constraint, a still-open drift, all under
   `docs/rules/`. History is not: if the sentence only makes sense as "what
   happened in round N", it is ledger material.

**Do not put rule text back into this file, and do not append a round-shaped
section anywhere.** Both are what broke the previous two schemes: this file
reached ~176KB before the ledger was split out of it, and the ledger then
reached 5,900 lines with every round appending to the same end-of-file.

## Rules

@docs/rules/README.md
@docs/rules/ops-toolchain-ci.md
@docs/rules/fn-cpp-core.md
@docs/rules/drift-open.md

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

**Twelve former dialogs are now `/panel/:tabId` tabs**, not dialog routes —
spec page 14's `IAMAP` reassigns every large management panel to the tab
carrier (see docs/ledger.md's "Tier 6c"). `manage-stashes`, `manage-worktrees`,
`manage-remotes`, `manage-submodules`, `manage-lfs`, `patches`, `reflog`,
`interactive-rebase`, `bisect`, `blame`, `file-history` and `line-history`
were deleted along with their routes and helpers; a `RoutePaths.<name>DialogFor`
for any of them no longer exists.

Dialog routes are top-level (pushed over whatever's underneath), not
`ShellRoute` children — see `dialog_route.dart`.

**`/dialogs/update` has no menu-bar entry, by design.** Its three producers
are `about_dialog.dart`'s primary button, `preferences_dialog.dart`'s
「Check for updates now」 (Advanced), and `app.dart`'s `AutoUpdateCheck` at
startup. A `Help → Check for updates…` item existed and was removed — the
spec's P04 `MENUS` gives Help four items and that was a fifth, so the menu
is now conformant rather than deviating. About's button is the one that
matters: `WelcomeScreen` renders no menu bar at all, so with no repository
open it is the only reachable route to the check.

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

### Three two-column switches that look alike and are not

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
`isEffectivelyGone()`, so the sidebar rows, the bulk-select set, the status
bar and the delete-branch dialog's 「also delete on remote」 checkbox cannot
disagree about whether a branch is gone.

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
`gbm_action_id.dart` (the `GbmActionId` enum, 65 values), `gbm_menu_model.dart`
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
  is as often a weak assertion as a missing one. A ninth is the cross-language
  shape, and it is the worst of them because **both languages stay green at
  once**: a fixture that hand-sets a field production never sets. Every Dart
  test of the `isSymbolic` filters wrote `isSymbolic: true` by hand while
  `RefStore` never assigned the field at all, and the C++ tests were green
  because the struct member really did exist and really was serialized. Neither
  side can see the gap; only the real binary on the far side of the boundary
  can, which is why that test belongs in `GitIntegrationTest.cpp` and the
  FFI-payload one in `SessionApiTest.cpp`. **When a field crosses a language
  boundary, ask which side assigns it** — a hand-set fixture is evidence about
  the consumer, never about the producer.
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
  **The same hazard ruins a manual on-screen check, where it is harder to spot
  because the window looks entirely reasonable**: the user's installed
  `/Applications/gbm_flutter.app` runs alongside a freshly built one, and
  `osascript`'s `first process whose name contains "gbm_flutter"` fronts
  whichever it likes — a correct fix screenshots as a failure. Run `ps aux |
  grep gbm_flutter` first, front the build you mean by `unix id` (its PID), and
  confirm the binary really carries the change (`strings <dylib> | grep <a
  string only the fix introduces>`) before trusting what you see.
  But **`Failed to foreground app; open returned 1` is not itself the failure
  signal** — it prints on fully green runs too, and what discriminates is
  whether test-result lines follow it. Read past that line to the counts
  before concluding the tier is blocked; taking it at face value cost the
  side-by-side round a wrong 「裝置層跑不成」 verdict that had already been
  written into the ledger before the re-run disproved it. It cost soft-warp
  the same verdict a round later, for the same reason and with the counts
  sitting right there in the log — **3 passed and then a hang on test 4** is
  a hang on one test, not a blocked tier, and the two call for completely
  different next moves. **Run the control on the *parent commit* too**, not
  just on a different test: soft-warp's parent got only 1 test through where
  the branch got 3, which is the evidence that says 「這輪沒有弄壞它」 —
  it costs one detached-HEAD run and it is the half of the diagnosis the
  foreground line can never give you. **And a hang is not yet a defect**: the
  same soft-warp file, re-run at the end of the branch after a `pkill` and a
  `scripts/build_capi.sh` rebuild, went **7/7 in 1m50s** with the previously
  hanging test passing in 15s. Which of the three changes (fresh dylib, no
  stale process, three more commits) cleared it was not isolated — so the
  honest claim is 「not reproducible」, not a cause. Rebuild the dylib and
  sweep stale processes *before* filing a device hang as a finding.
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
  render. **It also clears the flat keys `fileListViewMode` and
  `diffViewMode`**, which the two prefix filters had never covered: Tree mode
  nests rows under folder rows and side-by-side draws two columns of cells
  where there was one, both of which are exactly the shape that makes a
  finder ambiguous or miss. A new app-wide preference means adding its key
  here — a prefix filter will not catch a flat one.
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
  drag that must **not** scroll (ledger: soft-warp). **The 「unnecessary」 half
  is stronger than 「they never meet」, and it was measured**: adding `mouse`
  to a `GbmCodeScrollWell`'s `dragDevices` — the premise inverted — left
  `diff_pane_drag_stage_test.dart` fully green, and a probe confirmed the
  mutation was live (the same drag moved the horizontal offset 0 → 50 with no
  selection in the way). So even when a scroller *does* enter the arena, the
  `SelectableRegion` wins it. The corollary matters for what a test can
  claim: a drag test under a scroller pins the **composition**, not the arena,
  because no realistic mutation of the arena reddens it.

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
- **An unfiltered `ref.watch(repoSessionProvider(identity))` rebuilds the
  whole shell on *every* state publish, including caches nothing on screen
  reads.** Scrolling History prefetches commit metadata per scroll tick, so
  each reply republished state and rebuilt `MenuBarRow`,
  `PlatformMenuBarHost`, `ActionToolbar`, `TabRow` and
  `_buildActionHandlers()` — on macOS that rebuilds a real native menu bar,
  and the reported symptom was 「每次捲動 menubar 都會閃爍」. `WorkspaceScreen`
  now watches a **record of the nine fields it consumes** and `read`s the
  full state (it is passed whole to ~40 sites, which is what `grep
  'session\.'` undercounts — bare `session` arguments do not match).
  **Never put a derived getter that builds a new collection into such a
  record**: `gonePendingRefs` returns a fresh `Set` and a `Set` has no value
  equality, so including it makes the record unequal every time and silently
  restores the storm it was meant to remove (ledger: History 捲動卡頓).
- **`ref.listen` never fires for the value already present when it
  registers.** Every `ref.listen`-driven piece of session state needs
  something else covering the value that was already there — a filter query
  surviving a repository close is the recorded case. The test that sees it is
  the one that seeds the provider *before* pumping. **The mirror case is that
  a seeded test is blind to the opposite defect**: a surface that reads a
  provider once per *mount* instead of once per *build* answers correctly on
  its only build, so `ref.watch` → `ref.read` stays green across every test
  that seeds-then-pumps. Only flipping the notifier while the tree is on
  screen tells the two apart — verified by exactly that mutation going red in
  `test/integration/soft_wrap_preference_flow_test.dart` and green in the
  four seeded wrap tests next door (ledger: soft warp round).
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
- **A `PlatformProvidedMenuItem` silently forks one action id into two
  different windows, and the dispatch-parity test cannot see it.** `helpAbout`
  was wired in `_buildActionHandlers()` *and* listed in
  `PlatformMenuBarHost._systemProvided`, so Windows/Linux opened
  `AboutDialogContent` while macOS got the native About panel — for months,
  with every tier green. The reason no test caught it: a system-provided item
  takes **no handler from the map at all**, so «the handler is non-null» was
  vacuously true, and the in-window click test only ever exercised the
  non-macOS path. **Assert what a menu handler renders, not that it exists** —
  `item.onSelected!()` then a finder on the route's content
  (`workspace_about_dialog_test.dart`), with a second dialog route present as a
  decoy so a mis-wire fails on content rather than on a missing route. Spec
  page 01 is the rule being enforced: only the menu bar's *position* follows
  the OS; every window's *contents* are Flutter's on all three platforms. Note
  `PlatformMenuBar` replaces menus from index 1 only, so `MainMenu.xib`'s
  `systemMenu="apple"` menu survives untouched — macOS already has a native
  About/Quit/Hide there, which is what makes a second one under Help redundant
  rather than required. Quit stays system-provided for exactly that reason.
- **macOS reads the *application* name from the bundle, never from
  `NSWindow.title`.** `MainMenu.xib` writes the Apple menu, About, Hide and
  Quit items as the literal placeholder `APP_NAME`, which AppKit resolves from
  `CFBundleDisplayName` → `CFBundleName` at load time; the Dock tooltip and
  Force-Quit list read the same. It said `gbm_flutter` because `CFBundleName`
  was `$(PRODUCT_NAME)` and `PRODUCT_NAME` is also the built artifact's name,
  which `release.yml` hardcodes as `gbm_flutter.app` in four places. Writing
  the literal into `Info.plist` decouples the two (#67 candidate fix 1);
  renaming `PRODUCT_NAME` does not, and is a tag-build-only change. **No Dart
  tier reads a bundle's Info.plist and PR CI compiles no macOS (#69)**, so
  `test/platform/window_title_test.dart` asserts the plist as source text —
  and the value it asserts must be checked against a real
  `flutter build macos` at least once per change.
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
- **A `Scrollbar` paints along the edges of *its own* box, so a scroller
  whose box is unbounded puts its thumb where nobody can see it.** The
  Working Copy's horizontal scrollbar sat at y=1428 against a 300px pane,
  because `WorkingCopyDiffPane` put the scroller under a vertical
  `SingleChildScrollView` and the child of one gets unbounded height.
  Scrolling still worked (trackpad pan, Shift+wheel) — what was lost is the
  at-rest 「there is more to the right」 signal, dimension D's
  `material_state_hidden`. `GbmCodeScrollWell` is the fix and its shape is
  the rule: **horizontal scroller outside, vertical inside, and both
  `Scrollbar`s outside both** so each paints against the bounded pane;
  moving either scrollbar inward re-creates the bug on the other axis. Two
  traps come with it. **The ambient `ScrollBehavior` adds its own scrollbars
  on desktop**, wrapped around the *inner* scrollables — the same bug back
  again, and a finder still counts one per axis — so the inner tree needs
  `ScrollConfiguration(scrollbars: false)`. And **`flutter_test` reports
  `TargetPlatform.android` by default**, where Material adds no ambient
  scrollbar at all, so any test about them must set
  `debugDefaultTargetPlatformOverride` (reset it *in the test body* — the
  no-debug-variable-outlived-the-test check runs before tearDowns) or it
  passes with the suppression deleted. This app ships desktop-only, so the
  test default is the one platform that never happens (ledger: soft-warp).
  **It recurs on the other axis wherever a scroller sizes its child**, and
  `GbmCodeHScroll` did: its child `ListView` sits inside
  `SizedBox(width: contentWidth)`, so the ambient *vertical* scrollbar painted
  at `x = contentWidth` — 1025 against a pane ending at 610 — on all five
  read-only file surfaces at once. The fix is the same shape, and it forces
  the composition owner to hold the other axis' controller: `GbmCodeHScroll`
  takes a `required verticalController` with no default and no owned fallback,
  because a null would mean a scrollbar that cannot be dragged, which is worse
  than the bug. **Ask the recurrence question whenever you fix one of these**
  — the two widgets' `ScrollConfiguration` blocks are now byte-identical,
  which is also why a mutation anchored on that block matches twice.
- **`TwoDimensionalScrollView` is not the answer for a surface whose rows
  must stay mounted.** The disqualifier is that it is a *lazy* viewport:
  off-screen children are destroyed unless individually kept alive. Lead with
  that, not with 「core ships only the abstract halves」 — that is a real cost
  but not a disqualifier, and it does not survive the concrete form:
  `package:two_dimensional_scrollables`' `TableView` is a concrete class built
  on the same lazy viewport. **Passing off a cost as a disqualifier is the
  same error as a conformance cell whose evidence is `isActionEnabled()`** —
  a true, checkable fact standing in for the claim that actually needed
  checking. `ScopedDiffView`'s rows each hold the `SelectionListener` that
  reports whether the live selection touches them, which is how `SCOPES`
  row 7's drag-to-stage knows what it framed, so unmounting one silently
  breaks staging across a scroll. Keeping every row alive pays for a custom
  render object and gets a non-lazy list back. When the thing actually
  wanted is 「both axes bounded by the pane」, build that with plain
  scrollers (ledger: soft-warp).
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

- **`GraphSnapshotView.edgesSpanning()` is index-backed, not a scan.**
  `GraphSpanIndex` (`lib/data/models/graph_span_index.dart`) is built once
  per snapshot and cached on an `Expando` keyed by the snapshot instance —
  no invalidation exists because none is needed (a new snapshot is a new
  object; the old entry dies with its key). Its **extent comes from `edges`,
  not `rows`**: `edgesSpanning` is contractually a pure function of `edges`,
  and `graph_snapshot_test.dart` queries a view whose `rows` is empty while
  its edges span rows 5..20. The brute-force scan now lives in
  `graph_span_index_test.dart` as the oracle, deliberately not in `lib/`.
- **`matchingRowIndices` returns an O(1) view, not a list, when the query is
  empty.** `UnfilteredRowIndices` is read-only and computes element i as i;
  it is the commonest state of the History list, and it used to be an
  N-element allocation per scroll tick. Do not assume the result is mutable
  or materialised. `_buildList` likewise hands back `graph.oidsHex` itself
  rather than copying it when nothing is filtered.
- **`RepoSessionController.refreshRepoStatus()` is the one entry point for
  "re-read the git status", and its membership is a rule, not a list: every
  zero-argument `refresh*` on the controller** (twelve of them). Both
  `WorkspaceScreen`'s `AppLifecycleListener.onResume` and
  `GbmActionId.viewRefresh` (F5 / `View → Refresh`) call it, so the two
  cannot drift into refreshing different things — F5 used to re-read only
  the history, leaving the Working Copy badge and diff stale on the one path
  where the user explicitly *asked* for fresh state. The `request*` methods
  are all excluded because they are keyed to a user selection that need not
  exist when the window comes back. Focus regain is throttled by
  `kFocusRefreshThrottle` (2s); F5 deliberately is not. The throttle clock is
  a `Timer`, not `DateTime.now()`, because only the former is advanced by
  `tester.pump()`. **Not verified on real hardware**: the tests drive
  `handleAppLifecycleStateChanged` directly, which proves the wiring but not
  that macOS emits inactive/resumed on window focus changes.
  **`repoState` is the half of `conflictActive` that `refreshWorkingCopy()`
  does not cover** — `_readRepoState()` had only two callers, session open
  and `operationFinished`, so a rebase begun *or aborted* from a terminal
  left the status bar, the banner and the twelve `isActionEnabled()` gates
  frozen until the app itself ran an operation. `refreshRepoState()` is the
  one synchronous member (`RepoState::read()` only stats a handful of `.git/`
  paths), which is why the conflict badge corrects on the same frame.
- **Never gate a refresh on a predicate that guesses what git would answer.**
  `git submodule status` costs **79ms even with zero submodules**
  (`git-submodule` is a POSIX shell script, so it is fork + shell startup,
  not repository size) — 66% of everything `refreshRepoStatus()` added. Both
  candidate short-circuits, «`.gitmodules` exists» and «the index holds a
  gitlink», were rejected: each only approximates what the command would have
  said, and a guess in core is the same mistake as a guess in Dart.
  **`Session::refreshLfs()`'s short-circuit is not a counter-example** — its
  condition is that `git-lfs` is not on PATH, which is not approximating an
  answer, it is knowing the command cannot run. The cost was then measured to
  be one nobody waits on (background pool, ≤ once per 2s, nothing on screen
  blocked), so nothing is gated at all. Reading «this number is large» as
  «this needs fixing» without first asking *who is waiting on it* is the
  error being recorded here (ledger: fix/focus-refresh-repo-state).
- **`RefInfo.upstream` is the full ref name** (`refs/remotes/origin/x`), from
  `%(upstream)` not `%(upstream:short)`. Splitting on the first slash yields
  `"refs"` — use `remoteBranchParts()`. That was **#74**, now closed, and the
  same function held two more defects that only surfaced once the sidebar's
  prune entries were removed and this dialog became the only path to a remote
  delete: it asked `upstream` alone whether a branch *has* a remote side (see
  the counterpart entry below), and it **printed the upstream's branch name
  while dispatching the local one** — `feature/x` tracking `origin/renamed-x`
  said 「Also delete renamed-x」 and ran `git push origin --delete feature/x`.
  A branch's name on the remote is not its local name; resolve both from the
  counterpart in one place (`deleteBranchRemoteTarget()`). **Every fixture in
  which the two names coincide is blind to this**, which is nearly all of
  them.
- **「Does this local branch have a remote side?」 is not answered by
  `upstream`.** `git push origin HEAD` and most PR flows leave
  `branch.<name>.merge` empty while putting the branch on the remote, so a
  same-named remote ref is a real counterpart with no tracking config behind
  it. `mergeLocalAndRemoteBranches()` matched on the config alone and so drew
  such a branch **twice** — as a duplicate leaf for a nested name (a `List`),
  or losing the local row entirely for a root name (a `Map`, last write wins)
  — which is the whole of the reported 「剛進來灰雲、fetch 後黃雲斜線」
  symptom, prune being innocent. `RemoteBranchIndex`
  (`data/models/remote_counterpart.dart`) is the single source: explicit
  tracking first, then an *unambiguous* same-name match, and **nothing at all
  when two remotes share the name** — a counterpart cannot be inferred from a
  name, and guessing wrong is worse than not guessing. It is an index rather
  than a scan because the per-branch scan measured 14ms at 500×500 and runs
  every sidebar build (ledger: 「prune 壞掉的表象下有六個缺陷」). Read it
  through the index, never by re-deriving the match.
- **`RefInfo.hasTrackingInfo` does not mean "has an upstream"** — it mirrors
  `%(upstream:track)`, which is *empty* for a branch exactly in sync. Ask
  "does this track a remote?" with `upstream`; reserve `hasTrackingInfo` for
  "did git report ahead/behind numbers".
- **`RefInfo.ahead` means nothing when `upstream` is empty** — a branch that
  never had one reports `0`, which rendered literally claims the opposite of
  the truth.
- **The current branch has no sorting or filtering privilege in the sidebar,
  and this is a user-ratified deviation — do not "fix" it back.**
  `BRANCH_STATES` (「永遠置頂於所屬資料夾內，且不受 filter 影響」), P02-14
  rule 7 (「即使不符合條件也不會被濾掉」) and `BRANCH_TREE`'s mock (which
  draws `main` above the folders at its own depth) all specify otherwise, and
  all three were implemented and passing before the user ruled against them:
  a pin makes the first row of every level jump around depending on where
  HEAD happens to be, and an exempt row makes a filtered sidebar draw a
  folder with no matching child in it. Same precedent as the Working Copy's
  removed checkboxes. What is left is `_compareTreeNodes`' plain 「folders
  (alphabetically) → leaves (alphabetically)」 — folders-before-leaves stays
  because it is tree *structure*, not branch priority, which is the
  distinction the user drew. **The visual half of `BRANCH_STATES` survives
  untouched** (bold name + full-row `surfaceSelected`), and it is now the
  only thing marking HEAD, which is also what keeps
  `branch_selection_rules.dart`'s 「HEAD is never bulk-selectable」 rationale
  intact. 「Where am I」 is answered instead by `sidebar_panel.dart` seeding
  `_expandedFolders` with `ancestorFolderPaths(refs.head.branchName)`, so the
  folders on the way to HEAD are open on the first frame — seeded on mount
  *and* on every checkout through one `_seededExpansionForHead` gate, and
  `addAll`-only so nothing the user collapsed is forced back open. Ledger:
  「側邊欄目前分支不再置頂」.
- **`refs/remotes/<remote>/HEAD` is a symref, not a branch, and `RefInfo.isSymbolic`
  is the only thing that says so.** It is populated from `%(symref)`, the ninth
  and last field of `RefStore::load()`'s `for-each-ref` format — appended at the
  end precisely so the sink's `fields.size() > N` bounds keep the other eight
  where they were. For as long as that field was missing, `isSymbolic` sat at its
  `= false` default, nothing in `src/` ever assigned it, and **three Dart filters
  written to drop the ref were dead code**: the sidebar drew `origin/HEAD` as a
  selectable, checkout-able branch row called `HEAD` (its shortName rewrites to
  the bare `HEAD`, and no local branch claims it, so `mergeLocalAndRemoteBranches`
  emits it as remote-only). `BranchOps.cpp`'s `/HEAD` suffix check is **not** a
  second source: it reads raw `for-each-ref --contains` output, never a `RefInfo`.
  **Not every reader of the flag is a render site** — `graph_ref_chips.dart`'s
  `!r.isSymbolic` guards the upstream-resolution lookup map only; its chip list
  comes from an unfiltered `refsAtRow`, so History still draws an `origin/HEAD`
  chip — **user-ratified: it stays**. The flag was false for every release
  before this one, so leaving the chip is zero regression while removing it
  would be a fresh behaviour change on a surface nobody asked about. Ledger:
  「側邊欄那一列 `HEAD`」.
- **`RefInfo.isGone` can only be true after a prune** (git reports `[gone]`
  only once the remote-tracking ref is already deleted). Gone *marking* comes
  from `git remote prune --dry-run`, deliberately not from `fetch --prune`.
  Read gone-ness through `features/sidebar/gone_marking.dart`'s
  `isEffectivelyGone()`, never `isGone` or `gonePendingRefs` directly — and
  note it now takes a `remoteCounterpart`, because a branch with no tracking
  config still has a remote side to be gone from. **Gating anything on
  `isGone` alone leaves it wrong for the entire window between the fetch that
  discovers the deletion and the prune that records it**, which is where the
  user actually is when they look; the delete dialog's checkbox shipped that
  way.
- **`fetch` prunes unclaimed refs in the background, and no menu says the
  word 「prune」 — user-ratified, do not "fix" it back.** P02-12's three
  stages (mark → badge → explicit Prune) are superseded: a successful fetch
  auto-prunes exactly the refs the `--dry-run` preview calls gone **and** that
  no local branch claims. A claimed one keeps its cloud-off marking, because
  the user can still repush it. `Remote → Prune remote branches` survives as
  the manual fallback. **Only *fetch-triggered* previews may auto-prune**
  (`_autoPrunePreviewsInFlight`): the Prune dialog asks for a preview of its
  own, and an undiscriminated rule deletes the refs it is listing out from
  under the user. An automatic prune's failure is kept out of `lastError` —
  nobody asked for it — but still reaches the operation log; not notifying is
  not the same as not recording. **P11 item 9's 「可選同時 prune」 switch is
  deleted, not merely unwired** — the behaviour above is describable by no
  wording of an on/off switch (off would not stop it; on would promise the
  full `--prune` the ruling does not do), so `AppPreferences.autoFetchPrune`
  is gone from the model, the dialog and storage. Re-adding it re-creates a
  control that lies. `AppPreferences`' own doc rule is the precedent: absent
  beats present-and-ignored.
- `RemotePrunePreviewEntry.ref` is a **short** name while `upstream` and a
  remote row's `fullName` are full — normalise through `fullRemoteRefName()`.
  Every *comparison* in this codebase is on the full form; the short form is
  display only.
- `git branch -m` **keeps** `branch.<name>.remote/.merge`, so a local-only
  rename needs an explicit `git branch --unset-upstream`.
- **`git branch --delete --remotes` takes the *short* name only.** Measured:
  `refs/remotes/origin/feat/x` is 「remote-tracking branch not found」, exit 1,
  while `origin/feat/x` deletes it. `RemoteOps.h`'s contract said short all
  along; two Dart call sites sent `fullName`/`upstream` anyway, and
  `RemotePrunePreviewEntry`'s own comment knowingly documented both forms as
  coexisting. Normalise with `shortRemoteRefName()` at the boundary — but
  keep *comparisons* on the full form (`fullRemoteRefName()`), which is the
  rest of the codebase's convention.
- **`git branch -d`/`-D` is per-name and partially succeeds; `exit 1` does
  not mean nothing happened.** Measured: `git branch -d a cur b` deletes `a`
  and `b`, refuses `cur`, and still exits 1 — so a single exit-code check
  reports total failure for work that is mostly done, and a force retry then
  resends the already-deleted names, which fail as 「not found」 and report
  total failure a second time. That is the whole of the user's three-line
  error log. `DeleteBranchOperation` now probes `git for-each-ref` before
  (send only what still exists) and after a failure (say what really went),
  and **deliberately does not parse per-name stderr** — those strings are
  gettext-localised, so they may inform a *message* but never a correctness
  decision.
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
- **The commit graph's lane pitch is 11 while its dot geometry is still
  spec's — the two stopped coming from one source, and that is user-ratified.**
  `spec_logic.js:428`'s `L0 = 15, L1 = 32` is a 17px pitch, and an earlier
  round corrected a drifted 18 to it. The user then ruled the lanes should sit
  at about two thirds of that, so `GbmLayout.graphLaneWidth` is **11** while
  the halo, HEAD ring and connector in `graph_column_painter.dart` keep
  spec's 2.0 / 7.0+1.5 / 1.75 untouched — that ask was spacing, not a
  smaller graph. **The dot alone then went 4.2 → 5.0 on a second ruling**, and
  5.0 is not a taste: the ring keeps spec's numbers, so its *inner* edge is
  6.25 and a dot's visible outer edge is `radius + halo / 2`. At 5.0 that is
  6.0, leaving 0.25px of background; past it the ring stops reading as a ring
  and reads as a thick edge on the dot, **with no exception anywhere** — the
  ring is painted after the dot, so nothing is overdrawn. Only
  `graph_dot_geometry_test.dart`'s arithmetic sees it. Do not "fix" either
  number back on the citation's authority; the citations are still true and no
  longer decide the numbers. What makes the two
  compatible is **`kGraphLaneInset` (8 = `ceil(7.75)`, the HEAD ring's outer
  edge)**: a lane's centre is the inset plus whole pitches, **never**
  `laneWidth * (lane + 0.5)`, which made the ring's room a function of the
  pitch — at 11 it left lane 0's centre at 5.5 and `commit_row.dart`'s
  `ClipRect` cut the ring on the trunk, the lane HEAD sits in most often.
  Margin at 8 is 0.25px, so **anything that grows the ring has to move the
  inset with it**. Three pitch-derived numbers move with the pitch and one
  does not: `GbmGraphColumnId.graph`'s 153/34/425 → 99/22/275 (lane counts
  written in pixels — leaving them would have redefined the cap from eight
  lanes to thirteen), the refs corridor's measured ceiling 287 → 341, and
  `commit_row_narrow_width_test`'s rung fixture 610 → 552; the refs *floor*
  91 is a chip measurement and is pitch-independent. Ledger:
  「commit graph 的 lane 間距」 and 「點放大，以及分支顏色不再撞在一起」.
- **The lane palette has twelve colours because the core emits twelve, and
  their *order* is a contract the core does arithmetic on.**
  `GraphSnapshot.h`'s `kPaletteSize` is 12 and `colorForSeed` returns
  `0 .. 11`; `GbmColors.graphLanes` shipped with six, so the painter's
  `color % length` folded id 6 onto **0, the trunk's own colour**, and 7..11
  onto 1..5 — two random branches looked alike 17.4% of the time instead of
  9.1%, silently, because nothing linked a C++ `constexpr` to a Dart
  `.length`. `gbm_lane_palette_test.dart` now **reads `GraphSnapshot.h`
  itself** rather than copying the 12; a copy is what drifted. Entry `i` sits
  at `hue(0) + 30 * i` degrees **in OkLCH**, so `LaneAllocator`'s
  `min(d, 12 - d) >= kMinColorSeparation` is a hue distance without the core
  ever seeing an RGB value — reorder the list and the core keeps "spreading"
  a number that means nothing, with no symptom. **OkLCH, not HSL**: the same
  twelve colours are 12.4° apart in HSL's teal band and 68° in its green one,
  so an HSL assertion misreads an even palette as uneven and passes an uneven
  one. Twelve colours is a user-ratified deviation — spec names
  `--graph-lane-1` .. `--graph-lane-6`. Ledger:
  「點放大，以及分支顏色不再撞在一起」.
- **A lane's colour is the hash of its seed oid, repaired only when it crowds
  a neighbour** — and the seed of a ref tip's lane is the **tip commit**
  (`GraphBuilder.cpp`'s no-incoming-edges path), so committing on a branch
  already recoloured it long before the neighbour rule. `LaneAllocator`'s
  comment used to claim oid-keying kept a branch's colour across a refresh; it
  keeps it across *lane index reuse*, which is narrower. **The window is five
  columns either side, graded** — a quarter turn from the column beside you,
  60° from the one after that, merely a different colour out to five — and
  `penaltyWeight`'s 100/10/1 is what stops the tiers being traded against each
  other (everything below offset 1 sums to at most 46). It was ±1 for one
  round, and the entry here argued against widening it on two grounds that
  were both wrong: widening does **not** repaint anything, because a colour is
  fixed at seed time and never revisited; and ±1 was thinner than it read,
  since `allocateLeftmost` returns the *lowest free* lane, so on the ref-tip
  path there is nothing to the right by construction and only the left
  neighbour could ever fire. What actually broke was the user's own case —
  two branches in one colour with a single lane between them. Beyond the
  window repeats stay possible, and past 11 live lanes they are unavoidable:
  the palette has 11 non-trunk colours and `kMaxLanes` is 48, so the rule
  decides *where* a repeat lands, never whether. Ledger:
  「相隔一欄仍然撞色」.
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
- **Warm the JIT before timing, on every path being compared.** Timing
  cases in one loop with N increasing puts the smallest N on the coldest
  JIT. That produced a table where the *indexed* lookup got cheaper as the
  graph grew (8.85µs → 2.08µs → 0.58µs per row) — an impossible shape for an
  index, and it read as "the index is slower on small repos", nearly buying
  a threshold nothing needed. After 20k warm-up iterations on both paths the
  indexed cost is flat (~0.5µs) at every N. A per-N cost that *falls* as N
  rises is the tell (ledger: History 捲動卡頓).
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
  otherwise hide inside the thing that checks it. `pairHunkForSideBySide` in
  `src/core/git/SideBySideDiff.cpp` is the second such keeper and the reason
  is different again: it has no caller and never will, because the Dart port
  that *is* called mirrors it line for line — it is the **reference
  implementation**, exactly as `GraphAsciiRenderer.cpp` is for the graph.
  Both headers now say so; deleting it would take the reference with it.
- **Deleting code as an orphan obliges you to correct the record that
  justified it, or the deletion repeats.** `side_by_side_diff.dart` was
  deleted in C13 on a correct reading — the spec really does not ask for a
  side-by-side diff — and the verdict was filed in
  `docs/reports/spec-conformance-matrix.md` as 「orphaned code answering no
  requirement」. When the user later ruled the feature *in*, that row would
  have justified deleting the restored files a second time on grounds already
  overruled. The fix is two-sided and both halves are load-bearing: strike
  and rewrite the row **in place** (the #45/#50/#51/#60 precedent), *and*
  put the citation in the restored files' own doc comments, because an
  orphan sweep starts from the code and may never open the report. Note what
  survives the correction: the spec claim was true then and is true now —
  what stopped being true is that 「no spec basis」 is sufficient grounds
  (ledger: History 的並排 diff).
- **Deriving a quantity you already have is how a bug hides in the majority
  case.** The restored side-by-side view read a line's number as
  `kind == removed ? oldLine : newLine` — right for a removed line and an
  added one, and wrong for every *context* line in the left column, which is
  neither and so fell through to `newLine`. It is invisible whenever a hunk
  starts at the same number in both files, so it only appears once an earlier
  hunk has added or removed lines. The cure was to move the decision one
  level up, to the thing that actually knows: the **column** picks the
  number (`SideBySideSide.left => oldLine`), not an inference from the row.
  A fixture that does not set `oldStart != newStart` cannot see it.
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

## Engineering ledger

[docs/ledger.md](docs/ledger.md) holds every round's narrative, moved here
verbatim (the moved block is byte-identical; nothing was reworded, dropped, or
summarised away). Filing rule for a new round: see the top of this file.

**Everything a source comment cites as "CLAUDE.md's Tier 0c note",
"Known gaps", "Tier 6c", "Spec conformance audit" or any other `Tier N` /
round heading is in `docs/ledger.md` now**, under the same heading text. The
comments were left alone rather than rewritten across ~30 files; this
paragraph is the redirect.
