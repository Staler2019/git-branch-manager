# Invoking git correctly

Pin prefix `GIT-`. Format: [README.md](README.md).

## [GIT-branch-d-partially-succeeds] `git branch -d`/`-D` is per-name and partially succeeds

- **Rule**: `exit 1` does not mean nothing happened. Measured: `git branch -d a cur b`
  deletes `a` and `b`, refuses `cur`, and still exits 1.
- **Consequence**: a single exit-code check reports total failure for work that is mostly
  done, and a force retry then resends the already-deleted names, which fail as 「not found」
  and report total failure a second time. That is the whole of the user's three-line error log.
- **Do**: `DeleteBranchOperation` probes `git for-each-ref` before (send only what still
  exists) and after a failure (say what really went).
- **Do not** parse per-name stderr — those strings are gettext-localised, so they may inform
  a *message* but never a correctness decision.

## [GIT-diff-tree-ignores-first-parent] `git diff-tree` silently ignores `--first-parent`

- **Rule**: the correct spelling is `--diff-merges=first-parent` (git 2.31+).
- **Rule**: `git log --raw` honours `diff.renames` while `git diff-tree --raw` ignores it
  entirely.
- **Do**: pass the rename flag **explicitly on both**, from one shared `rawRenameFlag()`.

## [GIT-output-format-single-slot] git's diff output-format is a single slot

- **Rule**: `--raw` and `--numstat` cannot both take effect in one invocation, so a file list
  that needs kinds *and* line counts runs two commands and joins them by path
  (`DiffService::attachLineCounts()`, `CompareOps.cpp`'s `readFiles()`).
- **Do**: the second command must repeat **every** flag the first passed. Drop `--root` and
  root commits return nothing; drop `--diff-merges=first-parent` and merges return nothing;
  use a different rename flag and the two disagree about which paths exist. All three land as
  a row with no count and no error anywhere.
- **Do**: under `-z`, numstat spends **three** records on a rename (empty path field, old
  path, new path) where every other kind spends one, so a one-record-per-entry loop mis-reads
  every count after the first rename.
- **Do**: join on `path`, the only field `parseRawRecords()` fills for all kinds; `oldPath`
  is empty except for renames and copies. `-` means binary, not a number.
- **Evidence**: ledger: Changed files line counts

## [GIT-zero-means-unmeasured] `WorkingCopyEntry`'s four line-count fields: `0` always means "not measured"

- **Rule**: never "measured zero". `git status --porcelain=v2` reports no counts and git's
  diff output-format is a single slot ([GIT-output-format-single-slot]), so they come from
  two extra `git diff --numstat -z` passes (work tree↔index, `--cached`) joined by path — and
  from **reading the file** for untracked paths, which `git diff` cannot see at all.
- **Consequence**: binary, mode-only, and untracked over **1 MiB** all land as 0. The cap
  exists because `--untracked-files=all` enumerates every file in an unbuilt output directory.
- **Do**: the UI draws no badge at 0 for exactly this reason.
- **Do**: pass `-M` explicitly to both passes rather than trusting `diff.renames`, or the
  rename detection drifts from the one `--porcelain=v2` already did.

## [GIT-worktree-reads-need-fsmonitor-off] A background `git diff` that reads the work tree needs `worktreeReadFlags()`

- **Rule**: `GitCommand::worktreeReadFlags()` is `-c core.fsmonitor=false`.
- **Consequence**: without it, on a machine with `core.fsmonitor=true` the user's own writes
  start losing `.git/index.lock` — measured at 12 runs / 9 failures.
- **Do not** put it in `globalFlags()`: that would disable fsmonitor for `git status` too, on
  exactly the machines that opted into it. The `--cached` side never reads the work tree and
  does not pay it.
- **Note**: **the process creating that lock was never identified.** If anyone ever
  identifies it, the flag can be deleted — the comment says so.
- **Evidence**: ledger: Working Copy 重新設計

## [GIT-no-walk-is-date-ordered] `git log --no-walk` sorts by commit date, not by the order the oids were given

- **Do**: a batch reply must echo each oid rather than be index-aligned.
- **Do**: **absent is not zero** — a commit git never answered for is omitted, not cached as `0`.

## [GIT-push-without-refspec-refuses] `git push` with no refspec pushes through the configured upstream

- **Rule**: and *refuses* when there is none — not equivalent to naming the current branch.

## [GIT-topo-order-unconditional] An ordering flag stays unconditional in `toRevListArgs()`, and it is now `--date-order`

- **Rule**: the History branch filter's single-line rendering depends on a parent never being
  printed before its children. **Both** `--topo-order` and `--date-order` guarantee that; git's
  *default* order does not, so what the rule forbids is dropping the flag, not choosing between
  the two.
- **Rule**: **the flag is `--date-order` as of this round**, overruling the「never
  `--date-order`」comment that stood in `HistoryProvider.cpp` and the verdict recorded at
  `docs/ledger.md:1841`. History draws `row.commitTime` in its Date column, `--date-order` sorts
  by exactly that number, and `--topo-order` walks one branch to its end before starting the
  next — so the list was ordered by something the user cannot see. Measured on this repository:
  **15 time inversions over 835 rows under topo (7 of them on merge rows), 0 under date**.
- **Do not** reach for `--author-date-order`: it sorts a *different* timestamp from the one the
  Date column renders, which puts the two back out of step in a way that is harder to spot.
- **Note**: the two rejected reasons for `--topo-order` were both checked and both false.
  first-parent continuity does not depend on it — a lane stays occupied on `laneRefCount_`'s
  pending-edge count, so an interleaved row only makes the line longer; and streaming is not
  lost, measured at **0.010s to the first row either way** on 60,000 commits with a commit-graph.
- **Evidence**: [ledger: History 依 commit 時間排序](../ledger/2026-09-01-fix-history-graph-commit-date-order.md)
