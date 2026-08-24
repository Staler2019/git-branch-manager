# CLAUDE.md

Root-level guide for Claude Code (and other AI assistants) working in this
repo. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/FEATURES.md](docs/FEATURES.md) first — this file adds the Flutter UI's
structure, its session state machine, and the UX acceptance bar
`app_flutter/` changes are held to.

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
/repo/:repoId  (ShellRoute: WorkspaceScreen = menu bar + top bar + tab row + sidebar)
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
carrier (see "Tier 6c" below). `manage-stashes`, `manage-worktrees`,
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
                      one of these before hand-rolling a Container; see the
                      "known gaps" note below for a case where that was missed.
  features/
    welcome/         WelcomeScreen (route `/`, no repository open)
    repo_switcher/   RepoSwitcherButton (sidebar top) + popover + RepoSwitcherList
    workspace/       WorkspaceScreen (shell) + widgets/ (MenuBarRow, TopBar,
                      TabRow — presentational, no Riverpod dependency)
    history_graph/   CommitGraphView, commit_row.dart
    working_copy/    WorkingCopyView
    sidebar/         SidebarPanel
    diff/            DiffPage, side-by-side diff
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

Presentational/container split: `MenuBarRow`, `TopBar`, `TabRow`
(`features/workspace/widgets/`) take plain callbacks/values and hold no
Riverpod dependency, so they're tested directly against a bare `GoRouter`
(see `test/features/workspace/*_test.dart`). `WorkspaceScreen` is the
container: it watches `repoSessionProvider` and wires the callbacks in.

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
| `lastDiff` | `WorkingCopyDiffReply?` | most recently requested diff |
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

### Action availability state machine

`lib/actions/gbm_action_availability.dart`'s `isActionEnabled(GbmActionId,
RepoSessionState)` is the single source of truth for which actions a
state-dependent gate disables — every other call site (`workspace_screen.dart`'s
`_buildActionHandlers()`, `sidebar_panel.dart`'s `BranchTreeItem.conflictActive`,
`working_copy_view.dart`'s commit-box `canCommit`, `MenuBarRow`'s
`GbmMenuItem.enabled` grey-out) reads through this function rather than
re-deriving `session.conflictActive` locally.

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
   `MenuBarRow`/`TopBar` presentational split) so it's independently
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

## Engineering ledger

Every round of work on this repo used to append its narrative here, which is
how this file reached ~176KB — ~2,400 of its 2,839 lines were chronological
history, auto-loaded into every session. That history now lives in
[docs/ledger.md](docs/ledger.md), moved verbatim (the moved block is
byte-identical; nothing was reworded, dropped, or summarised away).

**Everything a source comment cites as "CLAUDE.md's Tier 0c note",
"Known gaps", "Tier 6c", "Spec conformance audit" or any other `Tier N` /
round heading is in `docs/ledger.md` now**, under the same heading text. The
comments were left alone rather than rewritten across ~30 files; this
paragraph is the redirect.
