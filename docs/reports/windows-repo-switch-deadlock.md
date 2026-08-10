# Capturing a repo-switch deadlock log (Windows, issue #23)

## Scope

This is instrumentation, not a fix. It has not reproduced on macOS, so the
only thing this round can produce is evidence: a log that shows whether a
stuck session is stuck *inside* `ThreadPool::cancelQueuedAndDrain()` or
somewhere else. See [#23](https://github.com/Staler2019/git-branch-manager/issues/23)
for the suspected code path (`MainWindow::closeRepository()` calling
`readPool_.cancelQueuedAndDrain()` on the UI thread with no deadline).

## Reproducing and capturing the log

1. Launch the app with `GBM_LOG_LEVEL=debug` set in the environment. The
   default level is `Info`, which filters out the per-switch diagnostics
   below -- they are too frequent (they fire on every repository close) to
   leave visible otherwise.

   ```
   set GBM_LOG_LEVEL=debug
   git-branch-manager.exe
   ```

2. Open the Operation Log panel (`Ctrl+L`) so it's visible while you work --
   it receives every log message regardless of level, not just git command
   records.
3. Switch between repositories repeatedly (the reports describe several
   switches before the window goes white and stops repainting).
4. When the window freezes, wait a few seconds, then use the panel's
   **Copy all** button if the UI is still responsive enough to click it. If
   the UI is fully unresponsive, the log content up to the freeze is still
   what's needed -- a screenshot of the panel, or the log lines from a
   previous responsive moment, are enough.

## What to look for in the captured log

Two lines matter:

- `<pool name> pool cancelQueuedAndDrain: discarded N queued task(s), M still
  running` -- written by `ThreadPool::cancelQueuedAndDrain()` every time it's
  called, at Debug level.
- `closeRepository: cancelQueuedAndDrain took <ms>ms (queueDepth=<n>,
  threadCount=<n>)` -- written by `MainWindow::closeRepository()` at Warn
  level (so it appears even without `GBM_LOG_LEVEL=debug`) only when the
  drain took at least 2 seconds.

If the freeze coincides with a `closeRepository: cancelQueuedAndDrain took
...` warning, the stall is confirmed to be inside the drain -- most likely a
single already-in-flight read whose pipe read has no deadline (see
`ThreadPool::cancelQueuedAndDrain`'s doc comment in
`src/core/workers/ThreadPool.h`). If the window goes white with no such
warning anywhere near the freeze, the stall is somewhere else, and the next
issue should look elsewhere in `closeRepository()` or the UI thread.

## Attaching the report

Please attach to the GitHub issue:

- The captured log lines (both kinds above, from the run that froze).
- Windows version and whether the repository involved is local, on a
  network share, or backed by an antivirus/EDR agent that hooks file I/O
  (a common source of unbounded child-process reads).
- Roughly how many repository switches preceded the freeze.
