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
