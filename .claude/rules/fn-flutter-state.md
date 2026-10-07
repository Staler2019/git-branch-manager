---
paths:
  - "app_flutter/lib/**"
---

# Flutter: frames, Riverpod and provider reads

Pin prefix `FLU-`. Format: [README.md](../../docs/rules/README.md). Rules a test and a site comment already carry (`ref` in `dispose()`, a provider write from `build()`, the update dialog's resting states, `Future.timeout` against a blocked isolate, the working-copy diff cache's fingerprint) live there.

## [FLU-postframe-no-frame] `addPostFrameCallback` does not ask for a frame

- **Rule**: it runs at the end of the *next* frame and never runs if nothing else schedules one; a drag hides this, a plain click does not, and `tester.pump()` runs a frame only `if (hasScheduledFrame)`.
- **Do**: pair every deferred notification with `SchedulerBinding.instance.ensureVisualUpdate()` (`selection_touch.dart`'s `_scheduleNotify`, `worktrees_panel.dart`).

## [FLU-watch-a-record-not-the-state] An unfiltered `ref.watch` of the session rebuilds the whole shell

- **Rule**: History scrolling republishes `commitMetaCache` per tick; `WorkspaceScreen` watches a `.select` record of the fields it renders and `read`s the full state, pinned both ways by `workspace_meta_cache_rebuild_test.dart`.
- **Do not**: put a derived getter that builds a new collection in the record — `gonePendingRefs` returns a fresh `Set` (no value equality), so the record is never equal and the rebuild storm returns.
- **Evidence**: ledger: History 捲動卡頓

## [FLU-listen-misses-the-current-value] `ref.listen` never fires for the value already present, and a seeded test cannot see the opposite defect

- **Rule**: something else must cover the value already there (`update_dialog.dart`'s mount check); a surface that reads a provider once per *mount* instead of per *build* passes every seed-then-pump test.
- **Do**: flip the notifier while the tree is on screen — `ref.watch`→`ref.read` in `PanelDiffText` reddens only `soft_wrap_preference_flow_test.dart`.
- **Evidence**: ledger: soft warp round

## [FLU-app-exit-closes-every-session] Every open session must be closed before the process quits

- **Rule**: `repoSessionProvider` is not `autoDispose` and Flutter pops no route on Cmd+Q, the close button or File → Exit, so nothing closes a session and their background work races the engine's teardown (SIGSEGV, `gbm_flutter` 0.48.1 build 77).
- **Do**: `AppExitSessionCleanup` (`app.dart`'s builder chain) calls `openRepoSessionsProvider.closeAll()` from `AppLifecycleListener(onExitRequested:)`; test with `tester.binding.handleRequestAppExit()`.
- **Note**: accepted residual — no UI closes *one* repository while the app runs; [CPP-read-pool-tasks-need-live-token]'s Note has the multi-session caveat.
- **Evidence**: [ledger: 關閉 app 時的 SIGSEGV](../../docs/ledger/2026-09-20-fix-quit-crash-session-shutdown.md)

## [FLU-log-row-is-replaced-by-id] A running log row is replaced by its outcome, and "unread" is a revision

- **Rule**: core records an invocation twice under one non-zero `OperationRecord.id`; `withOperationRecord` replaces the running row in place, appends the outcome when the cap already trimmed that row, and bumps `operationLogRevision` either way. id 0 never matches.
- **Consequence**: the status-bar badge compares the revision, not the list's length — a replacement leaves the length alone, and so does an append once the log is at its cap.
- **Do**: anything that must notice a log change reads `operationLogRevision`; a new log producer goes through `withOperationRecord`, never `copyWith(operationLog: …)`.
- **Evidence**: [ledger: slow-machine-log-and-timeouts](../../docs/ledger/2026-10-07-fix-slow-machine-log-and-timeouts.md)
