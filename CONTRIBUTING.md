# Contributing

## Layout

```
src/core/     No UI toolkit at all. C++20 + SQLite. Fully testable headless;
              CI enforces this.
  base/       Result/GitError, ObjectId, CancellationToken, FsUtil, thread checks
  git/        Process seam, cat-file co-process, rev-list streaming, refs, diffs, ops
  graph/      The lane algorithm, snapshot layout, ASCII renderer for golden tests
  discovery/  Repository classification and the parallel scanner
  cache/      SQLite schema and queries
src/capi/     Thin extern "C" bridge (gbm_capi.h) between core and the
              Flutter UI, reached via dart:ffi. No Git logic of its own.
app_flutter/  The UI: Flutter + Riverpod + go_router.
tests/        Unit, golden, integration, capi (FFI surface) tests, and the
              fixture generator.
```

The `core` / `capi` split is load-bearing rather than tidy: `core` links no UI
toolkit, so the entire data layer runs under GoogleTest with no UI runtime, and
CI fails the build if a Qt header appears under `src/core` (a historical check
from when the UI was Qt Widgets; the underlying rule -- `core` stays UI-free --
still holds). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the
invariants behind that split and the rest of the design.

## Building

Requires CMake 3.25+ (the `cmake --workflow` presets below need `workflowPresets`,
added in the CMakePresets v6 schema, which requires 3.25) and a C++20 compiler
for `src/core`/`src/capi`; the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable channel) for `app_flutter/`.

```bash
# Core + capi (FFI) + tests
cmake --workflow --preset capi-only

# Data layer only
cmake --workflow --preset core-only

# Sanitizers
cmake --workflow --preset asan-ubsan
cmake --workflow --preset tsan
```

Run the UI: see the README's "Building from source" section for the
`app_flutter/scripts/build_capi.sh` + `flutter run` sequence.

Warnings are treated as errors by default (`-Werror`/`/WX`, via
`gbm_warnings` in `cmake/Warnings.cmake`), so a build that only warned
before will now fail to compile, with no per-file exceptions. If a compiler
flags a real memory-safety warning (bounds, overread, use-after-free), fix
the code rather than suppressing the diagnostic. CI always builds with this
on; a downstream packager who hits a new warning from a compiler version CI
doesn't test can opt out with `-DGBM_WERROR=OFF`.

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

CI runs on every pull request targeting `main`: formatting (`lint`), the
core/UI layering check, commit message linting (`conventional-commits`), the
`capi-build` matrix on Linux/macOS/Windows, `flutter-ci` (`flutter analyze` +
`flutter test` for `app_flutter/`), and the `sanitizers`/`thread-sanitizer`
jobs. All of it needs to be green before merge.
