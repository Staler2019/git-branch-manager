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
  disabled for scanned ones, which would only come back on the next scan),
  and open-file-at-revision / save-this-revision in 05-K. Settings whose effect
  this layer cannot yet honour are likewise not offered in Preferences —
  see `AppPreferences`' doc comment.
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

**New defect found while writing test coverage, not from static reading
(H2)**: `working_copy_view.dart`'s Commit/Amend buttons do not reactively
enable while typing a commit summary — `_summaryController` has no listener
wired to `setState`, so `canCommit` only recomputes on some *unrelated*
rebuild (e.g. staging a file), not on the summary text itself changing. The
gate logic (`canCommit`) is correct in isolation — confirmed by pre-seeding
`workingCopyDraftProvider` before mount — the defect is specifically the
missing "text changed → rebuild" wiring. Both new test suites below had to
route around this (stage-after-type ordering, or a full tab-away-and-back)
rather than a plain `enterText` + assert. Not fixed this round.

**Other confirmed gaps**: `branchRenameCurrentBranch` has no keyboard
shortcut bound despite F2 being unclaimed by anything else in spec's MENUS
table (unlike two *other* absent bindings — Find-in-files, Stash-changes —
which are absent because spec's own table double-assigns their key to
something else; this one is a genuine omission). It compounds with the
`Rename branch` dialog route itself being entirely missing from
`route_paths.dart`. `lib/features/workspace/widgets/tab_row.dart`'s 18-item
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
the separate `operationLogDialog` route (doesn't).

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
