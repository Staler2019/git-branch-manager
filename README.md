# git-branch-manager

A fast Git client for very large repositories, modelled on [Fork](https://git-fork.com).

Built for the case most Git GUIs handle badly: **working trees over 500 MB with a
decade of history** — hundreds of thousands of commits, tens of thousands of files,
and often thousands of stale refs. It manages many such repositories at once,
discovered under folders you nominate.

> **Status: M0–M5 implemented.** History browsing, the Fork-style graph,
> repository discovery, diffs, branch switching, the working copy, merge/
> cherry-pick/conflict resolution, worktrees/stash/tags/fetch/pull/push,
> interactive rebase, reset/restore/clean, blame, file and line history,
> reflog/undo, submodules, bisect, LFS, patch import/export, themes and
> accessibility all work end to end on all three platforms. See
> [docs/FEATURES.md](docs/FEATURES.md) for the full list and
> [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

## Installing

Download the latest release for your platform from the
[Releases](../../releases) page. Released binaries are built with Qt 6.10,
which needs macOS 13 or newer; the macOS download is Apple Silicon only.

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

Requires CMake 3.25+, a C++20 compiler, and Qt 6.4+ for the GUI.

```bash
cmake --workflow --preset dev
./build/dev/src/app/git-branch-manager
```

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

Distributed binaries link **Qt 6 under the LGPL v3**, which means Qt must stay
dynamically linked and its licence notices must ship alongside. The build enforces
the first part — configuration fails if it detects a static Qt — and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) sets out each obligation and how
it is met. Git itself is only ever *executed*, never bundled or linked, so its GPL
does not reach this application.
