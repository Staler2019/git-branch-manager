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
