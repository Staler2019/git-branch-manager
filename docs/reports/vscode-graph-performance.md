# Git graph page performance: microsoft/vscode

Investigation report, 2026-08-04. Ad hoc test against a real large open-source
repository, done by hand — not automated, not part of CI. See "Performance gate
design" below for what should move into CI.

## Method

Cloned `microsoft/vscode` shallow (`git clone --depth 1`), then unshallowed it
(`git fetch --unshallow`). A depth-1 clone gives the graph algorithm nothing to
walk (1 commit) — it only exercises repository discovery on a large working
tree (17,157 files). Testing the graph page itself needs real history, so the
clone was deepened to get the repository's actual 162,368-commit history.

Built both the `core-only` preset (`gbm_graph_check`, `gen_history` — no Qt)
and the full `dev` Qt app. `MainWindow::openRepository` /
`onGraphUpdated` were temporarily instrumented with timing prints, the real
app was run headlessly (`QT_QPA_PLATFORM=offscreen`) against the vscode clone
several times, and the instrumentation was reverted afterward (not committed).

Repository shape after unshallowing: 162,368 commits, 30 refs (27 tags, 1
local branch — a fork clone, so far fewer refs than the live GitHub repo),
1.2 GB `.git`, 17,157 tracked files, commit-graph present.

## Bottleneck table

| # | Bottleneck | Evidence (this session, real vscode repo unless noted) | Root cause | Resolution |
|---|---|---|---|---|
| 1 | **Missing commit-graph** | First chunk 62ms→**898ms** (14x), full walk 195ms→**1027ms** (5.3x) on the same 162k-commit repo with the commit-graph removed vs present | `git rev-list --topo-order` must compute generation numbers/reachability from raw objects instead of the precomputed index | **Correction (this row was wrong):** this was *not* already implemented. `docs/PERFORMANCE.md`'s "Repository performance settings" described an opt-in prompt in the present tense, but the only trace in `src/` was a dormant, unread `GitExecutable::commitGraphSplit` capability flag — no prompt, no trigger, nothing on first repo add. Since fixed: `MainWindow` offers a non-modal, dismissible hint after the first history paint on a large repository with no commit-graph (`shouldOfferCommitGraph()` in `core/git/ops/MaintenanceOps.h`, pure and unit-tested), persisted per repository and also reachable from Repository Settings > Performance. See `docs/PERFORMANCE.md`'s "Commit-graph speedup gate" section for the same-run A/B test that now guards this regressing silently again. |
| 2 | **Cold first-touch filesystem I/O after a fresh clone** | `git status --porcelain=v2` (what `WorkingCopyStatusReader` runs) took **34.7s / 45.0s / 56.3s wall** (vs 1–3.6s CPU — 7-8% utilization) on first run after cloning 17,157 files; warm reruns: **~30ms**. Controlled A/B ruled out fsmonitor: disabling it made the cold run *slower* (56.3s vs 45.0s), not faster. | Not git or app logic — page-cache misses / metadata journaling / OS-level first-touch cost across ~17k newly written files. | **Correction (this row's "not a serialization bottleneck" claim was wrong):** the "≥2 threads, so just contention" reasoning ignored queue *order*. `MainWindow::openRepository()` used to post `refreshWorkingCopyStatus()` (via `WorkingCopyView::setSession()`) three tasks *before* `refreshRefsAndHistory()`, so on a 2-thread pool (`ThreadPool::defaultThreadCount()` clamps to `[2,6]`) the graph walk could sit queued behind the cold scan for its full 35–56s. Since fixed: `refreshRefsAndHistory()` is now posted first, and the repo-open status read goes through `RepositorySession::refreshWorkingCopyStatusWhenIdle()`, gated by a small pure type (`core/workers/StartupReadGate.h`, unit-tested in `tests/unit/CoreBasicsTest.cpp`) that holds it until the history walk's first result (success, error, cancel, or the fingerprint-skip fast path). Every user-driven call (staging, the Working Copy tab, resync) stays eager and opens the gate unconditionally. See `docs/PERFORMANCE.md`'s "Repo-open scheduling" section. The cold-scan cost itself remains unfixed and unfixable in-app — this only stops it from delaying the graph. |
| 3 | **Silent second graph rebuild from auto-fetch** | Headless app runs against vscode: 2 of 4 runs printed a **second** `graphUpdated(complete=true)` 750ms–1s after the first. Not visible in `gbm_graph_check` (no network path) or in `docs/PERFORMANCE.md`. | `openRepository()` unconditionally calls `maybeAutoFetch()` (Settings › `autoFetchOnOpen`, default true); the resulting real fetch against `github.com` moves refs and re-triggers the history walk. | Likely correct behavior, but was indistinguishable from "the first walk was just slow." **Since fixed:** `RepositorySession::graphUpdated(bool complete, GraphUpdateOrigin origin)` now carries a `GraphUpdateOrigin` (`core/git/HistoryProvider.h`, pure and unit-tested); `fetchRemoteSilently()` (`maybeAutoFetch()`'s only caller) tags its resync `AutoFetchResync`, every other call site keeps `Explicit`, and a new `emitGraphUpdated()` helper logs the distinction (`Info` for the resync, `Debug` otherwise) before every emit. See `docs/PERFORMANCE.md`'s "Auto-fetch resync signal" section. |
| 4 | **Qt/bridge-layer overhead is undocumented and volatile** | Core-only first-chunk on this exact repo/state: **62ms**. Real Qt app, same repo, 5 runs: **83, 94, 172, 916, 1069ms**. | `docs/PERFORMANCE.md` explicitly scopes itself to the Qt-free core: *"not evidence about what the running app feels like end to end."* That gap is real and currently unmeasured/untracked. | **Since fixed:** a permanent, env-gated (`GBM_TIMING=1`) probe now decomposes every history refresh into `queue_ms`/`refs_ms`/`walk_ms`/`hop_ms`/`apply_ms`, logged to stderr so headless runs (how this row's own numbers were measured) reproduce it too. `hop_ms` is the isolated `Qt::QueuedConnection` cost this row asked for; the other four segments came along for free from the same probe and place the rest of the 17x spread instead of leaving it as one undifferentiated number. See `app/bridge/WalkTimingProbe.h` (pure carrier, threaded through `RepositorySession`) and `core/base/WalkTiming.h` (pure, unit-tested formatting -- `RepositorySession` itself still has no test harness, same limitation as bottlenecks #2 and #3's fixes). See `docs/PERFORMANCE.md`'s "Bridge-layer timing probe" section for the full mark table and a reproduction. |
| 5 | **Memory margin is thinner than it looks** | 124.2 bytes/commit on real vscode — matches the synthetic fixture almost exactly (124.2 vs 124.0) — projecting to 59.2 MB at 500k against a **64 MB target: 7% headroom**. | Fixed per-row struct cost in `GraphSnapshot`, consistent across synthetic and real data — structural, not a topology artifact. | Profile `GraphSnapshot`'s row layout for compression *before* the next larger benchmark (500k+ commit monorepo) blows the budget. Track this ratio in CI now, while margin still exists. |
| 6 | **`for-each-ref` scales with ref count, not commit count** | 25–49ms on this repo (only 30 refs after the fork clone) — but `docs/PERFORMANCE.md`'s own 3,798-ref fixture measured 0.8–2.2s for *one* call, more than the entire 50k-commit commit-graph-accelerated walk. Not reproducible here since this vscode fork only carries 30 refs. | `%(upstream:track)` per-ref cost (doc: ~440ms refname-only vs ~770ms full format, same repo). | Duplicate-load already fixed (`refreshRefsAndHistory()`). Remaining, not-yet-applied mitigation: `core/workers/Debouncer.h` exists unused — wire it so a burst of refreshes collapses into one load. |
| 7 | **Lane-cap overflow** (checked, downgraded) | 2,406 / 179,779 edges (1.3%) in the overflow lane on real vscode vs ~12% on the synthetic random-merge fixture. | Real large-repo topology is *less* tangled than the synthetic stress fixture, as the docs already note. | Not a performance finding — rendering fidelity only, costs no time. Don't rank it as a bottleneck. |
| 8 | **cat-file batch metadata fetch** (verified non-issue) | 60-commit batch: 16–37ms warm. | The persistent `git cat-file --batch` co-process design already avoids the 20-40ms-per-spawn cost the code comments warn about. | No action — flagging this as confirmation the architecture doc's stated invariant holds under real data, not a bottleneck. |

## Performance gate design

Checked what already exists before designing anything new:

- `tests/CMakeLists.txt` already runs `graph_matches_git_on_generated_history`
  on every PR (4,000-commit fixture) and it **already enforces** a memory
  ceiling (`graph_check.cpp`'s `check(bytesPerCommit < maxBytesPerCommit,
  ...)`, default 140 bytes/commit) — just not a timing one.
- A code comment already states the intended split: *"Labels let CI gate on
  the fast suites and run perf separately: runners are far too noisy for
  timing assertions to gate a pull request"* — but no perf-labeled job or
  nightly workflow actually exists in `.github/workflows/` yet.
- `HistoryProvider.PublishesChunksOnAGeometricSchedule` already demonstrates
  the right pattern: gate a **counted invariant**, not wall-clock time.

Given that, and given this session's own numbers swung 83ms→1069ms for the
identical operation on the identical warm repo, an absolute-millisecond PR
gate would flake constantly. Design, in order of reliability:

### Tier 1 — PR gate (fast, deterministic, extends existing infra)

1. Keep `graph_matches_git_on_generated_history` as-is (correctness + memory
   ceiling).
2. **New:** `refstore_dedup_regression` — using the existing
   `FakeProcessRunner` test double, assert `for-each-ref` is invoked exactly
   once per `refreshRefsAndHistory()` call. This is a real regression test
   for the exact bug `docs/PERFORMANCE.md` already describes fixing —
   currently *no test exercises `RepositorySession` at all* (the doc says so
   directly).
3. **New:** `commit_graph_speedup_ratio` — build the same small (4,000-commit)
   fixture twice, with and without a commit-graph, and assert `withGraphMs <
   withoutGraphMs / 2`. A same-run, same-machine **ratio** is far more
   flake-resistant than an absolute ceiling, and this session's 5.3–14x
   real-world delta gives huge margin.
4. **New:** subprocess spawn-count assertions (via `FakeProcessRunner` or a
   wrapping mock) for the refs+history sequence — catches "someone
   reintroduced a duplicate git call" with zero timing involved.

### Tier 2 — scheduled workflow (new `.github/workflows/perf-nightly.yml`, doesn't exist today)

- `schedule:` + `workflow_dispatch:` triggers, not `pull_request`.
- Job A: the 200k-commit synthetic fixture already documented in
  `docs/PERFORMANCE.md`, run with **generous** absolute ceilings (e.g., 3-8x
  the documented numbers) purely to catch gross regressions over time via
  trend, not to gate merges.
- Job B (weekly or manual-only, given the network/size cost): formalize
  exactly what this session did by hand — shallow-clone + unshallow a pinned
  real OSS repo, run `gbm_graph_check`, and **publish** the numbers (Step
  Summary / artifact) rather than hard-pass/fail, for the same reason the
  docs already use ranges ("0.8-2.2s, machine-load dependent") instead of
  single numbers.

### Tier 3 — manual/local only, not automated

vscode-scale commit-graph A/B and cold-vs-warm working-copy status, as
reproduced this session. Document the repro steps in `docs/PERFORMANCE.md`
the same way the existing sections already do, but don't wire real
network-dependent multi-GB clones into CI.

## Caveat

This vscode fork ended up with only 30 refs after `fetch --unshallow`, so
it's a good commit-count fixture (162k, close to the doc's 200k synthetic
target) but a poor ref-count fixture — it doesn't exercise the "thousands of
stale refs" case the README names as the target workload. Only `gen_history
--branches 3000` (already used in the existing 50k/3798-ref doc fixture)
covers that axis; any gate needs both.
