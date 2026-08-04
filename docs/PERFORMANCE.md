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

`commit-graph` and `multi-pack-index` are the difference between a fast browse and a
slow one, but they write into your repository, so the app asks first and remembers
your answer:

```bash
git commit-graph write --reachable --changed-paths --split
git multi-pack-index write --bitmap
git config feature.manyFiles true      # index v4
git config core.fsmonitor true         # git >= 2.37; huge win for status
git config core.untrackedCache true
```
