# git-branch-manager

A fast Git client for very large repositories, modelled on [Fork](https://git-fork.com).

Built for the case most Git GUIs handle badly: **working trees over 500 MB with a
decade of history** — hundreds of thousands of commits, tens of thousands of files,
and often thousands of stale refs. It manages many such repositories at once,
discovered under folders you nominate.

> **Status: M0–M5 implemented.** History browsing, the Fork-style graph,
> repository discovery with caching, diff viewing, branch switching, the working
> copy, merge/cherry-pick/conflict resolution, worktrees/stash/tags/fetch/
> pull/push, interactive rebase, reset/restore/clean, blame, file and line
> history, the reflog/undo journal, submodules, bisect, LFS, patch import/
> export, light/dark/system themes and accessible names on the core views all
> work end to end on all three platforms — see [Roadmap](#roadmap).

## What works today

- **Fork-style commit graph.** A branch's first-parent chain renders as one
  unbroken vertical column, the trunk owns the leftmost lane for all of history,
  and merges branch right and rejoin with a single bend.
- **Multiple base folders** scanned for repositories, with a SQLite cache and an
  explicit Refresh, so startup never waits on the filesystem.
- **Branch switching**, including the dirty-work-tree case with Stash / Discard /
  Cancel rather than a raw Git error.
- **Diff viewing** per commit and per file, with real text selection.
- **The working copy**: status, stage/unstage by file, hunk or line, commit and
  amend.
- **Merge** (fast-forward-only / no-fast-forward / squash), **cherry-pick**
  (single, multi and range), and **conflict resolution** across all three index
  stages, with a side-by-side diff.
- **Worktrees, stash and tags**: add/remove/lock/prune worktrees; save/apply/
  pop/drop/branch stashes; create/delete/push annotated or lightweight tags.
- **Fetch, pull and push**, with credential prompts routed through an askpass
  helper rather than failing outright, and force-pushing offering only
  `--force-with-lease`, never a bare `--force`.
- **An operation log** recording every Git command, its exit code, duration and
  full stderr, with a copy button.
- **Interactive rebase**: reorder, drop, squash and fixup commits from an
  editable plan (no external editor process — see
  [Design decisions](#design-decisions-worth-knowing)), plus `edit` stops that
  hand off to the existing amend flow; conflicts, `--skip` and `--abort` are
  Continue/Skip/Abort banner controls shared with cherry-pick.
- **Reset, restore and clean**: soft/mixed/hard reset to any commit, unstage
  or discard changes per path, and a preview-before-you-delete untracked-file
  clean.
- **Blame, and file/line history**: per-line attribution (`git blame
  --line-porcelain`), a file's commit history across renames (`--follow`), and
  a specific line range's history (`log -L`).
- **Reflog browser and undo**: every `HEAD` movement, and a one-click "Undo
  last operation" backed by the operation runner's own undo journal rather
  than a reflog guess.
- **Submodules**: status (not-initialized / up-to-date / modified /
  conflicted) read from `.gitmodules` plus `git submodule status`; add, init,
  update, sync and deinit.
- **Bisect**: start with a bad/good range (or neither, marking as you go),
  good/bad/skip stepping with the next candidate and concluding message
  surfaced directly, and reset.
- **Git LFS**: detected rather than assumed; track/untrack patterns, see
  which files are pointers vs. downloaded, and pull/fetch/prune.
- **Patch import/export**: `format-patch` an arbitrary commit selection to a
  folder, `apply` a plain diff to the work tree, and `am` a patch series into
  commits with its own Continue/Skip/Abort recovery — deliberately not the
  shared rebase banner, since `git rebase --continue` refuses outright during
  an `am` session even though the two share an on-disk state directory.
- **Light/dark/system themes**, persisted and switchable from View > Theme.
- **Accessible names** on the repository list, commit history, ref tree,
  changed-files list, diff panes, working-copy lists and the credential
  prompt, so a screen reader has more than a generic control type to
  announce.

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

Reproduce with `gbm_graph_check` — see [Verifying against a real repository](#verifying-against-a-real-repository).

One caveat on that fixture, so the numbers are not read as more flattering than they
are: it merges randomly across the whole history, which is far more tangled than
real repositories, where merges are usually local. It therefore hits the 48-lane
render cap and pushes about 12% of edges into the overflow gutter. For comparison,
`git log --graph` needs *more* columns than we use on the same input (51 vs 31 on a
4-branch variant), so the width is a property of the topology rather than of the
lane allocator.

## Design decisions worth knowing

Three invariants drive the architecture, and most of the code exists to hold them:

1. **The UI thread never spawns a process or walks a directory.** Enforced by
   `GBM_ASSERT_NOT_UI_THREAD()`, which aborts in debug and test builds. Reading the
   local SQLite cache on the UI thread *is* allowed and is the reason startup is
   fast; the assertion guards the expensive, unbounded work.
2. **Expensive artifacts are immutable and published, never mutated.** Workers build
   a `GraphSnapshot` and hand it over as `shared_ptr<const T>`; the paint path takes
   no locks, and a superseded snapshot lives until the last frame using it is done.
3. **Startup paints from cache only.** Zero Git work before the window is visible.

Other decisions that are easy to get wrong:

- **The Git CLI is the only backend.** No libgit2. This keeps hooks, credential
  helpers, LFS and the rebase sequencer working exactly as they do in a terminal.
  The cost is that speed has to be engineered: a persistent `git cat-file --batch`
  co-process per repository, streamed `rev-list`, and viewport-sized batching. A
  process is never spawned per row.
- **Git is detected, never bundled.** 2.30 is the floor; below 2.37 (no fsmonitor)
  and 2.38 (no merge preview) the app says so in Settings rather than failing later.
- **Lane colours key off the lane's seed commit, not the lane index.** So a branch
  keeps its colour across a refresh or an incremental append, and colours are
  deterministic enough to golden-test.
- **Every cap is visible.** The 48-lane limit, the 2 MB diff limit and the row limit
  each surface a message. Silent truncation would be worse than being slow.
- **No interactive editor process, anywhere.** There is no terminal to run one in,
  so `git commit --amend`, a no-ff merge and squash/fixup all always pass a
  message explicitly (`--no-edit` or otherwise) rather than opening `$EDITOR`.
  Interactive rebase carries the idea furthest: the todo list is built and
  edited in the UI, then `GIT_SEQUENCE_EDITOR` is pointed at `cp` with the
  built plan as its first argument, so git's own "run the editor" step becomes
  a copy instead of a blocked child process. `cp` needs nothing bundled — Git
  for Windows carries its own coreutils and prepends them to `PATH` for
  exactly this kind of child process — so it works unmodified on all three
  platforms.
- **A cancelled scan never deletes anything.** It commits what it found and skips
  the mark-missing sweep, because most of the tree was never visited.

### Two bugs the design caught, as illustration

- The incremental scan pruned unchanged subtrees but never *saw* the repositories
  inside them, so the mark-missing sweep deleted them — one Refresh would empty the
  user's list. Fixed by advancing `last_seen_gen` for repositories under a pruned
  subtree (`RepoIndexDb::touchReposUnder`).
- Publishing a graph snapshot on a 30 ms timer looked entirely reasonable, but each
  publish copies every row built so far. Once a copy exceeded 30 ms, *every row*
  triggered another publish: 13,608 chunks and 470 seconds on a 200k-commit
  repository. The schedule is now geometric — 12 chunks, 0.6 seconds — and
  `HistoryProvider.PublishesChunksOnAGeometricSchedule` guards against a regression.

## Layout

```
src/core/     No Qt at all. C++20 + SQLite. Fully testable headless; CI enforces this.
  base/       Result/GitError, ObjectId, CancellationToken, FsUtil, thread checks
  git/        Process seam, cat-file co-process, rev-list streaming, refs, diffs, ops
  graph/      The lane algorithm, snapshot layout, ASCII renderer for golden tests
  discovery/  Repository classification and the parallel scanner
  cache/      SQLite schema and queries
src/app/      Qt 6 Widgets. Thin. No Git logic.
  bridge/     Where core callbacks become Qt signals — the only threading boundary
  models/     Virtualized models plus the graph delegate
  views/      Main window, diff view, operation log
tests/        Unit, golden, integration, Qt model tests, and the fixture generator
```

The `core` / `app` split is load-bearing rather than tidy: `core` links no Qt
target, so the entire data layer runs under GoogleTest with no `QApplication`, and
CI fails the build if a Qt header appears under `src/core`.

## Building

Requires CMake 3.25+ (the `cmake --workflow` presets below need `workflowPresets`,
added in the CMakePresets v6 schema, which requires 3.25), a C++20 compiler,
and Qt 6.4+ for the GUI.

Released binaries are built with Qt 6.10, which needs macOS 13 or newer; the
macOS download is Apple Silicon only.

```bash
# GUI + tests
cmake --workflow --preset dev

# Data layer only - no Qt needed at all
cmake --workflow --preset core-only

# Sanitizers
cmake --workflow --preset asan-ubsan
cmake --workflow --preset tsan
```

Run the app: `./build/dev/src/app/git-branch-manager`

## Formatting

CI's `lint` job rejects any PR that isn't clang-format-clean (clang-format 18,
see `.clang-format`). Run before pushing:

```bash
scripts/format-check.sh   # non-mutating; what CI runs
scripts/format.sh         # applies the fixes in place
```

Both resolve clang-format 18 for you -- `clang-format-18` on `PATH`, then a
Homebrew `llvm@18` keg, then a cached Python venv with the pinned `clang-format`
PyPI wheel as a fallback that needs nothing but `python3`. They're also
reachable as CMake targets once configured: `cmake --build build/dev --target
format-check`. Optionally wire `scripts/format-check.sh` into a pre-commit hook
via the provided `.pre-commit-config.yaml` (`pre-commit install`).

## Testing

```bash
ctest --test-dir build/dev --output-on-failure
```

The graph gets the most attention, because "it compiles and passes" is not enough
for a component whose requirement is visual:

- **Golden ASCII renders** make layout changes reviewable in a diff.
- **Property tests over thousands of random DAGs** assert the invariants an eye
  cannot check at scale — first-parent straightness, no edge crossing a node's
  cell, topological consistency, chunk invariance, colour stability.
- **A cross-check against Git itself**: our row order must equal
  `git rev-list --topo-order` exactly, and our parent sets must equal `--parents`.

### Verifying against a real repository

`gen_history` emits a `git fast-import` stream, so a 200k-commit fixture takes about
a minute instead of hours and needs no checkout:

```bash
R=/tmp/fixture
git init --quiet --bare $R/.git && git -C $R config core.bare false
./build/dev/tests/gen_history --commits 200000 --branches 40 --merge-rate 0.08 \
    --octopus 3 --tags 500 --seed 42 | git -C $R fast-import --quiet
git -C $R commit-graph write --reachable --changed-paths

./build/dev/tests/gbm_graph_check $R --print-rows 40
```

`gbm_graph_check` verifies the row order against Git, checks the layout invariants,
prints the timings above, and can render the first N rows as ASCII.

It works the same on a real clone — a large, long-lived open-source repository is
the best test there is.

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

## Roadmap

| Milestone | Contents |
|---|---|
| **M0 — done** | Build and CI on three platforms, discovery + cache + Refresh, streaming graph, diffs, branch switching, operation log |
| **M1 — done** | Working copy: status with fsmonitor, stage/unstage by file, hunk and line, commit and amend, branch create/rename/delete |
| **M2 — done** | Merge (ff / no-ff / squash), cherry-pick single, multi and range with preview, conflict resolution across all three index stages, side-by-side diff |
| **M3 — done** | Worktree manager, stash, tags, fetch/pull/push with askpass helpers and `--force-with-lease` by default, signed installers |
| **M4 — done** | Interactive rebase, reset/restore/clean, blame, file and line history, reflog browser and undo |
| **M5 — done** | Submodules, bisect, LFS, patch import/export, themes, accessibility |

## Licence

The source in this repository is MIT (see [LICENSE](LICENSE)).

Distributed binaries link **Qt 6 under the LGPL v3**, which means Qt must stay
dynamically linked and its licence notices must ship alongside. The build enforces
the first part — configuration fails if it detects a static Qt — and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) sets out each obligation and how
it is met. Git itself is only ever *executed*, never bundled or linked, so its GPL
does not reach this application.
