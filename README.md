# git-branch-manager

A fast Git client for very large repositories, modelled on [Fork](https://git-fork.com).

Built for the case most Git GUIs handle badly: **working trees over 500 MB with a
decade of history** — hundreds of thousands of commits, tens of thousands of files,
and often thousands of stale refs. It manages many such repositories at once,
discovered under folders you nominate.

> **Status: full feature parity implemented.** History browsing, the
> Fork-style graph, repository discovery, diffs, branch switching, the
> working copy, merge/cherry-pick/conflict resolution, worktrees/stash/tags/
> fetch/pull/push, interactive rebase, reset/restore/clean, blame, file and
> line history, reflog/undo, submodules, bisect, LFS, patch import/export,
> themes and accessibility all work end to end on all three platforms. See
> [docs/FEATURES.md](docs/FEATURES.md) for the full list and
> [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.
>
> The UI is [Flutter](https://flutter.dev) (see `app_flutter/`), calling into
> the Git logic in `src/core` through a thin C API (`src/capi/`) via
> `dart:ffi`. An earlier Qt Widgets UI (`src/app/`) was removed once the
> Flutter UI reached feature parity; `src/core` itself is unchanged by that
> rewrite -- see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Installing

Download the latest release for your platform from the
[Releases](../../releases) page. The macOS download is Apple Silicon only.

### macOS: clearing the quarantine attribute

The macOS build is only signed and notarized when the maintainer's Apple
Developer credentials are configured in CI; a fork or an unconfigured
release ships an unsigned `.dmg`. Gatekeeper quarantines anything downloaded
with a browser, so opening an unsigned build gives a "git-branch-manager is
damaged and can't be opened" or "Apple could not verify" dialog instead of
launching. Clear the quarantine extended attribute after moving the app to
`/Applications` (or wherever you keep it), then launch it normally:

```bash
xattr -cr /Applications/git-branch-manager.app
```

## Building from source

Requires CMake 3.25+, a C++20 compiler, and the [Flutter
SDK](https://docs.flutter.dev/get-started/install) (stable channel) for the UI.

```bash
# Build gbm_capi (the Git logic, as a shared library) and run the UI.
app_flutter/scripts/build_capi.sh   # build_capi.ps1 on Windows
cd app_flutter
flutter run -d linux                # -d macos / -d windows elsewhere
```

`flutter build linux`/`flutter build windows` compile and bundle `gbm_capi`
automatically as part of the same build (see `app_flutter/linux/CMakeLists.txt`
and `windows/CMakeLists.txt`); macOS still needs the `build_capi.sh` step
first (see that script's own doc comment for why).

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full build/format/test workflow.

## Documentation

| | |
|---|---|
| [docs/FEATURES.md](docs/FEATURES.md) | The full feature list |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Repository layout and the design decisions behind it |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Measured graph performance, how to reproduce it, and repository settings the app tunes |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones, done and upcoming |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the build, formatting and testing
workflow, commit message conventions, and what CI checks on every pull request.

## Licence

The source in this repository is MIT (see [LICENSE](LICENSE)).

Distributed binaries bundle the Flutter engine and the packages `app_flutter/`
depends on (Riverpod, go_router, etc.), each under its own permissive licence
(BSD-3-Clause for the Flutter engine; see `app_flutter/pubspec.lock` for the
rest). [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) lists each dependency
and its licence. Git itself is only ever *executed*, never bundled or linked,
so its GPL does not reach this application.
