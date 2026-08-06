# Performance

## Scope of the table below

The numbers in this section come from `gbm_graph_check`, which links only
`gbm_core` -- no Qt, no `RepositorySession`, no `CommitListModel`, no
`cat-file` metadata fetching, no `for-each-ref`-driven UI refresh cycle. They
measure `git rev-list` streaming plus `GraphBuilder`'s lane algorithm in
isolation, and are not evidence about what the running app feels like end to
end. See "UI refresh path" below for the numbers that are.

## Measured behaviour

On a generated 200,000-commit repository (40 branches, 8% merge rate, commit-graph
written), on a single developer machine:

| Metric | Measured | Target |
|---|---|---|
| Time to first painted rows | **331 ms** | < 500 ms |
| Full graph built in background | **629 ms** | < 3 s |
| Memory for the graph | **124 bytes/commit** (≈59 MB projected at 500k) | ≤ 64 MB |
| First-parent chains that stay straight | **199,960 / 199,960** | all |
| Row order vs `git rev-list --topo-order` | **exact match** | exact match |

Reproduce with `gbm_graph_check`:

```bash
R=/tmp/fixture
git init --quiet --bare $R/.git && git -C $R config core.bare false
./build/dev/tests/gen_history --commits 200000 --branches 40 --merge-rate 0.08 \
    --octopus 3 --tags 500 --seed 42 | git -C $R fast-import --quiet
git -C $R commit-graph write --reachable --changed-paths

./build/dev/tests/gbm_graph_check $R --print-rows 40
```

`gen_history` emits a `git fast-import` stream, so the 200k-commit fixture takes
about a minute instead of hours and needs no checkout. `gbm_graph_check` verifies
the row order against Git, checks the layout invariants, prints the timings above,
and can render the first N rows as ASCII. It works the same on a real clone — a
large, long-lived open-source repository is the best test there is.

One caveat on that fixture, so the numbers are not read as more flattering than they
are: it merges randomly across the whole history, which is far more tangled than
real repositories, where merges are usually local. It therefore hits the 48-lane
render cap and pushes about 12% of edges into the overflow gutter. For comparison,
`git log --graph` needs *more* columns than we use on the same input (51 vs 31 on a
4-branch variant), so the width is a property of the topology rather than of the
lane allocator.

## UI refresh path

Unlike the section above, this measures what a refresh actually costs once
Qt, refs and commit metadata are in the loop -- the thing users reporting "it
takes a while to sync" are describing.

`gbm_graph_check` was extended to time `RefStore::load()` (`for-each-ref`)
itself, run twice in a row to mirror what `RepositorySession` used to do
before this fix (see below). On a generated repository with 50,000 commits
and **3,798 refs** (many stale branches, closer to a repository that has been
alive for years than the 40-branch fixture above), with a commit-graph
written:

| Stage | Measured |
|---|---|
| `for-each-ref` (one call) | **~0.8-2.2 s**, machine-load dependent |
| `for-each-ref` (two calls, back to back) | roughly double the one-call cost |
| Full `rev-list` walk, 50,000 commits | **~440-580 ms** |

The `for-each-ref` range is wide because, unlike the isolated `gbm_core` numbers
above, this ran on a machine doing other work across different sessions (770-850
ms on a quiet run, up to ~2.2 s once). The number that matters is not any single
digit in that range but the comparison: on both quiet and loaded runs, one
`for-each-ref` call cost as much as or more than the entire commit-graph-accelerated
`rev-list` walk of 50k commits. That comparison is what motivates the fix below,
not the absolute milliseconds.

Reproduce (the "refs:" line prints both timings):

```bash
R=/tmp/gbm-perf-fixture
git init --quiet --bare $R/.git && git -C $R config core.bare false
./build/dev/tests/gen_history --commits 50000 --branches 3000 --merge-rate 0.05 \
    --octopus 2 --tags 800 --seed 7 | git -C $R fast-import --quiet
git -C $R commit-graph write --reachable --changed-paths

./build/dev/tests/gbm_graph_check $R
```

**Finding:** on a repository with thousands of refs, a single `for-each-ref`
call costs *more* than the entire commit-graph-accelerated `rev-list` walk of
50k commits, and `RepositorySession::refreshHistory()` used to run it a
**second** time on top of whatever `refreshRefs()` had already just run
(both are always called back to back -- every call site in the app does so),
for no functional reason beyond a comment explaining the two ran as
unordered, independently-scheduled pool tasks. Isolating the field list
confirms roughly half of a single call's cost is `%(upstream:track)`
specifically (minimal `%(refname)`-only format: ~440 ms; the app's full
8-field format: ~770 ms on the same repository) -- but that field is now
load-bearing for the stale-upstream validation fix (`RefStore::refExists`,
`RefInfo::isGone`), so it isn't a safe thing to drop.

**Fix applied:** `RepositorySession::refreshRefsAndHistory()` runs the load
once, publishes it, and feeds the same `RefSnapshotPtr` into the history walk
-- no synchronization primitive needed, because (verified by reading every
call site) `refreshHistory()` is *never* called without an immediately
preceding `refreshRefs()` except from `setHistoryFilter()`, which keeps
calling the original `refreshHistory()` and still reloads on its own. Every
other call site (checkout, merge, cherry-pick, fetch, pull, stash-branch,
repo open, Refresh, window-reactivation resync, ...) now calls
`refreshRefsAndHistory()` instead, cutting one `for-each-ref` call -- on the
order of the "one call" row above, hundreds of milliseconds to low seconds
depending on machine load -- out of every one of those refreshes. Also worth
naming: this is a small behavior change on the error path. Before this fix, a
failed ref load in `refreshRefs()` did not stop `refreshHistory()`'s
independent load from possibly succeeding on its own; now a failed load in
`refreshRefsAndHistory()` aborts both. No test in this codebase exercises
`RepositorySession` directly (there is no harness for it), so this was not
regression-tested; it is judged more correct -- a session should not present a
graph built from before a ref load failure as current -- but it is a real,
deliberate change in the 8 converted call sites' error behavior.

**Deferred, not implemented in this pass** (the plan's own gate: measure
before committing to more than the stage that dominates):

- **Debouncing a burst of `refreshHistory()`/`refreshRefsAndHistory()` calls**
  (`core/workers/Debouncer.h` exists, unused) so several operations firing in
  quick succession collapse into one walk. Real, but secondary to the
  duplicate-load fix above, and needs a `QTimer`-driven integration this pass
  didn't have room for.
- **Persisting commit metadata** (`CatFileBatch`/`cat-file` results) in
  `RepoIndexDb` instead of the in-process ~20k-entry `QHash` that starts
  empty every session. Explicitly the largest remaining piece, and the
  riskiest -- a new schema, an eviction policy, and invalidation on top of
  the discovery-only cache that exists today.
- These numbers are from this machine (macOS), not the Windows machine where
  the "always re-syncs, takes a while" report originated. Process-spawn cost
  differs by platform (`CatFileBatch.h` already notes 20-40 ms per spawn on
  Windows, worse under antivirus filter drivers), so the relative weight of
  "for-each-ref cost" vs. "process-spawn count" vs. "cat-file batch cost" may
  differ there. If it's still slow after this fix, re-run the reproduction
  above on the repository in question to see which stage actually dominates
  before reaching for either of the two deferred items.

### Repo-open scheduling: the cold status scan does not block the graph walk

The same vscode investigation (`docs/reports/vscode-graph-performance.md`,
bottleneck #2) measured `git status --porcelain=v2` -- what
`WorkingCopyStatusReader` runs -- at **34.7 / 45.0 / 56.3 s wall** on the first
run after cloning 17,157 files (page-cache misses and metadata journaling
across newly-written files; 7-8% CPU, so not fixable by making the app's own
code faster). The report judged this "a resource-contention risk .. not a
serialization bottleneck" because the read pool has >= 2 threads. That
reasoning missed the *queue order*: `MainWindow::openRepository()` used to
post the working-copy scan, the stash list, and the local-identity read
before the history walk. `ThreadPool::defaultThreadCount()` clamps to
`[2, 6]`, so on a 2-thread pool (a dual-core box, or a 2-vCPU CI runner) the
graph walk was queued behind the 35-56s scan -- a real serialization
bottleneck for exactly the machines least able to absorb it.

**Fix applied:** two changes, working together.

1. `MainWindow::openRepository()` now posts `refreshRefsAndHistory()`
   immediately after `commitModel_->setSession()`, before
   `workingCopyView_->setSession()` (which is what queues the status scan).
   The history walk is the first thing on the read pool's queue instead of
   the fourth. Safe because every `RepositorySession` signal is
   `Qt::QueuedConnection` and the UI thread stays inside `openRepository()`
   until every panel is connected -- nothing can be delivered out of order.
2. `RepositorySession::refreshWorkingCopyStatusWhenIdle()` (used only by
   `WorkingCopyView::setSession()`'s repo-open call) holds the scan back via
   a small pure gate, `core/workers/StartupReadGate.h`, until the history
   walk has produced its first result -- success, error, cancellation, or the
   fingerprint-skip fast path that republishes the prior graph without
   walking. Any number of calls made before that release coalesce into
   exactly one scan; nothing is lost. Every other caller
   (`refreshWorkingCopyStatus()` itself -- staging, the Working Copy tab,
   window-reactivation resync, post-operation refreshes) stays eager and
   also opens the gate unconditionally, so a user-driven read is never held
   back by it.

Like the `for-each-ref` duplicate-load fix above, `RepositorySession` has no
test harness, so this wiring itself is not regression-tested end to end.
What *is* unit-tested is the gate's decision table
(`tests/unit/CoreBasicsTest.cpp`, `StartupReadGate` section) -- coalescing
repeated holds into one pending request, opening even with nothing pending
(so a repository that errors on open, or has no commits, never leaves the
Working Copy panel stuck empty), and idempotent release. That mirrors how the
commit-graph advice logic below was pulled out of `RepositorySession` into a
pure, testable function for the same reason.

**Not fixed, and not fixable in-app:** the cold-scan cost itself. It is
OS-level first-touch I/O, not application logic; this change only ensures it
no longer delays the one thing the user opened the repository to see.

### Auto-fetch resync signal: telling a background resync apart from the initial walk

The same vscode investigation (`docs/reports/vscode-graph-performance.md`,
bottleneck #3) found that 2 of 4 headless runs printed a **second**
`graphUpdated(complete=true)` 750ms-1s after the first, with no way to tell it
apart from "the first walk was just slow". The cause: `openRepository()` calls
`maybeAutoFetch()` (Settings > "Sync" repository setting, default on), and its
`fetchRemoteSilently()` re-triggers `refreshRefsAndHistory()` on a successful
fetch that moved refs -- likely correct behaviour, but silent.

**Fix applied:** `RepositorySession::graphUpdated(bool complete,
GraphUpdateOrigin origin)` now carries a `GraphUpdateOrigin` (`core/git/HistoryProvider.h`)
alongside `complete`. `fetchRemoteSilently()` -- `maybeAutoFetch()`'s only
caller -- is the sole call site that passes `AutoFetchResync`; every other
refresh (repo open, Refresh, filter/checkout/operation-driven refreshes)
keeps the default `Explicit`. A new `emitGraphUpdated()` helper logs the
origin before every emission (`Info` for `AutoFetchResync`, `Debug`
otherwise), so a silent background resync now leaves a distinct trace in the
operation log instead of looking identical to a slow initial walk. Both the
signal and the log line exist for the same reason: the UI can react to the
distinction later if it needs to, and any future perf gate can assert on it,
without either being blocked on this pass actually changing visible UI
behaviour.

Like the other two fixes in this section, `RepositorySession` has no test
harness, so this wiring is not regression-tested end to end. What *is*
unit-tested is `GraphUpdateOrigin::toString()` (`tests/unit/CoreBasicsTest.cpp`,
`GraphUpdateOrigin` section) -- the pure mapping both the log line and any
future assertion depend on.

### Bridge-layer timing probe: making the Qt delta visible

The same vscode investigation (`docs/reports/vscode-graph-performance.md`,
bottleneck #4) found that this section's own promise -- "unlike the section
above, this measures what a refresh actually costs once Qt ... is in the
loop" -- wasn't actually being kept. `gbm_graph_check`'s time-to-first-chunk on
the real vscode clone was **62 ms**; the real Qt app, same repository, same
state, five runs: **83, 94, 172, 916, 1069 ms**. Nothing recorded that 17x
spread. It was only visible at all because `MainWindow` had been temporarily
instrumented with timing prints for the investigation and reverted
afterward -- exactly the throwaway instrumentation this section replaces.

**Fix applied:** `RepositorySession::refreshHistory()`/`refreshRefsAndHistory()`
build a `WalkTimingProbe` (`app/bridge/WalkTimingProbe.h`) right after
`setBusy(true)` -- that instant is timestamp zero -- whenever `GBM_TIMING=1` is
set; null (and free to check against) otherwise. The probe is threaded through
the posted worker lambda, `walkHistoryWithRefs()`, and the chunk callback,
marking five points along the way:

| Mark | Where | What it isolates |
|---|---|---|
| `queue_ms` | UI request -> worker lambda entry | Read-pool wait (bottleneck #2's residue) |
| `refs_ms` | worker entry -> `for-each-ref` done | The `RefStore::load()` cost measured above |
| `walk_ms` | refs done -> chunk built in core | `rev-list` + `GraphBuilder` -- what `gbm_graph_check` measures |
| `hop_ms` | chunk built -> `emitGraphUpdated()` on the UI thread | The `Qt::QueuedConnection` latency -- the pure bridge cost this section exists to expose |
| `apply_ms` | `emitGraphUpdated()` -> `noteGraphApplied()` returns | Model reset, `widthForRows()`, status text -- UI-thread work `MainWindow::onGraphUpdated()` does |

`main.cpp` installs a `Log::TimingSink` that writes each line straight to
`stderr` when `GBM_TIMING=1` -- a separate sink from the Operation Log panel's
`MessageSink`, so a headless `QT_QPA_PLATFORM=offscreen` run (how this
investigation's own numbers were taken) prints these lines too. A refresh logs
at most two: `outcome=first-chunk` and `outcome=complete`, matching
`gbm_graph_check`'s own `time-to-first-chunk=... total=...` shape rather than
one line per chunk in `HistoryProvider`'s geometric publish schedule. The
fingerprint fast path logs `outcome=skipped` (no `walk_ms`, since no
`rev-list` ran); a failed `for-each-ref`/`rev-list` logs `outcome=failed`
directly, since that path never reaches `emitGraphUpdated()` at all; a
superseded walk logs `outcome=cancelled` the same way, unless it had already
logged a first-chunk line, in which case the cancellation is left implicit
(no `complete` line ever follows). An unreached mark prints `-`, never `0` --
see `core/base/WalkTiming.h`'s doc comment on why a skipped walk must not read
as a suspiciously fast one.

Reproduce against the same kind of fixture this section's other numbers use:

```bash
R=/tmp/gbm-timing-fixture
git init --quiet --bare $R/.git && git -C $R config core.bare false
./build/dev/tests/gen_history --commits 50000 --branches 3000 --merge-rate 0.05 \
    --octopus 2 --tags 800 --seed 7 | git -C $R fast-import --quiet
git -C $R commit-graph write --reachable --changed-paths

QT_QPA_PLATFORM=offscreen GBM_TIMING=1 GBM_SCREENSHOT=/tmp/shot.png GBM_SCREENSHOT_REPO=$R \
    ./build/dev/src/app/git-branch-manager 2>&1 | grep gbm-timing
```

Sample output against a 5,000-commit fixture on this machine:

```
gbm-timing walk origin=explicit outcome=first-chunk rows=256 queue_ms=0 refs_ms=86 walk_ms=21 hop_ms=0 apply_ms=0 total_ms=107
gbm-timing walk origin=explicit outcome=complete rows=5000 queue_ms=0 refs_ms=86 walk_ms=25 hop_ms=1 apply_ms=1 total_ms=113
```

`hop_ms` and `apply_ms` read near-zero here -- consistent with `docs/PERFORMANCE.md`'s
recurring point that the number that matters is the comparison, not any single
run's digits: this section exists so that on a machine or a repository where
the bridge overhead *isn't* negligible, the `queue_ms`/`refs_ms`/`walk_ms`/`hop_ms`/`apply_ms`
breakdown says which segment to chase instead of leaving the whole refresh as
one undifferentiated number.

Like the other fixes in this section, `RepositorySession` has no test harness,
so this wiring is not regression-tested end to end. What *is* unit-tested is
the pure formatting and env-gate logic behind it -- `formatWalkTiming()`,
`toString(WalkOutcome)`, and `walkTimingEnabledForValue()`
(`tests/unit/CoreBasicsTest.cpp`, "walk timing" section) -- including the
dash-for-unreached-mark behavior and that `total_ms` falls back to the last
mark actually reached rather than always requiring `apply_ms`.

**Not covered:** no CI job measures this. `perf-nightly.yml` builds
`--preset core-only`, which links no Qt, so it cannot exercise
`RepositorySession` or the bridge probe at all; adding a Qt job there is next
in line if this trend ever needs unattended tracking (see this file's own
"Deferred, not implemented in this pass" precedent above). For now this is a
manual, on-demand probe, same tier as the vscode-scale reproductions
`docs/reports/vscode-graph-performance.md` itself names as "manual/local only,
not automated."

## Repository performance settings

`commit-graph` is the single largest lever this app controls, and until now
it was entirely unmitigated: an investigation against a real 162,368-commit
`microsoft/vscode` clone (`docs/reports/vscode-graph-performance.md`) found
that removing the commit-graph moved time-to-first-chunk **62 ms -> 898 ms
(14x)** and the full walk **195 ms -> 1027 ms (5.3x)** -- and that this
section previously *described* an opt-in prompt for building one that had
never actually been built. It writes into your repository, so the app asks
first and remembers your answer, non-modally, after the first history paint
(`MainWindow`'s dismissible perf hint) -- with the same choice also available
any time from Repository Settings > Performance > "Keep commit-graph up to
date". See `core/git/ops/MaintenanceOps.h` for the decision logic
(`shouldOfferCommitGraph`, pure and unit-tested) and
`RepositorySession::writeCommitGraph()` for the write itself
(`git commit-graph write --reachable [--changed-paths] [--split]`, gated on
the git version's `GitCapabilities::commitGraphSplit`/`changedPathBloom`).

Not yet wired to an in-app prompt -- worth revisiting the same way, once
there's a measurement to justify it:

```bash
git multi-pack-index write --bitmap
git config feature.manyFiles true      # index v4
git config core.fsmonitor true         # git >= 2.37; huge win for status
git config core.untrackedCache true
```

## Commit-graph speedup gate

A same-run A/B ratio test (`commit_graph_speedup_ratio`, `perf` label) proves
the commit-graph delivers the speedup above and keeps delivering it. It is
**not** a pull-request gate -- `tests/CMakeLists.txt`'s own label comment
explains why: a shared CI runner is far too noisy for an absolute-millisecond
assertion. This session's own measurements make the point directly: the
identical operation on the identical warm repository swung **83 ms -> 1069
ms** across five back-to-back runs of an unchanged binary. An absolute gate
wide enough to survive that spread would catch nothing; a ratio measured
seconds apart on one machine, in one process, is stable in a way neither
arm's absolute value is.

**Mechanism:** `gbm_graph_check --commit-graph-ab N --min-graph-speedup F`
toggles git's use of an *existing* commit-graph via the `GIT_CONFIG_COUNT` /
`GIT_CONFIG_KEY_0=core.commitGraph` / `GIT_CONFIG_VALUE_0` environment
variables (needs git >= 2.31; the tool refuses to measure below that rather
than silently reporting a false ~1.0x "regression"), rather than writing or
deleting the commit-graph file between arms. Nothing on disk changes between
the two measurements -- same pack, same inodes, same warm page cache -- which
is what a physically-mutating A/B would confound. `N` off/on pairs run with a
discarded warm-up walk first and the no-graph arm always first in each pair
(biasing *toward understating* the speedup, so a pass can never be an
ordering artefact); the gate asserts on the **median** of the `total` walk time,
and reports (but does not gate on) time-to-first-chunk, which is the more
dramatic number but a single instant, one descheduling away from a wrong
answer.

**Calibration** (this machine, git 2.55.0, `gen_history --branches 12
--merge-rate 0.10 --octopus 3 --tags 25 --seed 42`, median of 5 pairs):

| Commits | graph off (median) | graph on (median) | speedup | on-arm vs. 50ms floor |
|---|---|---|---|---|
| 25,000 | 113 ms | 32 ms | 3.5x | **fails** -- under the floor |
| 50,000 | 229 ms | 57 ms | 4.0x | 7 ms margin |
| 75,000 | 347 ms | 85 ms | 4.1x | 35 ms margin |
| 100,000 | 449 ms | 107 ms | 4.2x | 57 ms margin |

`gbm_graph_check` refuses to trust a measurement below a 50 ms floor: under
that, 1 ms clock resolution and process-spawn cost are a large fraction of
the number and the ratio stops meaning anything. 25,000 commits -- a
reasonable-looking fixture size on paper -- fails that floor outright with
this measurement method, which is exactly the failure mode the floor exists
to catch loudly rather than silently pass on noise. **Chosen: 100,000
commits, `MIN_SPEEDUP=2.0`** (roughly half the measured median, leaving
headroom for a CI runner meaningfully faster or slower than this one) --
`GBM_PERF_COMMITS`/`GBM_PERF_SAMPLES`/`GBM_PERF_MIN_SPEEDUP` in
`tests/CMakeLists.txt`. Full cycle (fixture generation + import +
commit-graph write + 5 measured pairs) is ~30 s locally.

Reproduce by hand:

```bash
cmake --build --preset core-only --target gen_history gbm_graph_check
R=/tmp/gbm-perf-fixture
git init --quiet --bare $R/.git && git -C $R config core.bare false
./build/core-only/tests/gen_history --commits 100000 --branches 12 --merge-rate 0.10 \
    --octopus 3 --tags 25 --seed 42 | git -C $R fast-import --quiet
git -C $R commit-graph write --reachable --changed-paths

./build/core-only/tests/gbm_graph_check $R --commit-graph-ab 5 --min-graph-speedup 2.0
```

Or via CTest: `ctest --preset perf` (excluded from `dev`/`core-only`'s default
run; wired into CI only via the nightly `.github/workflows/perf-nightly.yml`,
which publishes the measured numbers to the run's Step Summary rather than
just pass/fail, following this file's own "range, not a single digit"
convention above).

**Companion PR-gate tests**, both deterministic and label `unit` (they gate
every preset including the sanitizers), catching the exact regression class
that motivated the fix in "UI refresh path" above without any timing
involved:

- `RefStore.LoadsEveryRefWithASingleForEachRefInvocation`
  (`tests/unit/ProcessRunnerTest.cpp`) -- asserts `for-each-ref` is invoked
  exactly once per `RefStore::load()`, via `FakeProcessRunner`'s invocation
  log.
- `no_duplicate_ref_refresh_call_sites`
  (`tests/cmake/CheckNoDuplicateRefRefresh.cmake`) -- a source check, not a
  runtime one, following the precedent of `ci.yml`'s "core must not depend on
  Qt" grep. `RepositorySession` builds its own `IProcessRunner` in its
  constructor with no injection seam and delivers everything through a
  `ThreadPool` and queued Qt signals, so a runtime assertion here would need a
  seam this codebase doesn't have (see "No test in this codebase exercises
  `RepositorySession` directly" above, which remains true and is now
  deliberately so) for a bug whose entire shape -- `refreshRefs()` and
  `refreshHistory()` called back to back instead of
  `refreshRefsAndHistory()` -- is visible in the source text.
