---
paths:
  - "src/core/git/DiffService.*"
  - "src/core/git/WorkingCopyStatus.*"
  - "src/core/git/GitCommand.h"
  - "src/core/git/ops/CompareOps.cpp"
  - "src/core/git/ops/WorktreeOps.cpp"
  - "tests/unit/WorktreeReadFlagsTest.cpp"
---

# Invoking git correctly

Pin prefix `GIT-`. Format: [README.md](../../docs/rules/README.md).

## [GIT-output-format-single-slot] A second diff pass must repeat every flag of the first

- **Rule**: git's diff output-format is one slot, so `--raw` and `--numstat` cannot share a command; kinds and counts are two passes joined by `path` (`DiffService::attachLineCounts`, `CompareOps.cpp`'s `readFiles`, `WorkingCopyStatus.cpp`'s `attachNumstat`).
- **Do**: repeat `--root`, `--diff-merges=first-parent` (never `--first-parent`: `diff-tree` ignores it) and the same rename flag; a missed flag lands as a row with no count and no error.
- **Evidence**: `DiffService.cpp`'s `rawRenameFlag` and `attachLineCounts` docs; ledger: Changed files line counts

## [GIT-worktree-reads-need-fsmonitor-off] A background `git diff` that reads the work tree needs `worktreeReadFlags()`

- **Rule**: prepend `GitCommand::worktreeReadFlags()` to every background work-tree-vs-index `git diff`; never to `git status` (including the per-worktree pending count), never into `globalFlags()`.
- **Do**: a new call site needs its own case in `tests/unit/WorktreeReadFlagsTest.cpp` — CI has no fsmonitor, so only an argv assertion can see a missing flag.
- **Evidence**: `GitCommand.h`'s `worktreeReadFlags()` doc (9 of 12 `index.lock` failures, holder never identified); ledger: Working Copy 重新設計
