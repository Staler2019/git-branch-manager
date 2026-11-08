---
paths:
  - "src/**"
  - "tests/**"
  - "CMakeLists.txt"
---

# C++ core

Pin prefix `CPP-`. Format: [README.md](../../docs/rules/README.md).

## [CPP-run-not-byte-exact] `IProcessRunner::run()` is not byte-exact

- **Rule**: it reassembles stdout from the line splitter, dropping the final separator and stripping `\r` before every `\n`; a text blob comes back one byte short, a binary blob is corrupted.
- **Do**: for verbatim bytes use `CatFileBatch`, which reads exactly the count `cat-file --batch`'s header declares.

## [CPP-read-pool-tasks-need-live-token] A `sharedReadPool()` read posted from `Session` carries `readCancel_.token()`, never `CancellationToken{}`

- **Rule**: a default token has a null `state_`, so `onCancel()` is a no-op and that read can never be cancelled; `~Session()`'s `cancelQueuedAndDrain()` then waits out whatever a worker is running.
- **Do**: pass `readCancel_.token()` (`Session.h`, doc on `readCancel_`); a read posted by another owner needs its own source.
- **Note**: known residual — the pool is shared by every open session and `closeAll()` closes them one at a time, so A's drain can still wait on B's un-cancelled read; a two-phase shutdown would close it, not built.
- **Evidence**: [ledger: 關閉 app 時的 SIGSEGV](../../docs/ledger/2026-09-20-fix-quit-crash-session-shutdown.md)

## [CPP-windows-terminate-hangs-join] Windows 的 pump／terminate 只有 Windows CI 測得到，POSIX 那半邊不要為了對稱去改

- **Rule**: POSIX 是單一 `poll()` 迴圈、沒有執行緒要 join，`terminate()` 已是 SIGTERM→SIGKILL；改它只會製造沒有任何一層測得紅的分支。
- **Rule**: `ProcessRunnerTimeout.AChildThatNeverWritesIsStillTimedOut` 在 macOS/Linux 永遠是綠的，只有 Windows CI 能反駁（它的紅是 hang，由 ctest deadline 轉成 `***Timeout`）。
- **Evidence**: `ProcessRunner.cpp` 的 `WindowsChild`；[ledger: 追加，Windows CI 卡 81 分鐘](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)；量測與方法：`docs/reports/windows-process-cost.md`

## [CPP-interactive-reads-go-to-the-front] A read the user is waiting on takes `postFront()`; a sweep member takes `post()`

- **Rule**: `ThreadPool` is a FIFO deque; `refreshWorkingCopy()`/`dispatchRefresh()` stay on `post()` on purpose, or "interactive" stops meaning anything.
- **Do**: `postFront()` cannot preempt running work, so `refreshRepoStatus()`'s tier 2 is also deferred (`Timer(Duration.zero)`, `repo_session_repository.dart`); neither technique substitutes for the other. Never assert the relative order of two `postFront()`'d replies; each merges under its own key.
- **Evidence**: [ledger: fix/refresh-ui-first-tiering](../../docs/ledger/2026-09-17-fix-refresh-ui-first-tiering.md)

## [CPP-every-command-has-a-deadline] No git invocation runs without a finite deadline

- **Rule**: `effectiveDeadlines()` (`GitCommand.cpp`) is the one place that decides. A local command gets `min(declared timeout or kLocalCeiling, kLocalCeiling) × multiplier` (ceiling 300 s); a network command (`isNetworkCommand`: fetch, pull, push, clone, submodule update/add, lfs fetch/pull/push — **not** `ls-remote`) gets no total limit and `kNetworkIdle` (60 s) × multiplier without data. `timeout = 0` no longer means "none".
- **Consequence**: the classification is central, so a *new* network-shaped command that is missing from `isNetworkCommand` silently becomes a 300 s local command — wrong for a large transfer. `ls-remote` stays out because it rejects `--progress`, which `withTransferProgress()` adds to every network command.
- **Do**: add a new network command to `isNetworkCommand` and its test in `EffectiveDeadlines`; never add an "unlimited" escape hatch. `CatFileBatch` is bounded the same way (`kRequestDeadline`, 30 s × multiplier — a proposed figure, not a measured one).
- **Evidence**: [ledger: slow-machine-log-and-timeouts](../../docs/ledger/2026-10-07-fix-slow-machine-log-and-timeouts.md)

## [CPP-progress-is-the-network-liveness-signal] A pipe carries git's progress only if asked

- **Rule**: git prints no transfer progress to a pipe by default (`clone --quiet` wrote 0 bytes for its whole run), so a no-data deadline cannot tell a live transfer from a hung one without `--progress`. stderr `\r` redraws are collapsed to each line's last state (`collapseCarriageReturns`) before they reach a record or an error; `\r\n` is a line end, not a redraw.
- **Consequence**: the Windows pump reads stderr on its own thread and updates the progress clock per chunk; nothing but Windows CI tests that (`ProgressOnStderrAloneKeepsAChildAlive`, `AFetchReportsProgressThroughThePipe`). `GIT_LFS_FORCE_PROGRESS=1` for lfs is unmeasured — git-lfs was not installed when it was written.
- **Do**: do not claim Windows progress capture works from a macOS run; read the Windows job.
- **Evidence**: [ledger: slow-machine-log-and-timeouts](../../docs/ledger/2026-10-07-fix-slow-machine-log-and-timeouts.md)

## [CPP-child-gets-only-its-own-pipes] A spawned git must inherit only its own pipe ends

- **Rule**: POSIX pipes come from `posix::makeCloexecPipe` and every `posix_spawnp` takes `posix::initSpawnAttr` (`base/PosixPipe.h`); every `CreateProcessW` takes a `win::InheritList` (`base/WinHandleList.h`) and refuses to spawn without one.
- **Consequence**: a write end that leaks into a long-lived process — `fsmonitor--daemon` started by `git worktree add`, or a sibling `cat-file --batch` — keeps the pipe open after git exits; the read loop never sees EOF, the operation shows RUNNING until its deadline, and its onSuccess refresh never runs.
- **Do**: a new spawn site uses both helpers; test with `hang_forever --detach-grandchild` (POSIX) or `--probe-handle` (Windows, CI only).
- **Evidence**: [ledger: feature-worktree-checkout](../../docs/ledger/2026-10-08-feature-worktree-checkout.md)

## [CPP-exception-text-reaches-the-screen] A thrown exception's `what()` reaches every open repository's Log

- **Rule**: `reportCurrentException` sends the summary to the Log of the window and of every open repository, and the full description to a file a bug report attaches. A filesystem error is reduced to type and code on screen; every other `what()` is shown as it is, behind only `redactUrlCredentials`, whose known gaps are in the ledger.
- **Consequence**: safe today because `src/` has no data-bearing `throw` (only the standard library throws, and the one in `NativeError.cpp` is test-only). The first `throw` carrying a path, URL or file content makes that text visible across repositories.
- **Do**: put no user data in a `what()` or in `where`; `where` is a function name or a type name, never `describe()`. A sink runs under a lock, so it must not report.
- **Evidence**: [ledger: feat/native-error-channel](../../docs/ledger/2026-11-05-feat-native-error-channel.md)

## [CPP-crash-filter-allocates-nothing] The Windows crash filter touches only static buffers, and any process that may crash under test sets `GBM_CRASH_NO_DIALOG`

- **Rule**: `CrashFilter.cpp`'s filter runs on the faulting thread, possibly on an overflowed stack or holding the heap lock: ~~no allocation,~~ no allocation in our code (`CreateFileW`/`CreateDirectoryW` still allocate inside the OS when they convert the path), no `std::string`, no `std::filesystem`, nothing that pumps messages. Everything it needs is filled at install time; the dialog is shown by a thread started then.
- **Consequence**: without `GBM_CRASH_NO_DIALOG=1` a crash with no visible window blocks on a box nobody clicks until the job timeout. `ProcessTempDir.cpp` sets it for every C++ test binary; `ci.yml`'s "Real library reports across FFI" step sets it for Dart.
- **Do**: a new CI step or test binary that loads the real `gbm_capi.dll` sets it too. ~~The dialog itself has no automated test; read the Windows job for the rest.~~ The dialog is tested from `CrashFilterApiTest`, which unsets it for one child at a time; read the Windows job, since none of it runs on macOS.
- **Evidence**: [ledger: feat/crash-and-dart-error-log](../../docs/ledger/2026-11-07-feat-crash-and-dart-error-log.md)

## [CPP-read-throw-still-replies] A read reaches `sharedReadPool()` only through `postRead`, and its `onFailure` sends what its ordinary failure sends

- **Rule**: the pool's own catch only logs, so a read that throws never answers and Dart waits on it for good; `postRead` (`Session.cpp`) logs as before and then calls `onFailure`. `scripts/check-read-pool-posts.py` (`cq.yml`) rejects any other post.
- **Do**: `onFailure` emits exactly what the read's non-throwing failure path emits — `errorReply()` for `ERROR_OCCURRED`, or the read's own reply built by the same payload function (requestId, destPath, source, path). A Dart reader that matches on `argv` needs it set by hand (`requestRemotePrunePreview`); a guard the body needs on every path goes in `onAlways`, since an injected throw fires before the body.
- **Do**: test with `gbm_test_fail_read("Session::<method>")`, which fails only the next read posted under that name, so a session's own reads cannot use it up.
- **Evidence**: [ledger: feat/stuck-waits](../../docs/ledger/2026-11-09-feat-stuck-waits.md)
