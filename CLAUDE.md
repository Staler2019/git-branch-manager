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
    dialogs/         The 24 repo-scoped dialog contents listed above, plus the 3 app-wide ones
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

### FFI events → state (`GbmEventType`, `gbm_bindings.dart`, values 0–26)

| # | Event | # | Event |
|---|---|---|---|
| 0 | graphUpdated | 14 | fileHistoryReady |
| 1 | refsUpdated | 15 | lineHistoryReady |
| 2 | errorOccurred | 16 | reflogReady |
| 3 | operationFinished | 17 | rebasePlanReady |
| 4 | workingCopyStatusUpdated | 18 | submodulesUpdated |
| 5 | workingCopyOperationFinished | 19 | bisectStatusUpdated |
| 6 | workingCopyDiffReady | 20 | lfsUpdated |
| 7 | stashesUpdated | 21 | cleanPreviewReady |
| 8 | stashDiffReady | 22 | localIdentityUpdated |
| 9 | worktreesUpdated | 23 | effectiveIdentityUpdated |
| 10 | remotesUpdated | 24 | commitGraphWriteFinished |
| 11 | credentialRequested | 25 | workingTreeContentReady |
| 12 | operationLogRecord | 26 | commitMetaReady |
| 13 | blameReady | | |

`event_dispatcher.dart` is a thin bridge only: a `NativeCallable.listener`
copies each native event's payload bytes (avoiding dangling pointers), frees
the native buffer, and pushes a `GbmEvent` onto a broadcast `Stream`. All
per-event-type interpretation — which of the 27 event types updates which
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
  resets the cache. The remaining four (skeleton-width layout jank in
  `commit_row.dart`, unbounded `commitMetaCache` growth, a missing widget
  test for sidebar-toggle state) were **not** independently verified —
  they're unconfirmed leads for whoever picks them up next, not accepted
  facts.
