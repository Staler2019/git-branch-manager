# Session state machine

Pin prefix `STATE-`. Format: [README.md](README.md).

Current-state reference: the one immutable snapshot per repository, its lifecycle, the 34
FFI events that republish it, and the three dispatch paths that must agree. Moved here
whole; the field and event tables are not condensed.

## [STATE-repo-session-state] `RepoSessionState`

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

## [STATE-lifecycle] Session lifecycle

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

## [STATE-ffi-events] FFI events → state (`GbmEventType`, `gbm_bindings.dart`, values 0–33)

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

## [STATE-credential-recovery] Credential and recovery flows

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

## [STATE-graph-span-index] `GraphSnapshotView.edgesSpanning()` is index-backed, not a scan

- **Rule**: `GraphSpanIndex` (`lib/data/models/graph_span_index.dart`) is built once per
  snapshot and cached on an `Expando` keyed by the snapshot instance. No invalidation exists
  because none is needed — a new snapshot is a new object, and the old entry dies with its key.
- **Rule**: its **extent comes from `edges`, not `rows`** — `edgesSpanning` is contractually a
  pure function of `edges`, and `graph_snapshot_test.dart` queries a view whose `rows` is
  empty while its edges span rows 5..20.
- **Do**: the brute-force scan lives in `graph_span_index_test.dart` as the oracle,
  deliberately not in `lib/` ([CULT-reference-impl-not-orphan] is the same shape).

## [STATE-unfiltered-row-indices] `matchingRowIndices` returns an O(1) view, not a list, when the query is empty

- **Rule**: `UnfilteredRowIndices` is read-only and computes element i as i. It is the
  commonest state of the History list, and it used to be an N-element allocation per scroll tick.
- **Do not** assume the result is mutable or materialised. `_buildList` likewise hands back
  `graph.oidsHex` itself rather than copying it when nothing is filtered.

## [STATE-refresh-entry-point] `RepoSessionController.refreshRepoStatus()` is the one entry point for "re-read the git status"

- **Rule**: its membership is a rule, not a list — **every zero-argument `refresh*` on the
  controller** (twelve of them). The `request*` methods are all excluded because they are
  keyed to a user selection that need not exist when the window comes back.
- **Rule**: both `WorkspaceScreen`'s `AppLifecycleListener.onResume` and
  `GbmActionId.viewRefresh` (F5 / `View → Refresh`) call it, so the two cannot drift into
  refreshing different things. F5 used to re-read only the history, leaving the Working Copy
  badge and diff stale on the one path where the user explicitly *asked* for fresh state.
- **Rule**: focus regain is throttled by `kFocusRefreshThrottle` (2s); F5 deliberately is not.
  The throttle clock is a `Timer`, not `DateTime.now()`, because only the former is advanced
  by `tester.pump()`.
- **Rule**: **`repoState` is the half of `conflictActive` that `refreshWorkingCopy()` does not
  cover.** `_readRepoState()` had only two callers, session open and `operationFinished`, so a
  rebase begun *or aborted* from a terminal left the status bar, the banner and the twelve
  `isActionEnabled()` gates frozen until the app itself ran an operation. `refreshRepoState()`
  is the one synchronous member (`RepoState::read()` only stats a handful of `.git/` paths),
  which is why the conflict badge corrects on the same frame.
- **Note**: **not verified on real hardware** — the tests drive
  `handleAppLifecycleStateChanged` directly, which proves the wiring but not that macOS emits
  inactive/resumed on window focus changes.

## [STATE-never-guess-what-git-would-say] Never gate a refresh on a predicate that guesses what git would answer

- **Rule**: `git submodule status` costs **79ms even with zero submodules** (`git-submodule`
  is a POSIX shell script, so it is fork + shell startup, not repository size) — 66% of
  everything `refreshRepoStatus()` added.
- **Consequence**: both candidate short-circuits, «`.gitmodules` exists» and «the index holds
  a gitlink», were rejected. Each only approximates what the command would have said, and a
  guess in core is the same mistake as a guess in Dart.
- **Note**: **`Session::refreshLfs()`'s short-circuit is not a counter-example** — its
  condition is that `git-lfs` is not on PATH, which is not approximating an answer, it is
  knowing the command cannot run.
- **Do**: ask *who is waiting on it* before treating a number as a problem. This cost was
  measured to be one nobody waits on (background pool, ≤ once per 2s, nothing on screen
  blocked), so nothing is gated at all. Reading «this number is large» as «this needs fixing»
  is the error being recorded here.
- **Evidence**: ledger: fix/focus-refresh-repo-state
