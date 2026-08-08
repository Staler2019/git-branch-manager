# Contributing

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
CI fails the build if a Qt header appears under `src/core`. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the invariants behind that split
and the rest of the design.

## Building

Requires CMake 3.25+ (the `cmake --workflow` presets below need `workflowPresets`,
added in the CMakePresets v6 schema, which requires 3.25), a C++20 compiler,
and Qt 6.4+ for the GUI.

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

Warnings are treated as errors (`-Werror`/`/WX`, via `gbm_warnings` in
`cmake/Warnings.cmake`), so a build that only warned before will now fail
to compile. The one standing exception is GCC's `-Wstringop-overread`,
which has a known false positive against `std::string_view::find()`;
that's suppressed for `CommitMeta.cpp` only, not project-wide.

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

See [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for verifying changes against a
large generated or real repository, and for the numbers CI's benchmarks are
measured against.

## Commit messages

PRs are checked against [Conventional Commits](https://www.conventionalcommits.org/)
(`.github/workflows/ci.yml`, job `conventional-commits`):

```
type(scope)!: subject
```

where `type` is one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore` or `revert`. `scope` is optional; `!` marks a breaking
change. Release versioning is derived from these, so a malformed subject silently
produces the wrong version bump rather than just failing a lint.

## Pull requests

CI runs on every pull request targeting `main`: formatting, the core/Qt layering
check, commit message linting, the build-and-test matrix on Linux/macOS/Windows,
and the sanitizer jobs. All of it needs to be green before merge.
