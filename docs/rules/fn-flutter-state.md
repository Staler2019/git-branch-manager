# Flutter: frames, Riverpod and provider reads

Pin prefix `FLU-`. Format: [README.md](README.md).

## [FLU-postframe-no-frame] `addPostFrameCallback` does not ask for a frame

- **Rule**: it registers a callback for the end of the *next* frame, and if nothing else
  schedules one the callback simply never runs.
- **Consequence**: a drag hides this — the drag itself keeps frames coming — so a
  notification coalesced onto a post-frame callback can work for months and then not arrive
  at all the first time a plain click drives it (`selection_touch.dart`'s `_scheduleNotify`;
  the scope a hunk-heading click had already recorded stayed invisible).
- **Consequence**: in a widget test the gap is total rather than intermittent, because
  `tester.pump()` runs a frame only `if (hasScheduledFrame)` — six pumps in a row did nothing.
- **Do**: pair every deferred notification with `SchedulerBinding.instance.ensureVisualUpdate()`.

## [FLU-no-ref-in-dispose] `ref` inside a `ConsumerState.dispose()` always throws

- **Rule**: `_assertNotDisposed()` gates every `ref` member on `context.mounted`, and the
  element is already unmounted by then.
- **Do**: capture the notifier in `initState()` into a field and guard on `StateNotifier.mounted`.

## [FLU-never-write-provider-in-build] Never write a provider from `build()`

- **Rule**: Riverpod's guard is `assert`-wrapped, so debug crashes but **release strips it and
  lets the write land mid-frame**.
- **Do**: defer to a post-frame callback and recompute from then-current state, not from a
  captured list.

## [FLU-watch-a-record-not-the-state] An unfiltered `ref.watch` of the session rebuilds the whole shell

- **Rule**: `ref.watch(repoSessionProvider(identity))` rebuilds on *every* state publish,
  including caches nothing on screen reads.
- **Consequence**: scrolling History prefetches commit metadata per scroll tick, so each reply
  republished state and rebuilt `MenuBarRow`, `PlatformMenuBarHost`, `ActionToolbar`, `TabRow`
  and `_buildActionHandlers()`. On macOS that rebuilds a real native menu bar; the reported
  symptom was 「每次捲動 menubar 都會閃爍」.
- **Do**: `WorkspaceScreen` watches a **record of the nine fields it consumes** and `read`s the
  full state — it is passed whole to ~40 sites, which `grep 'session\.'` undercounts, because
  bare `session` arguments do not match.
- **Do not** put a derived getter that builds a new collection into such a record.
  `gonePendingRefs` returns a fresh `Set` and a `Set` has no value equality, so including it
  makes the record unequal every time and **silently restores the storm it was meant to remove**.
- **Evidence**: ledger: History 捲動卡頓

## [FLU-listen-misses-the-current-value] `ref.listen` never fires for the value already present when it registers

- **Rule**: every `ref.listen`-driven piece of session state needs something else covering the
  value that was already there — a filter query surviving a repository close is the recorded case.
- **Do**: the test that sees it is the one that seeds the provider *before* pumping.
- **Consequence**: **the mirror case is that a seeded test is blind to the opposite defect.** A
  surface that reads a provider once per *mount* instead of once per *build* answers correctly
  on its only build, so `ref.watch` → `ref.read` stays green across every test that
  seeds-then-pumps. Only flipping the notifier while the tree is on screen tells the two apart —
  verified by exactly that mutation going red in
  `test/integration/soft_wrap_preference_flow_test.dart` and green in the four seeded wrap
  tests next door.
- **Evidence**: ledger: soft warp round

## [FLU-resting-state-replays-stale] An entry point gated on one resting state replays stale answers forever

- **Rule**: once the machine has terminal states. The update dialog checked on mount only from
  `idle`, but `upToDate` / `failed` / `developmentBuild` are terminal — nothing returns them to
  `idle` — so re-opening it re-showed the previous answer for the rest of the session.
- **Do**: gate on a *named predicate* over the whole enum (`UpdateState.wantsFreshCheck`) rather
  than on one value, and check whether every state the machine can rest in has a way out.
- **Note**: the partition is rarely two-way. A **standing offer** the user has not acted on is
  neither stale nor in-flight, and refreshing it costs an API call on the commonest path.
- **Do**: where a `ref.listen` fills the remaining gap, key it on the specific *transition*,
  never on "arrived at X" — `idle` is also where `dismiss()` lands, and re-checking there
  re-offers the very thing the user just declined.
- **Evidence**: ledger: 更新流程的三個缺陷

## [FLU-timeout-cannot-bound-sync] `Future.timeout` cannot bound synchronous work on the same isolate

- **Rule**: the `Timer` it arms needs the very event loop the blocking call is holding, so it
  never fires. Measured: `.timeout(100ms)` around a future whose body synchronously sleeps
  three seconds reports `completed after 3009ms`.
- **Rule**: an `async` function is no defence — its body runs synchronously up to the first
  `await`, which is exactly the shape of `_closeSessions()` (`closeAll()` then nothing).
- **Consequence**: the fix that looks right is empty, and **it goes green**: no fake-async
  widget test blocks a real event loop, so nothing at that tier can tell the two apart. This is
  [TEST-fixture-cannot-disagree] shape 11 — the fixture cannot express "synchronously blocked".
- **Do**: enforce the deadline from somewhere the isolate cannot stall. `Isolate.spawn` gives
  its own event loop on its own OS thread, and `dart:io`'s `exit()` from it is process-wide
  (measured: the process ended with the watchdog's code while the main isolate was 30 seconds
  into a synchronous sleep). `updateWatchdogEntryPoint` is the worked example.
- **Do**: keep both layers and say why in the comment — the `.timeout` is the only half a test
  can reach, the watchdog is the only half that helps on real hardware. Neither subsumes the other.
- **Evidence**: [ledger: Install and restart 卡在 Installing…](../ledger/2026-09-01-claude-windows-app-update-install-irloo0.md)

## [FLU-diff-cache-keeps-by-fingerprint] A state refresh must not clear a diff cache wholesale, and the retention condition cannot be "the path is still there"

- **Rule**: `workingCopyDiffs` used to be reset to `const {}` on every `workingCopyStatusUpdated`
  event, which forced the diff pane's spinner and re-fetch on *every* focus-regain refresh, not
  just one that actually changed anything the user was looking at. `publishWorkingCopyStatus()`
  (`repo_session_repository.dart`, fix/refresh-ui-first-tiering C2b) now keeps an entry when
  the path's own per-side fingerprint is unchanged, and drops it otherwise.
- **Rule**: **the retention condition is "this side's fingerprint is unchanged", never "this
  path is still present in `WorkingCopyStatus`".** The obvious-looking condition is wrong:
  staging a hunk leaves both sides' paths present in the status, but the diff itself is stale —
  the old doc comment on this exact code already documented why ("the next 'Stage 3 lines'
  would stage three other lines"). A path staying in the status proves nothing about whether
  *its diff* is still correct.
- **Rule**: the fingerprint is computed by `workingCopyDiffFingerprints()`, deliberately kept
  next to `workingCopyDiffKey()` so both read the same key-construction logic. Unstaged side:
  `hasUnstagedChange`, `untracked`, `worktreeStatus`, `unstagedAdded`, `unstagedRemoved`,
  `isConflicted`, `conflict`, the three blob oids, **and** `untrackedSize`/`untrackedMtimeTicks`
  (see [GIT-untracked-numstat-is-not-a-diff] for why the last two are required, not optional).
  Staged side: `staged`, `indexStatus`, `stagedAdded`, `stagedRemoved`, `oldPath`, `similarity`.
  Both sides include `isSubmodule`.
- **Rule**: an untracked entry whose `untrackedSize`/`untrackedMtimeTicks` are both `0` is
  dropped unconditionally, never compared — that pair reads `0` when the stat failed or the
  file exceeded the 1 MiB cap ([GIT-zero-means-unmeasured]'s "absorbs two conditions" shape), so
  "not measured" must never be read as "unchanged".
- **Rule**: the cache now has an explicit, tighter bound — `kMaxCachedWorkingCopyDiffs = 4` —
  rather than relying on the wholesale clear to be its own bound. The old bound was a myth: it
  only fired on the *next* refresh, so between two refreshes a user could accumulate an
  unbounded number of entries by clicking through files.
- **Do**: side attribution for the fingerprint map must **not** be re-derived at the call site —
  `entriesWithUnstagedSide` on `WorkingCopyStatus` is the one list, shared with
  `_selectedSides()`, per [CULT-single-source-of-truth].
- **Evidence**: [ledger: fix/refresh-ui-first-tiering](../ledger/2026-09-17-fix-refresh-ui-first-tiering.md)

## [FLU-app-exit-closes-every-session] Every open session must be closed before the process is allowed to quit

- **Rule**: `repoSessionProvider` is not `autoDispose` ([STATE-lifecycle]), so nothing closes a
  session while the app keeps running, and Flutter never pops a route on Cmd+Q, the window's
  close button, or File → Exit's `SystemNavigator.pop()` — there is no route to pop. Without an
  explicit close, `~Session()`'s process-wide background work (the shared read pool, in-flight
  operations) is still touching a `Session` when the OS proceeds to tear the process down,
  racing the Dart engine's own shutdown of the `NativeCallable` trampolines those background
  threads call back into on completion. That race is what produced the SIGSEGV in crash report
  `gbm_flutter` 0.48.1 build 77.
- **Do**: `AppExitSessionCleanup` (`lib/features/app_lifecycle/app_exit_session_cleanup.dart`) is
  the one thing that closes every open session before quitting — it wires Flutter's
  `AppLifecycleListener(onExitRequested:)` (the single entry point `WidgetsBinding
  .handleRequestAppExit()` fans every quit path out to) to the already-existing, already-tested
  `openRepoSessionsProvider.closeAll()` ([open_repo_sessions.dart](../../app_flutter/lib/data/repositories/open_repo_sessions.dart),
  built for the self-install flow and now a second caller of it too), and returns
  `AppExitResponse.exit`. It sits in `app.dart`'s `MaterialApp.router` builder chain, above the
  router like `AutoUpdateCheck`/`UpdateLeftoverSweep`, so it still runs from `WelcomeScreen` with
  no repository open.
- **Do**: `AppDelegate.swift` already extends `FlutterAppDelegate`, so this needed no native
  Swift/Cocoa change — Flutter's built-in `applicationShouldTerminate:` → Dart `onExitRequested`
  interception was already available.
- **Do**: test this with `tester.binding.handleRequestAppExit()`, not by reaching into
  `AppLifecycleListener`'s private state — it is the exact call the engine makes on every real
  quit path, so it exercises the real dispatch (`WidgetsBinding.handleRequestAppExit()` fans out
  to every registered `WidgetsBindingObserver.didRequestAppExit()`, and `AppLifecycleListener` is
  one such observer).
- **Note**: **known, accepted residual, not closed by this pin.** `closeAll()`'s per-session
  wait is now bounded by cancellation rather than natural completion
  ([CPP-read-pool-tasks-need-live-token]'s own Note records the multi-session caveat this
  inherits), but there is still no UI affordance to close *one* repository while the app keeps
  running — every session accumulates until the whole app quits.
- **Evidence**: [ledger: 關閉 app 時的 SIGSEGV](../ledger/2026-09-20-fix-quit-crash-session-shutdown.md)
