---
paths:
  - "src/capi/Session.cpp"
  - "app_flutter/lib/data/repositories/repo_session_repository.dart"
---

# Refresh gating

Pin prefix `STATE-`. Format: [README.md](../../docs/rules/README.md).

## [STATE-never-guess-what-git-would-say] Never gate a refresh on a predicate that guesses what git would answer

- **Rule**: run the command rather than approximate its answer — «`.gitmodules` exists» and «the index holds a gitlink» were both rejected as gates for `git submodule status` (79ms even with zero submodules, on a background pool nothing waits on).
- **Do**: `Session::refreshLfs()` skipping when `git-lfs` is not on PATH is not a counter-example: that is knowing the command cannot run, not guessing its answer.
- **Evidence**: ledger: fix/focus-refresh-repo-state
