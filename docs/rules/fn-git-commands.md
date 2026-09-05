# Invoking git correctly

Pin prefix `GIT-`. Format: [README.md](README.md).

## [GIT-branch-d-partially-succeeds] `git branch -d`/`-D` is per-name and partially succeeds

- **Rule**: `exit 1` does not mean nothing happened. Measured: `git branch -d a cur b`
  deletes `a` and `b`, refuses `cur`, and still exits 1.
- **Consequence**: a single exit-code check reports total failure for work that is mostly
  done, and a force retry then resends the already-deleted names, which fail as 「not found」
  and report total failure a second time. That is the whole of the user's three-line error log.
- **Consequence**: **the second half is refreshing, and it went unwritten here for as long as
  this pin existed.** A partial delete is a *failed* outcome sitting on top of a repository
  that really moved, and `Session::submitOperation` refreshed refs on `succeeded` alone — so
  the sidebar went on drawing branches git had already removed until the next F5 or window
  focus. Single-branch delete is all-or-nothing, so only the multi-select path (the sidebar's
  own Delete button) could ever show it, which is exactly how it was reported.
- **Do**: `DeleteBranchOperation` probes `git for-each-ref` before (send only what still
  exists) and after a failure (say what really went).
- **Do**: **that same after-probe is the evidence for the refresh**, via
  `OperationOutcome::mutatedRefs` (`!deleted.empty()`). Evidence, not assumption: an empty
  `deleted` means either nothing went *or* the probe could not tell, and neither is grounds
  for claiming the repository changed — [STATE-never-guess-what-git-would-say] applied to a
  refresh decision. The flag is **deliberately not serialized**; the decision is taken inside
  Session's completion callback before `toJson(outcome)`, and a wire field with no Dart reader
  is [CULT-orphan-wiring].
- **Note**: the remote half (`git push <remote> --delete a b c`) partially succeeds the same
  way and has **no** before/after probe, so `mutatedRefs` is never set on that path —
  使用者裁定 this round is local-only. Adding one costs a network round trip, which is why it
  is a decision rather than an omission.
- **Do not** parse per-name stderr — those strings are gettext-localised, so they may inform
  a *message* but never a correctness decision.
- **Evidence**: [ledger: 部分成功的刪除不刷新](../ledger/2026-09-05-fix-partial-branch-delete-no-refresh.md)

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

## [GIT-worktree-prune-has-no-expire] `git worktree prune` takes no `--expire`, so a lock is the only thing standing between a temporarily-absent worktree and deletion

- **Rule**: git marks a worktree prunable as soon as its directory is missing, and
  `WorktreeOps.cpp`'s `PruneWorktreesOperation` runs a bare `git worktree prune --verbose`. The
  `--expire 3.months.ago` that makes this safe is `git gc`'s, not ours.
- **Consequence**: an unmounted volume, a network share that is briefly away, a path being moved
  — each reads as prunable, and pruning discards the administrative link permanently.
- **Do**: **never prune a locked worktree.** git itself refuses, and the meaning is exactly right:
  a lock is the user saying 「keep this」 about a path that may be coming back. That refusal is the
  only guard, so anything that prunes automatically must respect it explicitly rather than relying
  on git to say no.
- **Rule**: [REF-fetch-auto-prunes] extends to worktrees — 使用者裁定 「prune 是背景做掉，所以使用
  者不需要知道」 — with the preview step dropped, because `git worktree list --porcelain` already
  names the prunable entries and no `--dry-run` is needed to learn them.
- **Do**: **gate the automatic prune on 「this path has never been tried」, never on 「this path is
  prunable」.** A prune re-publishes the worktree list, and anything it could not remove (locked, or
  a failure) is *still prunable* in that snapshot — so the obvious predicate is an infinite loop.
  Same shape as writing `failed` into [GIT-worktree-status-is-per-path]'s cache: ask whether the key
  is absent, not whether the value is empty.
- **Do**: keep an automatic prune's failure out of `lastError` while still logging it. Attribution
  cannot use `PendingOperationKind` — it has no arm for a worktree prune and the capi carries no
  request identity — so match `GitError.argv` and consume one in-flight marker, exactly as the
  automatic *preview* suppressor does, so the user's own `Prune` button still reports its failures.
- **Evidence**: [ledger: 十二個管理面板照 P19 樣板統一](../ledger/2026-09-02-feat-p19-panel-template-conformance.md)

## [GIT-remove-locked-needs-two-forces] `git worktree remove --force` does nothing about a lock, and the capi cannot send the second `--force`

- **Rule**: measured — on a *locked* worktree, `remove` and `remove --force` fail **identically**
  (exit 128, same message); only `remove --force --force` succeeds (exit 0). git checks the lock
  before it checks for uncommitted changes, so a single `--force` never reaches the dirty case at
  all when a lock is present.
- **Rule**: git's own error names both escapes verbatim: `cannot remove a locked working tree; use
  'remove -f -f' to override or unlock first`.
- **Consequence**: `gbm_worktree_remove()`'s `force` is an `int32_t` coerced to a `bool`, and
  `RemoveWorktreeRequest::force` is a `bool` — **there is no way to send two**. So a checkbox or a
  second confirmation offering to force through a lock is a control that promises what the command
  cannot do, exactly the shape [REF-fetch-auto-prunes] records for the deleted `autoFetchPrune`
  switch.
- **Do**: offer no force path at all when locked; state the lock and point at `Unlock`, which is
  git's other named escape and already a one-click action in the panel.
- **Note**: **implementer's judgement under delegated authority, not user-ratified.** The design
  offered two UI options and the measurement showed neither could be built honestly. A capi change
  to a force *level* would reopen both; ask before assuming.
- **Note**: a worktree whose path is already gone from disk answers `remove` with **exit 0** — git
  just drops the administrative entry. So disabling `Remove` for a prunable worktree is a UI
  routing choice (send them to Prune), **not** something git refuses.
- **Evidence**: [ledger: Worktree 面板的五個回報](../ledger/2026-09-03-feat-p19-panel-template-conformance-review.md)

## [GIT-primary-not-current-worktree] `isMain` is the worktree you are standing in; `isPrimary` is the repository's main one, and every gate must pick deliberately

- **Rule**: they are the same row only when gbm is open on the primary worktree, which is the
  common case and therefore the one every fixture defaults to.
- **Rule**: git refuses two things on the *primary* worktree, both measured: `git worktree remove`
  on it, and `git worktree lock`/`unlock` on it (`fatal: The main working tree cannot be locked or
  unlocked`, exit 128). A **linked** worktree is removed and locked happily, including from inside
  the session that is open on it.
- **Consequence**: a gate spelled `isMain` inverts on a linked worktree — it refuses the row the
  user is standing in and offers the primary one. Both the Remove and the Lock/Unlock buttons
  shipped that way, five lines apart.
- **Do**: **a fixture where the two coincide cannot see this at all.** The test that can is one
  holding a `isPrimary && !isMain` row *and* a `isMain && !isPrimary` row at once.
- **Do**: when you fix one instance of a shape like this, **grep the neighbours before the
  comment you just wrote goes stale** — the second instance here was found only because a later
  commit happened to rewrite that button anyway. [CULT-scrutinise-the-comment] runs
  comment → bug; this is the reverse direction, fixed bug → unfixed twin.
- **Evidence**: [ledger: Worktree 面板的五個回報](../ledger/2026-09-03-feat-p19-panel-template-conformance-review.md)

## [GIT-index-lock-server-revalidates] Removing a stale `.git/index.lock` re-checks staleness on the server, and never trusts the click that asked for it

- **Rule**: `OperationRunner::removeStaleIndexLock()` re-reads `RepoState::read(paths_)` itself
  and only removes `paths_.indexLockFile()` when `indexLockAgeSeconds` is still past
  `kStaleLockSeconds` at the moment of the call. The Dart side's request (the user clicking
  `RemoveLock` on a choice `preflight()` offered, possibly seconds or minutes earlier) is never
  taken as proof the lock is still stale — a lock genuinely held by a concurrent git process must
  never be deleted out from under it, and a `bool` crossing the FFI boundary saying "the button
  was clicked" carries none of that guarantee.
- **Rule**: this is the same "ask the command, never approximate it" discipline
  [STATE-never-guess-what-git-would-say] states for a refresh gate, applied to a destructive
  filesystem action instead of a decision not to run something.
- **Do**: **the Dart caller never inspects whether removal succeeded before acting** —
  `_removeStaleIndexLock()`'s doc comment states this is deliberate: both
  `retryCheckoutWithChoice`/`retryDeleteBranchWithChoice`'s `removeLock` case call it and then
  unconditionally resubmit the original request regardless of what it returned, letting that
  resubmission's own `preflight()` re-arbitrate against whatever is really on disk — gone, it
  proceeds; still fresh, it refuses again with a freshly re-offered (and now accurate) choice set.
  One path, correct either way, instead of a second "remember the stale choices and hope" branch
  that duplicates what `preflight()` already does for free.
- **Consequence**: the capi entry point (`gbm_operation_remove_stale_index_lock`) and this
  function were both new — before this round `RemoveLock` was a choice `preflight()` could offer
  with **no way to act on it at all** ([ACT-recovery-choice-wire] records the sibling `Retry`
  choice's identical dead-button shape and how both were wired in the same round).
- **Evidence**: [ledger: OperationChoice wire 精簡](../ledger/2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md)

## [GIT-remote-pick-b-only-when-absent] Picking a remote branch means the local branch of the same name, and `-b` is correct only while that local branch does not exist

- **Rule**: measured on git 2.55, for both `git worktree add` and `git checkout`:

  | local `feat/x` | `-b feat/x … origin/feat/x` | plain `… feat/x` |
  |---|---|---|
  | absent | creates a tracking branch, exit 0 | n/a |
  | exists, free | `fatal: a branch named 'feat/x' already exists` | exit 0, reports it tracking the remote |
  | exists, checked out elsewhere | the same `fatal` | `fatal: 'feat/x' is already used by worktree at …` |

- **Consequence**: `createBranch: <the pick is remote>` is wrong in two of the three rows,
  and the failing one is the **commonest**: a branch you already have locally, picked from
  the remote half of the list. Add Worktree and Checkout each shipped exactly that
  expression; the worktree one was 使用者回報 with the `exit 255` transcript.
- **Do**: gate on 「is there a local branch of this name」, and send the *local* name when
  there is. Anything downstream that names the branch — a default worktree path, a
  「建立本地分支「X」」 line — must read the same resolution, or it describes an operation
  that will not happen.
- **Do**: **a remote row is occupied exactly when its local counterpart is.** Add Worktree
  greyed the local row for a checked-out branch and left `origin/<same name>` selectable —
  one branch drawn two ways, and the selectable one reached git as the `fatal` above.
- **Do not** rely on `git worktree add <path> origin/feat/x`'s DWIM as a general fact. It
  creates the tracking branch **only while no local `feat/x` exists**; once one does, the
  same command *detaches* instead (measured). A comment here recorded the first half alone
  and read as a general rule ([CULT-scrutinise-the-comment]).
- **Do**: a fixture with one remote row cannot tell the three cases apart, and if that row's
  local counterpart happens to exist it pins the bug. The Add Worktree test asserting `-b`
  was named 「remote-only」 while its fixture had a local `release/0.5`
  ([TEST-fixture-cannot-disagree]).
- **Evidence**: [ledger: 追加三](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)
