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

mean 0.4371, stdev 0.0387 — a **±9 % band**, min to max a 22 % spread, on runs
whose `src/` differences cannot plausibly account for it. Any claim about a
Windows speed-up smaller than that band is unfalsifiable from CI alone.

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

**CI cannot confirm this, and does not.** The Windows run carrying the change
(`32393264652`, 517 tests, 226.47 s) lands at **0.4380 s/test** — z = +0.02
against the six-run population above, i.e. dead on its mean. Quoting it against
the 0.4923 s/test baseline alone would manufacture a −11 % "improvement" that
the rest of the population does not support; that baseline simply happened to
be the slowest run in the set. The defensible claims here are the deterministic
ones — 89 fewer processes, 5.5 ms per call — not a CI delta.

## What this does *not* fix

Stated plainly so the CI number is not mistaken for the target:

1. **Test fixtures dominate, and they are not app code.** 903 of 1378
   invocations come from `runGit()` helpers built on `std::system()`. On
   Windows that spawns **`cmd.exe` *and* `git.exe`** per call — roughly 1806
   processes for the fixtures against 386 for the app. No change under `src/`
   can touch this. Replacing `std::system()` with a direct spawn would be the
   single largest win available for the *test job*.
2. **ctest runs serially in CI.** `CMakePresets.json`'s `tbase` test preset
   sets no `execution.jobs`, so all 511 cases run one at a time on every
   platform. Parallelising would compress Windows' 251 s substantially — but
   see **#70**: `UndoApiTest`/`MergeApiTest` (and, observed while writing
   this, `BisectApiTest.BisectResetEndsTheSessionAndRestoresTheOriginalBranch`)
   already fail intermittently under parallel load with a fixed 10 s
   `waitFor` budget. Turning on `-j` in CI without settling #70 first would
   trade wall clock for flakes. Deliberately not done here.
3. **The remaining app spawns are mostly irreducible.** `status`, `diff` and
   `for-each-ref` each answer a distinct question; `--version` is one probe
   per `Session`.

## Sundry

`--no-optional-locks` (issue #77) was checked for a Windows regression, since
skipping the index stat-cache refresh could in principle cost later `status`
calls. Its run is the fastest of the six above (0.4002 s/test) — but that is
z = −0.95, still inside the band, so the honest reading is "no regression
detected", not "measurably faster".
