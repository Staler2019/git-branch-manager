# Architecture

## Layout

```
src/core/     No Qt, no Dart, no UI toolkit at all. C++20 + SQLite. Fully
              testable headless; CI enforces this.
  base/       Result/GitError, ObjectId, CancellationToken, FsUtil, thread checks
  git/        Process seam, cat-file co-process, rev-list streaming, refs, diffs, ops
  graph/      The lane algorithm, snapshot layout, ASCII renderer for golden tests
  discovery/  Repository classification and the parallel scanner
  cache/      SQLite schema and queries
src/capi/     Thin, Qt-free extern "C" bridge (gbm_capi.h) between core and
              the Flutter UI, reached via dart:ffi. No Git logic of its own —
              each function transliterates a core call and publishes the
              result as JSON (or a packed binary buffer for the commit
              graph) or an async event.
app_flutter/  The UI: Flutter + Riverpod + go_router, feature-first widget
              folders. Calls into gbm_capi via dart:ffi rather than
              reimplementing any Git logic in Dart — see app_flutter/README
              and its plan notes for which small, already-tested, pure
              (no I/O) core algorithms were judged safe to port directly
              (e.g. the side-by-side diff row-pairing) versus which stayed
              server-side because of real edge-case complexity (e.g. conflict
              marker parsing).
tests/        Unit, golden, integration, capi (FFI surface) tests, and the
              fixture generator.
```

The `core` / `capi` split is load-bearing rather than tidy: `core` links no UI
toolkit of any kind, so the entire data layer runs under GoogleTest with no
UI runtime, and CI fails the build if a Qt header appears under `src/core`
(a historical check from when `src/app` was a Qt Widgets UI, kept because the
underlying rule — `core` stays UI-free — still holds for every UI this
codebase might ever grow).

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
- **The macOS build does not run under App Sandbox.** A Git GUI has to walk
  arbitrary directories the user names, spawn `git` from wherever it happens
  to be installed, and hand off to hooks, credential helpers and an askpass
  program — none of which is compatible with the sandbox's per-file access
  model. The tradeoff is giving up Mac App Store distribution; direct
  distribution (notarized `.dmg`/`.zip`) is fine without a sandbox.

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
