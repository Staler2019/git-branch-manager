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
/repo/:repoId/conflicts            ConflictResolveWindow (standalone window, not a dialog overlay)

/dialogs/about                            \  app-wide (not repo-scoped: discovery
/dialogs/keyboard-shortcuts                > and app settings aren't tied to any
/dialogs/manage-base-folders               > one open repository, see gbm_capi.h's
/dialogs/preferences                      /  Discovery section, and spec page 11)

/repo/:repoId/dialogs/<name>       33 repo-scoped dialogs: reset-branch, merge,
                                    cherry-pick, stash-changes, manage-stashes,
                                    manage-worktrees, manage-remotes, create-tag,
                                    credential, operation-log, blame, file-history,
                                    line-history, reflog, undo-last,
                                    interactive-rebase, manage-submodules, bisect,
                                    manage-lfs, patches, clean-untracked,
                                    checkout-recovery, delete-branch-recovery,
                                    prune-remote-branches, repository-settings,
                                    new-branch, checkout, delete-branch,
                                    rebase-onto, force-push, delete-remote-branch,
                                    restore-file, discard-changes
```

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
    operation_log/   OperationLogDialog
    compare/         ComparePage
    status_bar/      StatusBar, BackgroundTask
    log_drawer/      LogDrawer
    context_menus/   Shared GbmContextMenuItemSpec builders (9 right-click targets)
    dialogs/         The 33 repo-scoped dialog contents listed above, plus the 4 app-wide ones
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

Plus one derived getter, not a field — the single source of truth for conflict
state, read by every conflict-aware surface and by
`lib/actions/gbm_action_availability.dart` (see "Action availability state
machine" below):

```dart
bool get conflictActive =>
    (repoState?.isSequencerOperation ?? false) ||
    workingCopyStatus.conflicted.isNotEmpty;
```

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
`gbm_action_id.dart` (the `GbmActionId` enum, 52 values), `gbm_menu_model.dart`
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

### Spec conformance pass

A later pass re-read the source spec (`Flutter Desktop Spec.dc.html`, the
same claude.ai design project `f6b7d1fd-…` that `docs/design/tokens-reference.md`
is drawn from) page by page and closed the gaps it found. What that changed,
so the next reader doesn't re-derive it:

- **~30 of 52 menu actions were wired to `null`** — the menus rendered, but
  clicking did nothing. All now resolve to a handler except the four routed
  through `MenuBarRow` params and those legitimately state-dependent
  (disabled with no unstaged files, on a detached HEAD, or mid-conflict per
  spec page 07).
- **History had no commit search** (spec page 02 item 3). Added
  `features/history_graph/commit_search.dart` + a filter field. The lane
  column is hidden while filtering, because `graph.edges` connect adjacent
  rows of the *unfiltered* snapshot. Known limitation documented there:
  message/author matching only sees commits whose `CommitMeta` has loaded;
  hash-prefix matching covers the whole snapshot.
- **Nine spec page 06 dialogs did not exist** — new-branch, checkout,
  delete-branch, rebase-onto, force-push, delete-remote-branch, restore-file,
  discard-changes, repository-settings.
- **Discard had no confirmation at all**: `WorkingCopyView._discardFile`
  called `restorePaths` straight from the context menu. It now goes through
  the discard-changes dialog.
- **`PlatformMenuBarHost` was a passthrough stub**; it now builds a real
  macOS `PlatformMenuBar`, and `MenuBarRow` is suppressed there so the menus
  don't render twice (spec page 01).
- The Keyboard shortcuts dialog was seven hardcoded strings matching neither
  the menu labels nor the real bindings; it now derives from `gbmMenus` +
  `gbmActionShortcuts`.

Toolchain note: this repo needs Flutter with Dart ≥ 3.12.2 (`pubspec.yaml`'s
`sdk: ^3.12.2`) — Flutter 3.44.x ships it. After that pass `flutter analyze`
is clean (exit 0) and `flutter test` is 631 passed / 21 skipped.

**`flutter analyze` must stay at zero issues.** CI's Flutter UI job runs it
with no tolerance flags, and the command exits non-zero on *info*-level
lints too — so an "only an info" diagnostic still fails the build. That job
also sits behind `needs: capi-build`, so it does not run at all while any
capi job is red; a green capi run can therefore surface Flutter problems
that were previously invisible rather than absent.

### Known gaps (flagged, not fixed this round)

- **B (−1 pt)**: route/entry-point reachability was audited exhaustively;
  whether each dialog's *internal* functionality is complete once opened was
  not re-verified per dialog.
- ~~**Route audit has drifted since Round 1**: a later `deleteRemoteBranchDialog`
  route (`route_paths.dart`) was registered in `app_router.dart` but never
  given a call site under `lib/features/`~~ — **Fixed**: `sidebar_panel.dart`
  now renders one merged branch tree instead of local branches only, per the
  source design (`Flutter Desktop Spec (standalone).html`, page 02 items
  4/12): `branch_tree_builder.dart` gained `mergeLocalAndRemoteBranches()`
  (local ∪ the subset of remote branches with no local branch tracking them,
  matched by a local branch's `RefInfo.upstream` — confirmed to be the
  tracked ref's *full* name, not `%(upstream:short)` — against a remote
  branch's `fullName`; a matched remote branch is dropped, an unmatched one
  keeps its ref but has its `shortName` stripped of the `<remote>/` prefix so
  it groups into the same folder a same-named local branch would) and
  `remoteBranchParts()` (the inverse split, recovering remote name + branch
  name from a remote ref's `fullName` for the actions below).
  `BranchTreeItem` renders a remote-only row per `BRANCH_STATES`: cloud icon
  (cloud-off for gone, new `assets/icons/cloud-off.svg`) at 0.62 opacity,
  single tap inert, double tap checks out as a new local branch, and its
  right-click menu swaps to the 05-C subset (Checkout as new local…/Copy
  branch name/Prune this ref/Delete on remote…, "Fetch this branch" omitted
  — `gbm_remote_fetch()` has no per-ref fetch capability). `sidebar_panel.dart`
  wires the three real actions: `checkout(target: fullName, createBranch:
  true, newBranchName: shortName)`, `pruneRemote(remoteName, [fullName])`,
  and `context.push(RoutePaths.deleteRemoteBranchDialogFor(...))` — the
  previously-orphaned route now has its call site. Covered by
  `branch_tree_builder_test.dart`, `branch_tree_item_test.dart`,
  `branch_context_menu_test.dart` (widget tier) and
  `sidebar_panel_remote_branch_test.dart` (drives the real
  `repoSessionProvider`/`GoRouter` seam via `FakeRepoSessionController`, not
  just `BranchTreeItem` in isolation — including a round-trip test that
  `emit()`s a conflicted state, asserts double-tap checkout no-ops, then
  `emit()`s clean and asserts it fires, per the "Rule" at the end of
  "Action availability state machine" above). Discovered along the way: a
  remote-only row's `InkWell.onDoubleTap` and its inner "more" `IconButton`'s
  tap recognizer sit in the same gesture arena, so a single click on that
  button has a real ~300ms hesitation before the menu opens
  (`kDoubleTapTimeout`) — a latency quirk, not fixed here (see
  `sidebar_panel_remote_branch_test.dart`'s `_openRemoteRowMenu` doc
  comment). ~~Still not addressed: a "gone" row (a local branch whose
  upstream vanished) still goes through the full 05-B local-branch menu
  instead of spec's narrower gone-row subset~~ — **Fixed**: `BranchTreeItem`
  gained `_buildGoneMenuItems()`, routed to whenever `ref.isGone` (checked
  after the `_isRemoteOnly` branch in `_buildMenuItems()`), per 05-C's own
  target note: "gone 的列只留 Prune 與 Copy，其餘停用" (a gone row keeps only
  Prune and Copy enabled; the rest disabled). "Checkout as new local…" and
  "Delete on remote…" render but permanently disabled (`enabled: false`,
  `onTap: null`) rather than omitted — matching the spec's "停用" wording,
  and confirmed via `_GbmMenuRow` that `enabled: false` overrides `danger`
  styling too (dimmed, not red). `SidebarPanel` gained `_pruneGoneUpstream()`
  and wires it to `onPruneRef` for a gone row (guarded on
  `ref.upstream.isNotEmpty`, defensive since `isGone` is only ever computed
  for a branch with a configured upstream) — it prunes `ref.upstream` (the
  vanished remote-tracking ref, e.g. `refs/remotes/origin/feature`), not
  `ref.fullName` (the still-live local branch), per BRANCH_STATES's note:
  "真正移除 remote-tracking ref 要執行 Prune". Covered by five new tests in
  `branch_context_menu_test.dart`'s "gone row (05-C subset)" group (item set,
  both disabled items no-op on tap, Prune dispatches, dimmed-not-red
  styling) and two in `sidebar_panel_remote_branch_test.dart`'s "gone-row
  menu wiring" group (`Prune this ref` reaches the real session with the
  upstream ref; the two disabled items reach neither `commandLog` nor the
  delete-remote-branch route — the latter assertion exists because that
  action dispatches by navigation, not by session command, so a
  `commandLog`-only check can't see a regression that re-wires it). And
  `gbm_context_menus.dart`'s other 8 unwired targets remain a separate,
  larger gap this doesn't touch.
- Some spec behaviour has no backing capi entry point and is therefore
  absent rather than faked: per-object transfer counts for fetch/pull/push
  (spec page 10's "12,480 / 31,206" progress figures, reported as
  indeterminate instead), `git init` / clone (File → New repository… and
  Clone repository… are disabled, as is the switcher popover's Clone
  footer — no entry point exists in `gbm_capi.h` or `src/core`), removing a
  *scanned* repository from the switcher list (05-A's "Remove from list" is
  live for manually-opened rows, which `RecentsRepository` owns, and
  disabled for scanned ones, which would only come back on the next scan).
  ~~and open-file-at-revision / save-this-revision in 05-K~~ — **Fixed**
  (Tier 4, see below): `gbm_export_file_at_revision` is the blob-read entry
  point that was missing. Settings whose effect this layer cannot yet honour
  are likewise not offered in Preferences — see `AppPreferences`' doc
  comment.
- ~~**`TabRow`'s Merge…/Cherry-pick…/Reset… buttons bypass the action
  availability state machine**~~ — **Fixed**: `TabRow` gained a
  `conflictActive` param (stays presentational/Riverpod-free, same as
  `BranchTreeItem`/`CommitGraphView`'s param of the same name);
  `WorkspaceScreen` computes it via
  `!isActionEnabled(GbmActionId.branchMergeIntoCurrent, session)` and wires
  it in. Cherry-pick and Reset still have no `GbmActionId` of their own, so
  they share Merge's gate rather than going ungated — all three would start
  a second sequencer operation mid-conflict, the same class spec page 07
  disables. Covered by `tab_row_test.dart` (widget tier) and the new
  `test/integration/workspace_tab_row_conflict_gate_test.dart` (integration
  tier, mirrors `workspace_conflict_transition_test.dart`'s pattern —
  clean/conflict/round-trip). `MergeDialogContent` itself still does not
  independently read `session.conflictActive` (only disables "Merge" when
  no target branch is selected) — not a live gap now that the dispatch
  path leading to it is gated, but worth knowing if a future direct-link
  entry point to that dialog is added.
- ~~**`dart format --set-exit-if-changed .` is not CI-enforced**~~ —
  **Fixed**: the pre-existing 27-file drift was formatted in one
  standalone commit, then a dedicated `dart-format` job ("Dart format")
  was added alongside the C++ side's standalone "Format and layering"
  (`lint`) job rather than living as a step inside `flutter-ci`
  ("Flutter UI") — a format failure now surfaces on its own check instead
  of aborting `flutter-ci` before `flutter analyze`/`flutter test`/
  `flutter build linux` get a chance to run, and it doesn't wait on
  `capi-build` since formatting needs no native library. Both jobs were
  later split out of `ci.yml` into their own `cq.yml` workflow (same
  `pull_request` trigger), since neither builds or tests anything — they
  are pure static checks. Caught along the way: `dart format`'s output is
  not stable across Dart SDK versions —
  `subosito/flutter-action@v2`'s `channel: stable` floats, so a local Dart
  3.12.2 and a CI run on a newer stable (Dart 3.13.0 shipped a formatter
  style change) can each accept the *other's* output as "needs
  reformatting", flapping a file between two valid-but-different
  formattings depending on who last touched it. No SDK version is pinned
  here yet — worth revisiting if this recurs.
- **D (−2 pt)**: History and Working Copy are still a tab switch, not a
  combined view. This matches an industry-standard pattern (Fork, GitKraken,
  Sourcetree all do the same) and isn't treated as a defect — but it's one
  more step than zero.
- **A (−1 pt)**: T2 evidence only — no moderated user testing behind any of
  these step counts.
- A `code-review` pass was run against the full branch diff (not just this
  round's changes) as part of the loop protocol. Two of its six findings
  were spot-checked and both were false positives against intentional,
  already-documented decisions already on this branch: `app.dart`'s
  single-`ThemeVariant` switcher deliberately replaces the old
  system-following `ThemeMode` (see `theme_mode_provider.dart`'s doc
  comment), and `commitMetaCache`'s `copyWith` already defaults to
  `this.commitMetaCache`, so omitting the parameter preserves rather than
  resets the cache. Of the remaining three: ~~unbounded `commitMetaCache`
  growth~~ is **fixed** — `RepoSessionState.withCommitMeta()` now caps it
  at `_kMaxCommitMetaCacheEntries` (5000), evicting oldest-inserted entries
  once over, mirroring `operationLog`'s `_kMaxOperationLogEntries` pattern;
  see `test/data/repositories/repo_session_commit_meta_cache_test.dart`.
  ~~Skeleton-width layout jank in `commit_row.dart` and a missing widget test
  for sidebar-toggle state were **not** independently verified — still
  unconfirmed leads for whoever picks them up next, not accepted facts.~~ —
  **Resolved** (2026-08 spec-conformance audit, see below): the skeleton-width
  lead was checked directly against `commit_row.dart` and found to be no
  defect (downgraded, not fixed — there was nothing to fix); the
  sidebar-toggle lead was found to already have three passing widget tests
  covering it. Both were stale entries in this list, not open work.

### Spec conformance audit (2026-08)

A full re-audit against `docs/claude-design-demo/Flutter Desktop Spec
(standalone).html` — every page, not a diff — done on branch
`docs/spec-conformance-audit`. Unlike the "Spec conformance pass" above
(which closed gaps directly), this round's user-approved scope was
**audit-only**: no `lib/` production code changed. Full detail lives in two
generated reports (regenerate the spec extraction via
`tools/extract_design_spec.py` if the source `.html` ever changes):

- `docs/reports/spec-conformance-matrix.md` — page-by-page conformance
  table, ~78 items checked against the 12 spec pages plus shortcuts/dialogs.
- `docs/reports/code-review-2026-08.md` — architectural review (not diff
  review) of `app_flutter/lib/`, 0 CRITICAL / 2 HIGH / 3 MEDIUM / 3 LOW.

**Root cause of most drift (H1)**: `lib/features/context_menus/gbm_context_menus.dart`
fully declares all 11 spec page-05 context-menu groups, labels matching the
spec verbatim — but no file under `lib/` imports it, only `test/` does. Each
render site hand-writes its own item list instead, so 5 of 11 have drifted:
05-B (missing Rebase-onto-here/Compare-with…), 05-E (missing Merge-into-
current/Compare-with…/the whole "More actions" submenu), 05-F (missing
Stage/Open-file/Show-in-file-manager/Open-terminal-here), 05-G (missing
Discard-N-lines…), 05-K (missing Compare-with-working-copy/Open-terminal-
here plus 3 submenu items). 05-A/C/D/H/I/J conform (05-D/H/I/J via a
dedicated `*_menu_items.dart` pure function each — the template to follow
when this eventually gets fixed). Not fixed this round; tracked as skipped
regression tests (below) so a future fix flips them green one at a time.

**H1 update (Tier 1, see below)**: 05-F and 05-G now follow that template
too (`working_copy_file_menu_items.dart`, `diff_line_menu_items.dart`), so
six of eleven groups are catalog-checked with no `skip`, and 05-K's two
wireable items landed. Note the audit's own 05-F and 05-G rows were
materially wrong — see the Tier 1 section for what they got wrong and why
it moved the fix.

**H1 update (Tier 4)**: 05-K is now catalog-checked with no `skip` too
(seven of eleven), so **05-B and 05-E are the only drifted groups left**.
05-K's render site is still a private `_buildMenuItems` inside
`changed_files_panel.dart` rather than a `*_menu_items.dart` pure function
— it stayed there because its items need the container's commit oid and its
two-step export state, which the pure-function template has nowhere to put.

~~**New defect found while writing test coverage, not from static reading
(H2)**: `working_copy_view.dart`'s Commit/Amend buttons do not reactively
enable while typing a commit summary — `_summaryController` has no listener
wired to `setState`, so `canCommit` only recomputes on some *unrelated*
rebuild (e.g. staging a file), not on the summary text itself changing. The
gate logic (`canCommit`) is correct in isolation — confirmed by pre-seeding
`workingCopyDraftProvider` before mount — the defect is specifically the
missing "text changed → rebuild" wiring. Both new test suites below had to
route around this (stage-after-type ordering, or a full tab-away-and-back)
rather than a plain `enterText` + assert. Not fixed this round.~~ — **Fixed**
(Tier 0, see below): `_summaryController` now carries a listener
(`..addListener(_onSummaryChanged)`, mirroring `_diffScrollController`'s
existing pattern) that calls `setState(() {})` on every keystroke, so
`canCommit` recomputes immediately instead of waiting for an unrelated
rebuild. `test/integration/workspace_states_table_test.dart` gained a test
that drives this with a real `tester.enterText()` instead of the
provider-override workaround the pre-existing test in that file still uses
(that one verifies gate *logic*; the new one verifies the typing → rebuild
wiring, which is what H2 was actually missing).

~~**Other confirmed gaps**: `branchRenameCurrentBranch` has no keyboard
shortcut bound despite F2 being unclaimed…~~ — **Fixed** (Tier 0c, see
below). The two *other* absent bindings named there (Find-in-files,
Stash-changes) were excused as spec-internal collisions — spec's own MENUS
table double-assigned their keys. **That excuse expired on 260820**: P16's
`REVISIONS` table reassigns Find-in-files to `Ctrl/Cmd+Shift+H` and Stash
changes to `Ctrl/Cmd+Shift+S`, so both are now ordinary unbound shortcuts
with no defence. Neither is fixed here (Tier 0c scoped itself to rename);
the matrix rows are corrected and each needs its own issue. Note the Stash
one is not a free slot: `Ctrl/Cmd+Shift+S` currently belongs to
`repositoryStageAll`, so honouring the revision means re-deciding that
binding too. Two more REVISIONS casualties in the same table, both found
after the first pass at these docs and both **not** fixed here:
`repositoryStageSelectedLines` is now spec'd at `Ctrl/Cmd+Alt+S` but bound
to `Ctrl/Cmd+Shift+Enter`, and `Edit → Select all` (`Ctrl/Cmd+A`) does not
exist in `gbmMenus` at all — the latter is deliberately **sequenced after**
the multi-select work (#54), since `Ctrl/Cmd+A` is also `MULTIKEYS`' "全選
當前清單" and binding it first would give it nothing to select.

`lib/features/workspace/widgets/tab_row.dart`'s 18-item
`_MoreMenu` overflow menu plus 3 standalone buttons (Merge/Cherry-pick/
Reset) is, per this audit's user-confirmed scope rule ("beyond-spec
functionality is fine only via context menu or menu bar"), the sole
non-conforming entry surface in the app — every "extra" feature beyond the
12 spec pages (stash management, worktrees, submodules, bisect, LFS,
patches, reflog/undo, blame, file/line history, tags, remotes, operation
log, repository settings) is reachable *only* through it, and 2 of its 18
items (`Repository Settings…`, `Preferences…`) duplicate menu-bar entries
that already exist. Two competing Log implementations also still coexist:
`features/log_drawer/` (matches spec page 10's bottom-drawer design) and
the separate `operationLogDialog` route (doesn't) — **and as of 260820
that is no longer a tie to break**: P16's REVISIONS deletes the dialog
from the spec by name ("只留抽屜；operation-log dialog 從規格中刪除"), so
the route, its `_MoreMenu` entry and `features/operation_log/` are now
非規格內容. This is the ruling **#61** was waiting on. Removing a live
route is its own change with its own tests, so it is recorded, not done.

New tests added this round: `test/features/context_menus/context_menu_parity_test.dart`
asserts all 11 groups against `gbmContextMenuGroups` — the 6 conforming
groups directly, the 5 drifted ones (`05-B/E/F/G/K`) with `skip: true`
pointing back to the matrix's corresponding row, so clearing a skip is the
signal a future fix landed.
`test/integration/workspace_states_table_test.dart` locks in the 3
previously-under-tested STATES-table rows (Working copy/Commit/Status bar)
and is what surfaced H2. `test/actions/gbm_shortcuts_test.dart` gained one
`skip: true` test for the F2 gap. `integration_test/` (new — see its own
README.md) adds real-`gbm_capi`/real-temp-repo device-tier coverage for
three flows (repo lifecycle, commit, merge-conflict resolution), run
individually per platform (`-d macos`/`-d linux`/`-d windows`) rather than
as a directory — running the whole directory in one `flutter test` command
was found to be unreliable on macOS specifically (each app launch after the
first fails to attach a debug connection), not a defect in the tests
themselves.

### Tier 0 fixes (fix/tier-0-spec-conformance-gaps)

The audit above turned into 8 GitHub issues (#43–#50), grouped into tiers by
dependency risk; Tier 0 was the "independent, no shared file" batch. Per
user decision, all 8 landed as 7 sequential commits on one branch (not
parallel worktrees, not squashed) rather than the 8th (#45) — see below.
Commit order: `0b → 0a → 0h → 0f → 0d → 0e → 0g`.

- **0a / #43** (`613f80c`) — H2 above, fixed.
- **0b / #44** (`2a60b47`) — `gbm_context_menus.dart`'s 05-C doc comment
  said "Not yet wired"; `branch_tree_item.dart`'s `_buildGoneMenuItems()`
  already implemented it (confirmed by this same audit, see 05-C in the H1
  paragraph above). Comment-only fix, no behavior change.
- **0d / #46** (`2307ef7`) — History's ref chips now merge a synced
  local+upstream pair into one chip with a cloud-icon suffix instead of
  drawing both separately, and draw a dashed chip at the commit the
  upstream actually points to when the two have diverged (spec page 02).
- **0e / #47** (`a928bd5`) — the List/Tree file-view preference
  (`fileListViewModeProvider`) is spec page 03 item 10's *one* shared
  setting, but History's Changed files panel, Compare's two file lists, and
  the conflict-resolution rail each drew their own hardcoded flat list with
  no toggle. All three now read the shared provider and render through the
  same `FileListModeSwitcher`/`FileTreeFolderRow` Working Copy already
  used — proved cross-page, not just per-view, via a new
  `test/integration/workspace_file_list_view_mode_test.dart`.
- **0f / #48** (`16626b2`) — the status bar's folded "+N task" label is now
  a tappable `showMenu` popover listing every background task with its own
  Cancel button (spec page 10), not inert text.
- **0g / #49** (`3e65208`) — see its own commit message for the five
  sub-items and the capi extension (`gbm_discovery_set_base_folder_depth`,
  `RepoIndexDb`'s schema-3 `lastScanSkipped` column) two of them needed.
- **0h / #50** (`503e326`) — `operationLog`'s cap was a hardcoded module
  constant whose doc comment incorrectly claimed it mirrored
  `OperationRunner::kMaxUndoEntries` (a different, unrelated 200-entry list
  for Undo Last); it now reads `AppPreferences.logMemoryLimit`, the field
  spec's LOGRULES table actually describes ("上限寫在 Preferences，不隱
  藏").
- **0c / #45 — deliberately not in this batch**, and shipped later on its
  own branch once the blocker cleared. See "Tier 0c" below.

Two premises in the original issues were corrected during planning, not
just during implementation — worth knowing before re-reading #49/#50's
issue text literally: #50 assumed the C++ `kMaxUndoEntries` constant needed
changing in lockstep with the Flutter cap; it doesn't; they were never
actually linked. #49 assumed all five Preferences sub-items were pure
Flutter-side wiring; two needed a real capi addition, which the user
explicitly approved doing as part of this round rather than splitting into
a separate capi-only issue.

### Tier 1 fixes (fix/tier-1-spec-conformance-gaps)

Issues #51–#53, the page-05 context-menu batch. Nine sequential commits on
one branch (six for the issues themselves, then the follow-up defect, its
docs, and the device-tier e2e), same as Tier 0. **All three issues' premises turned out to be
wrong in ways that moved the work**, so read this before re-reading their
issue text:

- **#51's named render site was dead code.** `changed_file_row.dart`'s
  `ChangedFileRow` was constructed by **nothing under `lib/`** — only by
  `test/`. `WorkingCopyBoard` (`39d6303`) had replaced it and `5581538` had
  moved the real 05-F menu into `working_copy_view.dart:576`, leaving the
  widget orphaned. Consequences: the live menu already had `Open terminal
  here` (so the gap was 2 items, not 3), and the parity test was pumping the
  dead widget, so "just remove the skip" per the issue would have gone green
  against code nobody runs. The orphan and its test file were deleted in
  their own commit; `working_copy_file_menu_items.dart` is the extraction the
  parity test now checks. **Deliberate reduction while doing it**:
  `Blame…`/`File History…`/`Line History…` left this menu, because 6 spec
  items + 3 beyond-spec extras is 9 and `showGbmContextMenu` asserts spec
  page 05's own 8-item cap. `GbmMenuItem.submenu`'s flyout was not
  implemented at the time (it is now — Tier 4), so nesting them was not an
  option then. They stay reachable from `tab_row.dart`'s overflow menu,
  minus the pre-filled path — a real, accepted convenience loss, and one
  that a follow-up could now revisit since the flyout exists.
- **#52 needed a new capi, and 05-G's drift was 4 items not 1.** Spec's own
  05-G block lists `Stage 12 lines` / `Stage hunk` / `Unstage hunk` /
  `Copy lines` / `Discard 12 lines…`; the code had `Stage line`, `Copy line`,
  and ternaried between the two hunk directions. All four now match: both
  hunk items always render, with the inapplicable one carrying `enabled:
  false` **and** `onTap: null` (`enabled` alone is a visual signal — see
  `gbm_menu.dart:28`). `gbm_discard_lines` is new: `gbm_stage_lines`/
  `gbm_unstage_lines` are `git apply --cached` and only move the index, so
  discarding work-tree lines needed `git apply --reverse` without
  `--cached`. `StageOps.cpp`'s `applyPatchToIndex` was split into a
  `cached`-parameterized `applyPatch` (the four existing callers pass true,
  behavior unchanged). The patch is built with `unstaging: true` — that flag
  means "will be reverse-applied, so check the new side", which is exactly
  what a work-tree reverse apply does, and it also keeps a rename's header
  pointed at the new path so the reversal discards content without undoing
  the rename. Offered only on the unstaged side, always through the
  discard-changes dialog's new line mode.
- **#53 landed as scoped**, its 2 top-level items wired; the parity skip
  stays per the issue, with regression coverage in a targeted
  `test/integration/history_commit_file_menu_test.dart` instead — both new
  items dispatch by navigation or by an injected service, so neither shows
  up in `FakeRepoSessionController.commandLog` and a `commandLog`-only test
  could not see them regress.

**A seventh commit closes a defect the first six introduced**, found while
writing coverage for the seam between them rather than by reading the diff:
`discardLinesDialogFor`'s URL → `app_router.dart`'s inline `hunk`/`line`
parsing → the dialog's line mode had no test at any tier (the menu end and
the `gbm_discard_lines` end each did). That inline parsing cross-nulled its
two outputs — `hunkIndex: lineIndices.isEmpty ? null : hunkIndex` and the
mirror image — so a URL carrying line indices with a missing or unparsable
`hunk` silently produced *whole-file* mode: the same danger button, asked
to discard two lines, would have discarded the entire file. Parsing now
lives in `features/dialogs/discard_changes/discard_changes_request.dart`
(`DiscardChangesRequest.fromQuery`, plus `wholeFiles`/`lines`/`malformed`
constructors), and anything that asked for line mode but cannot be honoured
is `isMalformed` — the dialog then renders a `Close` button and no
destructive one at all, rather than falling back. Covered by
`discard_changes_request_test.dart` (8 malformed URL shapes) and
`discard_changes_dialog_test.dart` (which of `discardLines` vs
`restorePaths` actually fires — the assertion that matters, given the
blast-radius difference). `FakeRepoSessionController` gained a
`discardLines` override for it. The line-mode copy also changed from "will
be removed from the working copy" to "will be reverted": a discarded `-`
line is one the working copy deleted, so discarding it restores the line.

**All three flows then got real device-tier coverage** rather than the
hand-check the plan had budgeted for:
`integration_test/context_menu_flows_test.dart` drives them against the real
`gbm_capi` and a real temp repo — 05-G asserts the bytes on disk (only the
selected line reverted, the neighbouring insertion untouched, `git status`
still ` M`), 05-F asserts the absolute path handed to the OS, 05-K asserts
the router really lands on `ComparePage` with `CommitGraphView` gone. Two
things about the harness came out of writing it, both now in
`integration_test/README.md`: `build/native/libgbm_capi.dylib` is a *copy*,
so a stale one loads happily and a new capi entry point appears to be a Dart
bug; and these tests share the machine's real `shared_preferences`, where a
`panelLayout.*` splitter ratio the developer once dragged made History's
Changed files panel overlap the commit graph by ~28px — enough that a
correct `tester.tap` silently missed its hit test. `pumpRealAppOn` now
clears those keys, so geometry depends only on the code under test.

Also noted while running the C++ suite:
`UndoApiTest.UndoRefusesAfterSwitchingBranches` is flaky (~2 in 5, a 10s
`waitForRefreshesToSettle` timeout) independently of this branch —
`MergeApiTest.ConflictingMergeReportsConflictThenResolveAndCommitFinishes`
and `UndoApiTest.UndoLastOperationRevertsTheCommit` fail the same way under
a loaded parallel `ctest` and pass on re-run. Not investigated here; worth
knowing before blaming a future branch for it. Tracked as **#70**, which
also records the untested hypothesis (a fixed 10s budget losing to parallel
load) and warns against raising the timeout before confirming it — that
would paper over a real refresh-coalescing bug if one exists.

**A second flake was isolated during Tier 0c's CI run and must not be
folded into #70** — `WorkingCopyApiTest.UnstageHunkReversesAFullyStagedSingleHunkFile`
failing with `LockHeld` ("Another Git process appears to be running in this
repository", the lock being its *own* temp repo's `.git/index.lock`). Unlike
#70's shape it was **not** a timeout and **not** load-dependent: run alone
with no parallel `ctest`, it failed 1 in 12 and again at iteration 30 of 40,
each time in ~0.36s, nowhere near any timeout budget. **Fixed** — #77, closed
by PR #78 (`3f6cfa1`).

Two things about it are worth keeping, because both are the kind of mistake
that is cheap to repeat:

- **It was a real product race, not a test artifact**, and the first
  diagnosis recorded here was wrong in an instructive way. This paragraph
  used to say "a working-copy operation is reported complete before git has
  released the index lock the next one needs" — blaming the *previous
  write*. That write's lock was long gone. The actual holder was the
  **background status/diff that follows it on `sharedReadPool()`**: a
  different pool from `OperationRunner`'s single serial worker, so reads and
  writes are not serialised against each other, and a plain `git status`
  rewrites the index (and takes `.git/index.lock`) whenever its stat cache
  has gone stale. Writes never collide with writes; only a background read
  can collide with a write. The fix is `--no-optional-locks` in
  `GitCommand::globalFlags()` — see its doc comment for why it is global
  rather than tagged onto the ~28 read call sites.
- **The end-to-end flake could not be reproduced on demand afterwards, in
  either direction.** After the fix the test passed 60/60 — but so did a
  control run with the fix removed, and 40/40 under parallel `ctest` load.
  Each test uses its own temp repository, so the race is intra-process
  thread scheduling, not inter-process contention, and that stress method
  cannot surface it. The evidence for the fix is the deterministic
  mechanism test (`RealRepoTest.StatusReadDoesNotRewriteTheIndex`, red
  before and green after) plus the causal chain above — not an A/B.

**#70 is still open**, and the triage advice stands: a red capi job may be
either shape, and they need different treatment — read the failure text
before assuming. A 10s `waitFor`/`waitForRefreshesToSettle` timeout under
load is #70; anything else is new.

### Tier 5 (fix/tier-5-native-window-title) — issue closed, not implemented

Issue #60 asked for a custom Windows/Linux title bar (a window package, two
platform-project changes, a new widget). **It should not be built**, and the
one thing worth carrying forward from this round is why, because the same
mistake is cheap to repeat.

Reading spec page 01's prose instead of its mockup shows the spec asks for
the *opposite*: 「三平台統一樣式，只有 menu bar 位置與**標題列跟隨系統**」
(intent line), and item 2 of its three-item platform-differences list is
「**標題列按鈕位置與號誌燈樣式沿用系統原生**」 — where the other two items in
that same list (macOS `PlatformMenuBar`, the system file picker) plainly mean
"use the OS's own facility". The facing panel scopes Flutter self-drawing to
「視窗**內**所有內容」, putting the title bar deliberately in the other list.
The page's three mockup cards illustrate what each OS's *native* decoration
looks like — the macOS card draws traffic lights with the same placeholder
technique the Windows/Linux cards use for minimize/square/close. Relying on
native decorations, which this app already did, **is** the conforming
behaviour. `spec-conformance-matrix.md`'s row read the illustration as a
requirement; that row is now corrected in place, and #60 is closed as
not-planned rather than fixed (same convention as #45: an issue whose premise
does not survive contact with the source is closed with the evidence, not
quietly retitled). **Generalisable rule: a mockup shows what the user sees,
not who draws it — a conformance verdict has to rest on the spec's prose.**

What *did* ship is a real page-01 gap the audit missed while chasing the
imaginary one: all three mockup cards title the window `git-branch-manager`,
but every platform still used Flutter's scaffold default `gbm_flutter`.
`lib/app.dart`'s `MaterialApp.title` does not reach the OS window title on
desktop, so this lives in native runner code only — `windows/runner/main.cpp`,
both branches of `linux/runner/my_application.cc` (GNOME header bar *and* the
X11 traditional title bar; changing one leaves half of Linux wrong), and on
macOS `MainFlutterWindow.swift` plus `MainMenu.xib`. `PRODUCT_NAME` /
`BINARY_NAME` were left alone on purpose: they are also the built artifact
names and `release.yml` hardcodes `gbm_flutter.app`/`.exe` paths.

That leaves macOS's *application* name — the Apple menu, About panel, Quit
item and Dock tooltip, all of which read `CFBundleName`, i.e.
`$(PRODUCT_NAME)`, i.e. still `gbm_flutter`. Setting `NSWindow.title`
directly is display-only and does not touch it. Tracked as **#67**, which
lays out the two candidate fixes (a literal `CFBundleName` in `Info.plist`,
keeping the artifact name; or a real rename with all four `release.yml`
paths moved in lockstep) and notes the evidence is consistency, not a spec
sentence — page 01's macOS card never draws the Apple menu.

Two things found by measuring rather than reasoning, worth knowing before
touching this again:

- **macOS needs a deferred re-assignment.** Setting the title synchronously
  in `awakeFromNib`, in `MainMenu.xib`, *and* in
  `AppDelegate.applicationDidFinishLaunching` are all reverted to
  `CFBundleName` (`gbm_flutter`) before the window reaches the screen; only
  `DispatchQueue.main.async { self.title = … }` survives. That line looks
  like a redundant duplicate of the one above it, so
  `test/platform/window_title_test.dart` asserts it explicitly — delete it as
  "cleanup" and the title silently regresses.
- **A macOS debug build's app code is not in `Contents/MacOS/<name>`.** That
  file is a launcher stub with a `__debug_dylib` section; the compiled Swift
  lives in `Contents/MacOS/<name>.debug.dylib`. Grepping the stub for a
  string you just added returns nothing and looks exactly like a stale or
  cached build — several rebuilds were spent on that false lead here.

`test/platform/window_title_test.dart` asserts the three runner sources
directly. That tier choice is deliberate: no widget or integration test can
reach native runner code, and **PR CI never builds Windows at all** —
`ci.yml`'s Flutter job is ubuntu-only and `windows/runner/main.cpp` is
compiled solely by `release.yml` on tag — so this test is the only thing that
sees a Windows-side regression before a release. Same rationale as `cq.yml`'s
`flutter-action` version-pin check, which greps workflow source for the same
"nothing else can see this" reason.

The hole is one platform wider than that sentence implies: PR CI runs no
`flutter build macos` either, so `macos/Runner/` is equally uncompiled until
a tag. Only Linux is covered, by `flutter build linux --debug`. And a
source-assertion test catches a string drifting or a `flutter create`
regeneration — never a compile error. Tracked as **#69**; until it is
resolved, assume any edit under `windows/runner/` or `macos/Runner/` reaches
`main` having been compiled by nothing, and weigh the change accordingly.

One more thing this round surfaced without resolving: spec's `MSGS` Rebase
row says the step count 「只顯示在標題列」, but 標題列 means four different
things across this spec (OS title bar on page 01; dialog header on page 06;
panel header in page 02 item 16; column header row in the multi-select
table), and page 01 is the *only* place it means the OS window title. The
app already renders `rebaseStep`/`rebaseTotal` in three surfaces
(`workspace_screen.dart:1055`, `status_bar.dart:117`,
`conflict_resolve_window.dart:967`), so if this is a gap at all it is an
over-display one, not a missing feature. **#68** asks for the reading to be
settled before any code moves — implementing off a guess here is the exact
failure mode that closed #60.

### Tier 0c (fix/tier-0c-rename-branch-dialog) — issue #45, addendum

Two things worth carrying forward from the verification pass, both found by
*running* rather than by reading — see the Tier 0c section further up for
the feature itself.

**`RefInfo.hasTrackingInfo` does not mean "has an upstream".** It mirrors
git's `%(upstream:track)` (`RefStore.cpp`'s `parseTrack()`), which is an
**empty string** for a branch exactly in sync with its upstream — 0 ahead,
0 behind — even though `%(upstream)` is fully populated. The rename
dialog's first version gated its whole "Remote handling" section on
`hasTrackingInfo && upstream.isNotEmpty`, which therefore hid it for the
single most common case (a branch that was just pushed) and silently
downgraded those renames to local-only. Anything asking "does this branch
track a remote?" must read `upstream`, and reserve `hasTrackingInfo` for
"did git report ahead/behind numbers". The widget tests all passed
throughout, because the test fixture hardcoded
`hasTrackingInfo: upstream.isNotEmpty` — the same wrong assumption, written
twice, so the tests could not disagree with the code. A fixture that
derives one field from another is a fixture that cannot falsify the
derivation.

**Nothing but a device-tier test crosses the FFI signature seam.**
`test/**` runs on `FakeGbmBindings`; `tests/capi/**` calls the C++ directly;
`dart:ffi`'s `lookupFunction` matches by **symbol name only, never by
signature**. So changing a capi function's parameter list and its Dart
typedef in lockstep is checked by nothing — a mismatch compiles, analyzes,
and unit-tests clean, then corrupts the stack at runtime.
`integration_test/rename_branch_flow_test.dart` is the only thing that
would catch it for `gbm_branch_rename`. Same trap as the stale-dylib note
in `integration_test/README.md`, and it fired again here: the checked-in
copy was 21KB behind a fresh build.

### Tier 4 (fix/tier-4-file-at-revision) — issues #58 + #59

The 05-K batch, and the only tier since Tier 0h to need new `src/core` C++.
Both issues landed on one branch as sequential commits, per the user's
decision to do 4a and 4b together. **#58's implementation sketch was wrong
and was corrected during planning** — read this before re-reading its issue
text.

**The capi is an export, not a read.** #58 proposed mirroring
`gbm_request_working_tree_content`: return the file's content inline in the
event payload. But neither consumer displays content in-app — "Open file at
this revision" needs a path to hand `DesktopLauncher.openFile()`, "Save this
revision as…" needs bytes at a path the user picked, and the route tree has
no in-app file viewer at all. Following the sketch would have produced (a) a
capi whose `content` field nothing under `lib/` consumes, the orphan-wiring
pattern this repo's audits keep flagging, and (b) no support for binary
files, since a JSON string payload cannot carry one — and recovering an
image out of history is exactly the case to support. So
`gbm_export_file_at_revision(session, revision, path, destPath)` writes raw
bytes to a destination and fires `GBM_EVENT_FILE_AT_REVISION_EXPORTED` (34)
echoing all three parameters back. Same premise-correction convention as
#50/#51/#60: the reasoning is recorded on the issue and in the PR, not
silently applied.

**`IProcessRunner::run()` is not byte-exact, and nothing said so.** This was
found by measurement, not by reading: `run()` reassembles stdout from the
line splitter, which drops the final separator and strips a `\r` before
every `\n` (Windows CRLF tolerance, `ProcessRunner.cpp`'s `LineSplitter`).
A text blob therefore comes back one byte short and a binary blob is
silently corrupted wherever `\r\n` occurs. The first draft of `BlobStore`
used `run()` and its own `cat-file -s` size check caught the mismatch —
which is the only reason this is a note here rather than a bug in
production. `BlobStore` now goes through `CatFileBatch`, which reads exactly
the byte count `cat-file --batch`'s header declares straight off the pipe,
and is the per-repository co-process `docs/ARCHITECTURE.md` already
prescribes for object reads. **If you ever need verbatim stdout from git,
`IProcessRunner::run()` is not it.**

**The submenu flyout was #59's real blocker, not the capi.** `gbm_menu.dart`
rendered a `GbmMenuItem.submenu` trigger's label with a permanently-null
`onTap`, so every "More actions" item in the app was unreachable. It now
draws a chevron and opens a nested menu **on tap, not on hover** — that is
forced, not a preference: `showGbmMenu` is built on Material's `showMenu`,
which lays a modal barrier over everything beneath it, so a hover-opened
flyout would instantly make its own parent menu unhoverable. Choosing a
child closes the parent too, and the parent is popped *before* the child's
action runs: menu items routinely push a dialog, and popping afterwards
would take the dialog down instead of the menu. `gbm_menu_test.dart` has a
test that asserts exactly that ordering by pushing a route from a child and
checking it survives.

Two things that look like gaps but are deliberate:

- **"Restore file to this state" and "Restore and stage" open the same
  dialog.** `restore_file_dialog.dart` has always offered both as two
  buttons on one dialog because the confirmation text is identical; a second
  dialog would be the same dialog. Spec lists both as menu items, so both
  exist as menu items.
- **"Export as patch…" on a file row exports the whole commit.**
  `gbm_patch_export` is `git format-patch -1 <commit>` — commit-level. A
  single-file patch would be a different capi. Asserted in
  `history_commit_file_menu_test.dart` so it reads as a decision, not a bug.

`Directory.systemTemp`, not `path_provider`, backs the temp copy for
open-at-revision: no plugin channel means a widget test can exercise the
whole path, it is synchronous, and the macOS build does not run under App
Sandbox. The temp filename keeps the extension (without it the OS has no
file association) and carries the short oid (so two revisions of one file do
not collide).

`file_selector` is a new dependency, wrapped in `FileSavePicker` /
`fileSavePickerProvider` so tests can substitute it exactly as
`desktopLauncherProvider` allows. Spec page 01's platform-differences list
names the system file picker as one of the three things taken from the OS,
alongside the macOS `PlatformMenuBar` and the window title bar.
`log_drawer.dart`'s "this app has no file-picker dependency" comment was
made false by that and is corrected in place, but the drawer itself was
deliberately not switched over.

**Left open on purpose**: `gbm_context_menus.dart`'s 05-K submenu lists four
children where spec's own block lists five — `Restore file to before this
state` is missing from the catalog. That drift predates this work and was
*not* fixed here, because the catalog is the parity test's acceptance
baseline and editing it mid-fix would redefine the thing being verified.
Tracked as **#71**, which also flags that the page-05 audit's method —
comparing each render site against the catalog — could not have caught a
catalog-vs-spec drift in *any* group, so others may exist.

### Tier 0c (fix/tier-0c-rename-branch-dialog) — issue #45

The one item Tier 0 deferred, shipped once its blocker cleared. Read this
before re-reading #45's issue text: **both the issue's premise and its
deferral reason were out of date**, in opposite directions.

**The deferral reason expired.** Tier 0 scoped #45 out because there was no
design draft for the rename dialog and building one blind risked a rewrite.
That draft now exists: the spec gained four pages on 260820 (commit
`fc3bfb3`), and **P13 section A** is exactly it — layout, the two remote
options, and a `RENAMEVALID` table of five live-validation rules. Nothing
about the deferral was wrong; the condition it named simply came true.

**The issue text overstated the gap.** "Rename branch dialog + route + F2
missing" reads as though rename did not work. It did: `sidebar_panel.dart`
and `workspace_screen.dart` both renamed branches through a shared plain
`promptText` box. What was missing was the *dedicated* dialog, its route,
and the shortcut. The issue body has been corrected in place (same
convention as #60 and #50) rather than quietly retitled.

**The issue also understated the work.** It read "`gbm_branch_rename`
already exists; only wiring is missing." P13's 遠端連帶處理 section made
that false — see below.

Eight sequential commits, every one green and independently revertible.

**`gbm_branch_rename` grew three parameters** (`renameRemote`,
`remoteName`, plus an internal `askpassDir`). The remote option is
push-then-delete — git has no atomic remote rename — and it lives in
`RenameBranchOperation::run()` rather than being chained from Dart. Three
capi calls chained in the controller would produce three
`OPERATION_FINISHED` events and three error exits, against spec page 10's
one-background-task rule; `run()` was already multi-step anyway (the
case-only rename goes through a `.gbm-rename-tmp` two-stage). `TagOps.cpp`'s
`DeleteTagOperation` is the template followed throughout: local step first,
remote steps behind the flag with `askpass::wire()` and no local timeout,
and a partial-failure summary that says which half landed.

**Two things measurement caught that reading would not have:**

- **`git branch -m` keeps the upstream.** Spec says a local-only rename
  leaves the branch with no upstream, and the obvious reading is that
  renaming naturally drops the tracking config. It does not — `branch -m`
  carries `branch.<name>.remote/.merge` across, so the renamed branch
  silently still tracks the *old* remote branch. That needed an explicit
  `git branch --unset-upstream` step. Verified directly against a scratch
  repo before writing the test, precisely so the test could not pass
  vacuously.
- **`Session::submitOperation` had no unconditional hook.** `beginAskpass()`
  documents that `endAskpass()` must be paired unconditionally, but only
  `submitWorkingCopyOperation` had an `onAlways`; `submitOperation` had just
  `onSuccess`, which would leak the credential watch on failure. Rename had
  to stay on `submitOperation` (it emits `OPERATION_FINISHED`, an existing
  capi contract), so `onAlways` was added there as its own commit.

**`RefInfo.upstream` is the full ref name**, `refs/remotes/origin/main`, not
`origin/main` — it comes from `%(upstream)`, not `%(upstream:short)`. The
dialog recovers the remote with `remoteBranchParts()`; splitting on the
first slash would send `"refs"` as the remote name. **`delete_branch_dialog.dart`'s
`_remoteOf()` does exactly that split and is therefore broken today** — its
"also delete on remote" checkbox builds a request against a remote named
`refs`. Found while writing this dialog, deliberately not fixed here
(different feature, needs its own test), tracked as its own issue.

**F2 targets the current branch, not the sidebar selection.** Spec says
"sidebar 選中後按 F2", and the sidebar *does* have selection state — but
`_selected` is `SidebarPanel`'s local `State`, which
`WorkspaceScreen._buildActionHandlers()` cannot read. Lifting it into a
provider is work #54's multi-select round needs anyway. So F2 and the Branch
menu fall back to HEAD (matching the action id's own name) and the 05-B
context menu is what names a branch, via the route's `branch` query
parameter. Deliberate, not an oversight.

**Validation was extracted, not copied.** `branchNameError()`
(`features/dialogs/branch_name_validation.dart`) came out of
`new_branch_dialog.dart`'s private `_nameError`; two dialogs needing the
same rules is how two drifting copies start. The rename dialog additionally
excludes the branch's own name from the duplicate check — that is
RENAMEVALID's 未改動 row, which disables the button *without* red text.

`branch_tree_item.dart`'s Rename item gained the `conflictActive` gate the
menu and F2 paths already had through `isActionEnabled()`; it sets **both**
`enabled: false` and `onTap: null`, since `enabled` alone is only a visual
signal (`gbm_menu.dart`'s doc comment). Noted while there: `New branch from
here`, `Merge into current branch` and `Delete branch` in that same menu are
still ungated despite spec page 07 disabling all three mid-conflict — a real
gap of the same shape, left alone as out of scope for #45.

`test/integration/workspace_rename_branch_flow_test.dart` covers the seam the
widget tests cannot: F2 → handler map → route → dialog → controller. Its
value was confirmed by mutation rather than assumed — deleting the F2 binding
fails three of its four cases (the fourth, "mid-conflict F2 opens nothing",
correctly still passes).

**Docs**: `spec-conformance-matrix.md` gained a baseline banner recording
that the audit was written against 12 pages and the spec now has 16, and its
`REVISIONS`-affected rows were corrected in place — including two that had
been excused as spec-internal collisions and no longer are. P14/P15/P16 are
**not** audited; nothing under `lib/` was changed for them.
