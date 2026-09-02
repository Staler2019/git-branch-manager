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
- **See also**: [GIT-no-index-sees-untracked] — the *diff* half of the same blind spot, which this
  rule's own wording implies and which went unimplemented for as long as this rule existed.
- **Do**: pass `-M` explicitly to both passes rather than trusting `diff.renames`, or the
  rename detection drifts from the one `--porcelain=v2` already did.
- **See also**: [GIT-worktree-status-is-per-path] carries a three-state enum beside its number and
  is **not** a counter-example — the difference is whether a sentinel slot exists at all. Here
  「no matching record」 and 「really zero」 are indistinguishable by construction, so `0` has to
  absorb both; there, 「not run」 has somewhere else to live. Both obey [GIT-no-walk-is-date-ordered]'s
  「absent is not zero」.

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

## [GIT-no-index-sees-untracked] `git diff` cannot see an untracked path, and `--no-index` is how one is diffed

- **Rule**: an untracked path is in neither the index nor HEAD, so `git diff -- <path>` prints
  nothing and the reply arrives as an ordinary *empty* diff. `git diff --no-index -- /dev/null
  <path>` produces the real thing — canonical `new file mode` / `--- /dev/null` / `@@ -0,0 +1,N @@`,
  git's own binary detection, and the `\ No newline at end of file` marker.
- **Consequence**: without it the Working Copy drew 「Nothing unstaged」 over a file whose own row
  badge said `+12`, and `PartialStageOperation` / `DiscardLinesOperation` both answered
  「No pending changes found」 — three defects behind one wall, which is why the fallback lives in
  `DiffService::workingTreeDiff` rather than at any one call site.
- **Rule**: **`--no-index` exits 1 when it finds differences**, i.e. always here, and
  `ProcessRunner::run()` fills `result->out` only on success — so stdout is discarded on that path.
  Read exit 1 as data through `runner_.stream()` plus a local accumulator, the way
  `CompareOps::readMergeBase` already does.
- **Do**: gate it on 「not in the index」, asked as `git ls-files -z -- <path>` and never inferred.
  A tracked *unmodified* file also produces an empty diff, and answering that one with `--no-index`
  renders the whole file as newly added — a wrong diff, worse than the missing one.
- **Do**: gate it on `is_regular_file` too. `git status -uall` reports an untracked nested
  repository as the directory `nested/`, and `--no-index` answers that with
  `Could not access 'nested/null'`.
- **Note**: git special-cases the literal string `/dev/null` in `diff-no-index.c`, so it is the
  empty side on Windows too — it is not a path being stat'ed. **Measured**, not just read off the
  source: all seven of the untracked-diff tests, the subdirectory and binary cases included, pass
  on the `capi (FFI) - Windows` job.
- **See also**: [GIT-zero-means-unmeasured] records the *line-count* half of the same blind spot;
  this is the diff half, which went unwritten for as long as that rule has existed.
- **Evidence**: [ledger: 未追蹤檔案在 Working Copy 看不到 diff](../ledger/2026-09-01-claude-working-copy-untracked-files-qq2gnc.md)

## [GIT-new-file-patch-needs-dev-null] A rebuilt patch for a path not in the index needs `new file mode` and `--- /dev/null`

- **Rule**: measured — `git apply --cached` on a patch headed `--- a/<path>` for a path the index
  does not hold fails with `error: <path>: does not exist in index`, exit 1; with `new file mode
  100644` + `--- /dev/null` it succeeds and leaves the file `AM`, index holding exactly the
  selected lines. `git apply` reads the *mode* line, not the `index` line, to decide it is
  creating a file, so the mode must be echoed (or defaulted) rather than omitted.
- **Consequence**: this is the whole of「staging a scope of an untracked file」; without it the
  diff is visible and every button in it errors.
- **Do**: key the header on `DiffFile::kind == Added`, **never on an empty `oldPath`**. `--- /dev/null`
  does strip to an empty string, but `diff --git a/x b/x` has already filled `oldPath` in and the
  `---` handler declines to overwrite it with nothing — so「has no old side」is a condition that
  reads plausibly and is never true.
- **Do not** change the unstaging direction: by then the file is in the index, `git apply --cached
  --reverse` checks the patch's *new* side against it, and the plain `a/<path>` header is what
  matches. An intent-to-add path (`git add -N`, which `git diff` also reports as `new file mode`)
  accepts the create form on the staging side — measured, exit 0.
- **Evidence**: [ledger: 未追蹤檔案在 Working Copy 看不到 diff](../ledger/2026-09-01-claude-working-copy-untracked-files-qq2gnc.md)

## [GIT-apply-without-cached-follows-autocrlf] `git apply` without `--cached` writes the work tree, so its output follows `core.autocrlf`

- **Rule**: `--cached` writes a *blob*, where autocrlf's clean filter normalises to LF on the way
  into the index; without it git rewrites the file on disk and applies the smudge direction. Git
  for Windows ships `core.autocrlf=true` in its **system** config, so a fresh `git init` fixture
  inherits it with nothing in the repo saying so.
- **Consequence**: a byte-exact assertion on work-tree content is platform-dependent.
  `DiscardsSelectedLinesOfAnUntrackedFile` wrote `a\nb\nc\n`, discarded one line, and got
  `"a\r\nc\r\n"` back on the Windows runner — one red job out of 621 tests, on eleven checks where
  every other platform was green.
- **Do not** "fix" it in the operation: that would override the user's own git config, and a real
  Windows user's untracked file already has CRLF, so git rewriting it as CRLF is correct.
- **Do**: set `core.autocrlf=true` in the test *and* normalise the assertion. Leaving it to the
  platform makes the normalisation a no-op on Linux, so nothing outside the Windows CI job could
  show it was load-bearing — measured: with the config forced, deleting the normalisation reddens
  on Linux too.
- **Note**: the staging mirror needs none of this, and the contrast is the evidence for the cause —
  `StagesSelectedLinesOfAnUntrackedFile` passed on Windows in the same run because it applies with
  `--cached`.
- **Evidence**: [ledger: 未追蹤檔案在 Working Copy 看不到 diff](../ledger/2026-09-01-claude-working-copy-untracked-files-qq2gnc.md)

## [GIT-worktree-status-is-per-path] A per-worktree pending count is one `git status` per path, and two kinds of worktree must not be asked at all

- **Rule**: the command is `git <globalFlags> -C <worktreePath> -c core.fsmonitor=false status
  --porcelain=v2 -z --untracked-files=normal`. It reads that work tree against its own index, so
  [GIT-worktree-reads-need-fsmonitor-off] applies verbatim.
- **Rule**: `--untracked-files=normal`, **never `-uall`** — the count is of *changes*, and an
  untracked directory is one change, not one per file inside it. Measured on this repository,
  warm, 20 iterations: **13.4 ms** with `normal` against **20.9 ms** with `-uall`. Read that 56%
  as a floor rather than the reason: every output directory here is gitignored, so the real cost
  [GIT-zero-means-unmeasured] records (enumerating an unbuilt output tree) never fired.
- **Do**: **reuse the porcelain-v2 entry parser; never count NUL records yourself.** A rename
  (`2 …`) spends one *more* NUL field than every other kind — the same shape as
  [GIT-output-format-single-slot]'s three-record rename — so a record counter is silently wrong
  from the first rename onward, and correct on every fixture that has none.
- **Rule**: **a bare or prunable worktree is not asked at all.** Bare answers `fatal: this
  operation must be run in a work tree`; a prunable path is not on disk. Both are
  [STATE-never-guess-what-git-would-say]'s *LFS exemption* word for word — not approximating an
  answer, knowing the command cannot run — and neither is a `.gitmodules`-style guess.
- **Do**: report it as a **three-state** field (`unmeasured` / `measured` / `notApplicable` /
  `failed`) beside the number, not as a sentinel. The enum is what lets `0` mean 「measured, and
  clean」 — see [GIT-zero-means-unmeasured] for the case where no such slot exists.
- **Do**: cache the answer on `path@headOid` and write **`failed` into the cache too**. A gate
  reading 「some count is null」 re-asks forever on the failure path, because a reply saying
  「failed」 leaves the same null; a gate reading 「some key is absent」 terminates on every branch.
- **Evidence**: [ledger: 十二個管理面板照 P19 樣板統一](../ledger/2026-09-02-feat-p19-panel-template-conformance.md)
