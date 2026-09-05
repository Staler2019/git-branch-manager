# Windows process-spawn cost, measured (2026-08)

Why the C++ suite takes four minutes on Windows and twenty seconds on Linux,
what part of that gap the *application* is responsible for, and what was
actually changed. Written because the ratio is large enough that "Windows is
just slow" is not a useful answer, and because two of the three contributing
costs are **not** in `src/` at all — a fact worth recording before someone
optimises the wrong layer.

## The gap

Windows ctest totals from six CI runs of the same suite, oldest first. All are
`cmake --workflow --preset capi-only`; the test count drifts because branches
added tests. **Per-test time is the only comparable number**, and the run-to-run
spread on GitHub's Windows runners is the first thing to notice:

| Run | branch | tests | ctest total | s/test |
|---|---|---|---|---|
| `32365698665` | tier-5 | 502 | 202.71 s | 0.4038 |
| `32367844938` | tier-5 | 502 | 204.81 s | 0.4080 |
| `32374888281` | tier-4 | 508 | 212.61 s | 0.4185 |
| `32382971897` | tier-0c | 511 | 236.51 s | 0.4628 |
| `32387290916` | tier-0c | 511 | 251.54 s | 0.4923 |
| `32389479399` | `--no-optional-locks` (#78) | 509 | 203.71 s | 0.4002 |

mean 0.4309, stdev 0.0378 — a **±9 % band**, min to max a 23 % spread, on runs
whose `src/` differences cannot plausibly account for it.

The sharpest demonstration is not that table but a same-code pair. The branch
carrying this report's own change was run twice, the second time with two extra
tests and no behavioural difference:

| Run | tests | ctest total | s/test |
|---|---|---|---|
| `32393264652` | 517 | 226.47 s | 0.4380 |
| `32394639008` | 519 | 191.29 s | **0.3686** |

**19 % apart, on effectively identical code.** The second is faster than every
run in the table above, including the ones without the change. Any claim about
a Windows speed-up needs either an effect well outside that spread or several
runs per side; a single pair proves nothing in either direction.

For scale, the same suite on Linux (`ubuntu-22.04`, run `32387290916`) is
**22.89 s** against Windows' ~220 s — roughly **11×**, and not one pathological
test: Linux's slowest single case is 1.77 s while Windows has a dozen in the
2–9 s range and a long flat tail. A broad per-test constant is the signature of
**per-process overhead**, since every one of these tests spawns git repeatedly.

## Method

Two independent counters, run against the same binary so they cross-check:

1. **In-process**: a temporary atomic counter in `ProcessRunner`'s `execute()`
   funnel, keyed by `command.args[0]`. Counts what the *app* spawns.
2. **PATH shim**: a `git` shim script earlier on `PATH` than the real binary,
   appending `$1` to a log and `exec`-ing through. Counts what *anything*
   spawns — app and test fixtures alike, since `GitExecutable::detect()`
   searches `PATH` and `std::system()` inherits it.

Both were run over the whole `gbm_capi_tests` binary on macOS. Platform does
not matter for a *count*; only the per-spawn cost is platform-specific.

## What the counts showed

`gbm_capi_tests`, before any change:

| Source | git invocations | Share |
|---|---|---|
| Test fixtures (`std::system`) | 903 | 65 % |
| Application (`ProcessRunner`) | 475 + 35 `--version` probes | 35 % |
| **Total** | **1378** | |

And within the application's own 510, the distribution was lopsided:

| git subcommand | count |
|---|---|
| `rev-parse` | 115 |
| `symbolic-ref` | 111 |
| `status` | 53 |
| `--version` (`GitExecutable::probe`) | 35 |
| `for-each-ref` | 33 |
| everything else | ≤ 22 each |

**`rev-parse` + `symbolic-ref` = 226 of 510 — 44 % of every git process the
app started was spent reading HEAD.** That is the finding this report exists
for.

## Why HEAD was costing two processes

`RefStore::readHead()` issued `symbolic-ref --quiet HEAD` for the branch name
and then `rev-parse --verify --quiet HEAD` for the oid, unconditionally. It
sits on two hot paths at once:

- `RefStore::load()` — every refs refresh.
- `OperationRunner::recordUndoPoint()` — before **every** undoable write.

So on Windows each write operation paid roughly two spawns of pure overhead
before it began, and the refresh that followed paid two more.

### The fix

One command supplies both facts:

```
git rev-parse --revs-only HEAD --symbolic-full-name HEAD
```

| HEAD state | exit | stdout |
|---|---|---|
| On a branch | 0 | `<oid>` then `refs/heads/<name>` |
| Detached | 0 | `<oid>` then the literal `HEAD` |
| Unborn (no commits) | 0 | *empty* |

`--revs-only` is load bearing rather than decoration. Without it the same
argument list exits 128 on an unborn repository and writes `fatal: ambiguous
argument 'HEAD'` to stderr — and `ProcessRunner::recordOperation()` records
*every* invocation, stderr included, into the operation log the user can
read. A freshly-initialised repository is a normal state, and it would have
been described there as a fatal error.

Unborn is the one case that still costs a second process: the combined
command cannot name the branch HEAD is parked on, so it falls back to the old
`symbolic-ref`. That is 2 spawns, exactly as before — no regression, and the
common cases drop to 1.

Detached is recognised by the literal string `HEAD` on line two. That is
unambiguous, not merely convenient: a real branch always comes back fully
qualified as `refs/heads/…`.

### Measured effect

Same shim, same binary, after the change:

| | before | after | delta |
|---|---|---|---|
| App git spawns | 475 | **386** | **−89 (−18.7 %)** |
| All git invocations | 1378 | 1289 | −89 (−6.5 %) |

89 rather than the 113 a naive halving predicts, because some `readHead()`
calls take the unborn fallback and some `rev-parse` calls come from other
sites (`RefStore::resolveRevision`, `BisectOps`).

Per call, on macOS, 60 iterations against a real repository: the two-process
form costs **11.3 ms** and the one-process form **5.9 ms** — 5.5 ms saved, or
48 %. A user operation runs `readHead()` twice (once in `recordUndoPoint()`,
once in the refresh's `load()`), so that is ~11 ms per operation on macOS and,
extrapolating from Windows' higher per-process cost, plausibly 60–120 ms there.
The extrapolation is not a measurement.

**CI cannot confirm this, and does not.** The two runs carrying the change land
at 0.4380 (z = +0.02, dead on the population mean) and 0.3686 (z = −1.65,
faster than anything without the change) — 19 % apart from each other, which is
larger than any effect a 89-process saving could produce. Quoting either one
alone would manufacture a result: against the 0.4923 s/test baseline the first
looks like −11 %, and that baseline simply happened to be the slowest run in
the set. The defensible claims here are the deterministic ones — 89 fewer
processes, 5.5 ms per call — not a CI delta.

## The fixture shell, since removed

The largest single item in the earlier version of this report was listed under
"what this does not fix": 903 of the 1378 git invocations came from `runGit()`
helpers built on `std::system()`, copy-pasted into 26 capi fixtures. On Windows
each of those spawns **`cmd.exe` *and* `git.exe`**, so the fixtures alone cost
~1806 processes against the app's 386.

That is now fixed. `tests/support/GitCli.h` runs git through the existing
`makeProcessRunner()` — `gbm_capi_tests` already linked `gbm_core`, so no new
dependency — and every fixture call site goes through it.

| | before | after |
|---|---|---|
| git processes | 1378 | 1348 |
| shell processes | 903 | **0** |
| **total** | **2281** | **1348** |

**933 fewer processes, −41 %**, which is what the per-process model predicted.
The 30 git processes that also went are `GitExecutable::detect()`: 29 fixtures
each ran their own `git --version` probe purely to decide whether to skip, and
`GitCli` detects once per test binary.

Wall clock, `gbm_capi_tests` run end to end on macOS, three runs per side:

| | samples | median |
|---|---|---|
| before | 64.19 / 54.95 / 45.49 | 54.95 s |
| after | 38.43 / 40.97 / 52.49 | **40.97 s** |

−25 % by median, **but the ranges overlap** (the fastest "before" run beats the
slowest "after" one), so on macOS this is directional rather than conclusive at
n=3. That is expected: `/bin/sh` is cheap. The deterministic process count is
the number to trust here, and Windows — where the removed process is `cmd.exe`
— is where the effect should be large enough to see. A controlled measurement
on a single file was cleaner: `WorkingCopyApiTest --gtest_repeat=10` (800
fixture calls) went from a median of **33.72 s** to **30.56 s**, non-overlapping
ranges, 3.95 ms saved per call against a 4.39 ms prediction.

Two correctness problems went with the shell, and they matter more than the
seconds:

- **Quoting.** `BranchApiTest` carried a five-line comment explaining that
  single quotes are POSIX-shell syntax `cmd.exe` passes through literally, so
  git received them as part of a `--format` string, while leaving
  `%(refname:short)` unquoted made dash treat the parentheses as a syntax
  error. An argv vector has no such failure mode.
- **Stray files in the repository under test.** `CommitFilesApiTest` and
  `CommitMetaApiTest` redirected `rev-parse HEAD` into `head-oid.txt` *inside*
  the fixture repository, leaving an untracked file for every later status read
  to trip over. `GitCli::capture()` returns stdout directly.

A `cq.yml` guard now fails the build if `std::system` reappears under `tests/`,
on the same reasoning as the "core must not depend on Qt" grep next to it: the
tests would still pass, just slower and more fragile, so nothing else in CI
would notice.

## The prediction failed on Windows CI

The acceptance criterion was written before the run and is not being moved
afterwards. Removing 933 of 2281 processes was predicted to take Windows'
ctest phase from ~0.43 s/test to ~0.26; anything landing in 0.37–0.49 was
declared a failure in advance.

| Run | tests | ctest | s/test |
|---|---|---|---|
| six-run population *without* either change | 502–511 | — | 0.4002–0.4923 (mean 0.4309) |
| readHead only | 519 | 184.2 s | 0.3549 |
| readHead **+ no fixture shell** | 523 | 211.9 s | **0.4052** |

**0.4052 is squarely in the failure band** — the population mean, essentially.
And the branch with *fewer* changes came out faster than the branch with more,
which is not a coherent causal signal in either direction. The honest reading
is **no detectable effect on Windows CI**.

The model was wrong in a specific, identifiable way: it assumed
cost(`cmd.exe`) ≈ cost(`git.exe`). The data says otherwise. `cmd.exe` is a
small, already-resident system binary; `git.exe` on Windows drags in the MSYS2
runtime and is far more expensive to start. Removing 903 shell processes
therefore removed 903 of the *cheap* processes and left all 1348 expensive ones
in place. The `−41 % of processes` figure is still true and still deterministic;
it just does not convert into `−41 % of time`.

What survives is not the speed claim:

- the quoting hazard is structurally gone (an argv vector has no shell to
  misparse it),
- the two redirect files written *inside* the repository under test are gone,
- and a guard stops the pattern coming back.

Those were always the better half of the argument. The seconds were not there.

## What this still does *not* fix

1. **ctest runs serially in CI.** `CMakePresets.json`'s `tbase` test preset
   sets no `execution.jobs`, so all cases run one at a time on every platform.
   Parallelising would compress Windows further — but see **#70**:
   `UndoApiTest`/`MergeApiTest` (and, observed while writing this,
   `BisectApiTest.BisectResetEndsTheSessionAndRestoresTheOriginalBranch`)
   already fail intermittently under parallel load with a fixed 10 s `waitFor`
   budget. Turning on `-j` in CI without settling #70 first would trade wall
   clock for flakes. Deliberately not done here.
2. **The remaining app spawns are mostly irreducible.** `status`, `diff` and
   `for-each-ref` each answer a distinct question.

## The compile phase is the larger half, and nothing here touches it

Splitting the Windows job by phase makes the priority obvious, and it is not
the one this report spent its effort on:

| Platform | compile | test | compile share |
|---|---|---|---|
| **Windows** | **297–310 s** | 184–212 s | **~61 %** |
| Linux | 129 s | 17 s | 88 % |
| macOS | 97 s | 52 s | 65 % |

Windows compiles 2.3× slower than Linux and 3.1× slower than macOS, and that
phase alone is bigger than the whole test phase. Meanwhile there is **no
`ccache`/`sccache`, no `CMAKE_*_COMPILER_LAUNCHER`, no precompiled header, no
`UNITY_BUILD`, and no `actions/cache` anywhere in `ci.yml`** — every run
recompiles everything, on every platform, including the `FetchContent` copy of
GoogleTest. The generator is Ninja, so build parallelism is already the default
and is *not* the missing piece.

A compiler cache is the obvious next lever and is deliberately left undone
here. One caveat found while scoping it, worth checking before anyone starts:
sccache does not cache MSVC objects built with `/Zi` (separate PDB), only
`/Z7`. That is the most likely reason such an attempt would quietly not work.

## Sundry

`--no-optional-locks` (issue #77) was checked for a Windows regression, since
skipping the index stat-cache refresh could in principle cost later `status`
calls. Its run is the fastest of the six above (0.4002 s/test) — but that is
z = −0.95, still inside the band, so the honest reading is "no regression
detected", not "measurably faster".

## Job object per-spawn cost, measured (2026-09-05)

`[CPP-windows-terminate-hangs-join]`'s fix puts every spawned git process into a
Win32 job object, so that `terminate()` kills the whole tree rather than one
process. The round that shipped it claimed the job object cost **33%**, then
corrected that in place to "not measured": the 33% came from three whole-suite
CI runs with a control group (175 tests that never spawn anything, averaging
34 ms each) that could not react to the variable being excluded — it moved 1.58×
between two runs of its own.

`tests/tools/spawn_cost_win.cpp` (`gbm_spawn_cost`, ctest label `perf`, run by
`perf-nightly.yml`'s `windows-spawn-cost`) replaces that with an A/B inside one
process on one machine. First run that produced a number, `windows-2022`, MSVC
14.44, 51 iterations, 5 discarded warm-up:

```
job-object-ab: verdict=measured job_overhead_us=71 resolution_us=18
               git_spawn_us=26501 overhead_fraction_of_git=0.0027
               watchdog_delta_us=-72 parent_in_job=1 iterations=51
```

| Arm | Median |
|---|---|
| `raw_nojob` (trivial child, no job object) | 16031 µs |
| `raw_job` (same child, job object created and assigned) | 16102 µs |
| `raw_nojob_aa` (A/A null — the run's own resolution) | 16013 µs → **18 µs** |
| injected 300 µs control | recovered 291 µs (**3% error**) |
| `git --version` through the real `ProcessRunner` | 26501 µs |

**The job object costs 71 µs per spawn, 0.27% of one `git --version`.** That is
four times the run's own resolution, and the injected-delay control recovered a
delay it was told the size of to within 3%, so the instrument was working when
it said so. The earlier 33% is wrong by two orders of magnitude.

Read it as one run. The gate (`GBM_MAX_JOB_OVERHEAD_FRACTION`) stays at 0.0 —
disabled — until the nightly has a trend, because picking a threshold off a
single sample is the same shape of error this whole document exists to record.

### The watchdog number from that run is *not* usable, and why

The same run printed `watchdog delta = -72us (resolved)`. A watchdog thread
cannot make spawning faster, so that label was wrong — and the flaw was in the
tool, not the runner. `resolution_us=18` was measured by an A/A arm on the
**raw** path (a ~16 ms trivial child) and then used to judge the **prod** pair
(a ~26 ms git process). Run-to-run spread scales with what is being run, so
that is a ruler calibrated on A being used to measure B — the identical error,
one level down, that the 33% claim was corrected for.

Fixed by giving the `prod_*` pair its own A/A null arm; `prod_resolution_us` is
now reported beside the delta and is what decides whether it is resolved. **No
watchdog figure should be quoted from before that change.**
