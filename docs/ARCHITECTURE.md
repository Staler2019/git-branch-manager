# Architecture

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
