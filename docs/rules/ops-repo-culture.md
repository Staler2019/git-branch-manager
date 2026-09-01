# Repo culture

Pin prefix `CULT-`. Format: [README.md](README.md).

## [CULT-standing-rules] Three standing rules about how a round is run

Set by the user, not derived from the code — they outrank convenience every time.

1. **Hitting a related issue means reading the spec and the decision record and *fixing
   it*.** Ask only when neither has the answer. An issue number is not permission to stop.
2. **Never produce a 「本輪不做」 without the user's decision.** A reduction is the user's
   call, not the implementer's; where something truly cannot be done, say what blocks it
   and finish everything else.
3. **Never open an issue without the user's consent.** Existing issues may be updated or
   closed; a new one is a decision, not a filing action.

## [CULT-cache-documents-three-things] Every cache documents three things, and needs a test that invalidation recomputes

- **Rule**: document what the key is *and why it distinguishes every case it must*; which
  named events invalidate it; what symptom appears if invalidation is missed.
- **Rule**: "which events" can legitimately be **none** — `UntrackedLineCountCache` has no
  event to subscribe to because an editor saving a file emits no `GBM_EVENT_*`, so the key
  *is* the invalidation. Saying so is part of the documentation, not a gap in it.
- **Do**: the test must **count** (`hits()`/`misses()`, an injected counting stand-in),
  never assert on the result alone — a cache that recomputed every time and answered
  correctly is indistinguishable from a working one by its output.
- **Do**: prefer removing the recomputation to caching it. C18's `FileTree` candidate turned
  out to be a code path that should not have run at all in the default mode.

## [CULT-warm-the-jit] Warm the JIT before timing, on every path being compared

- **Rule**: timing cases in one loop with N increasing puts the smallest N on the coldest JIT.
- **Consequence**: it produced a table where the *indexed* lookup got cheaper as the graph
  grew (8.85µs → 2.08µs → 0.58µs per row) — an impossible shape for an index — and it read
  as "the index is slower on small repos", nearly buying a threshold nothing needed.
- **Do**: after 20k warm-up iterations on both paths the indexed cost is flat (~0.5µs) at
  every N. **A per-N cost that falls as N rises is the tell.**
- **Evidence**: ledger: History 捲動卡頓

## [CULT-measure-before-caching] Measure before caching, and put the number in the ledger

- **Rule**: C18's two numbers, debug JIT — splitting a 40×200 `DiffFile` into scopes is
  **197µs** and ran *every frame* of a selection drag (cached); `FileTree.fromPaths` over
  100 paths is **41µs** and runs per click (not cached).
- **Consequence**: the second is written down precisely so the next round re-decides from a
  number rather than from the same guess.

## [CULT-orphan-wiring] Orphan wiring is the recurring defect shape here

- **Rule**: a route, provider, preference or capi field with no caller under `lib/`. It has
  shipped at least five times (`deleteRemoteBranchDialog`, `readVisibility()`,
  `readOrder()`/`readWidths()`, `RefreshCoalescer`, the `autoFetch*` settings — **#102**).
- **Do**: grep for a caller before adding a field, **and before deleting the last one**.
- **Consequence**: the sixth instance was worse than dead weight — `ProcessStarter`'s
  `workingDirectory` parameter existed and no caller ever passed it, and passing it was the
  whole fix for the Windows self-install ([CI-windows-cwd-lock]).
- **Consequence**: the seventh and eighth were checkbox-era leftovers deleted in C18 — nine
  methods across `WorkingCopySelectionState` and `file_tree.dart`, all unit-tested and all
  uncalled, one of which was standing in as a conformance cell's evidence
  ([SPEC-cell-names-capability]).

## [CULT-reference-impl-not-orphan] Not every uncalled function is an orphan

- **Rule**: two keepers, for two different reasons.
- **Rule**: `sameLogicalFile` was kept by **moving it into its test file** — it is the
  independently-written *oracle* `logicalFileKey` is checked against, and keeping it in
  `lib/` was the actual defect, since a bug in the key could otherwise hide inside the thing
  that checks it.
- **Rule**: `pairHunkForSideBySide` in `src/core/git/SideBySideDiff.cpp` has no caller and
  never will, because the Dart port that *is* called mirrors it line for line — it is the
  **reference implementation**, exactly as `GraphAsciiRenderer.cpp` is for the graph
  ([CPP-ascii-renderer-is-reference]). Both headers now say so; deleting it would take the
  reference with it.

## [CULT-correct-the-record] Deleting code as an orphan obliges you to correct the record that justified it

- **Rule**: or the deletion repeats.
- **Consequence**: `side_by_side_diff.dart` was deleted in C13 on a correct reading — the
  spec really does not ask for a side-by-side diff — and the verdict was filed in
  `docs/reports/spec-conformance-matrix.md` as 「orphaned code answering no requirement」.
  When the user later ruled the feature *in*, that row would have justified deleting the
  restored files a second time on grounds already overruled.
- **Do**: both halves are load-bearing — strike and rewrite the row **in place** (the
  #45/#50/#51/#60 precedent), *and* put the citation in the restored files' own doc
  comments, because an orphan sweep starts from the code and may never open the report.
- **Note**: what survives the correction — the spec claim was true then and is true now;
  what stopped being true is that 「no spec basis」 is sufficient grounds.
- **Evidence**: ledger: History 的並排 diff

## [CULT-do-not-derive-what-you-have] Deriving a quantity you already have is how a bug hides in the majority case

- **Consequence**: the restored side-by-side view read a line's number as
  `kind == removed ? oldLine : newLine` — right for a removed line and an added one, wrong
  for every *context* line in the left column, which is neither and so fell through to
  `newLine`. Invisible whenever a hunk starts at the same number in both files, so it only
  appears once an earlier hunk has added or removed lines.
- **Do**: move the decision one level up, to the thing that actually knows — the **column**
  picks the number (`SideBySideSide.left => oldLine`), not an inference from the row.
- **Do**: a fixture that does not set `oldStart != newStart` cannot see it.

## [CULT-single-source-of-truth] A second source of truth for a computed fact is how a bug hides

- **Rule**: it cannot disagree with itself. Folder identity, column order, selection sets,
  `conflictActive`, `submitCommit()` (the only place a commit message is composed and
  dispatched) and `scopeButtonLabel()` are each deliberately single-sourced.

## [CULT-nothing-silently-dropped] Nothing is silently dropped

- **Rule**: a capability removed for spec conformance gets its reason recorded (the
  operation-log dialog's `Clear`, the per-remote Pull/Push), and a reduction made for a cap
  or a missing capi is written down rather than left for the next audit to file as a bug.
- **Consequence**: **a reduction note names one victim of a missing capability, not all of
  them.** `commit_selection_summary.dart` recorded P13's 合計 diff as absent because
  `ChangedFile` had no line counts, and P02-10's badge — same missing field, no running
  total needed — went unfiled for rounds.
- **Do**: grep for other readers of whatever a note calls absent before trusting its blast
  radius.
- **Evidence**: ledger: Changed files line counts

## [CULT-scrutinise-the-comment] A note explaining why a test avoids a code path deserves the same scrutiny as the code path

- **Consequence**: one correct observation with a wrong cause became a permanent workaround
  and hid a real defect for months.
- **Consequence**: the same holds for a comment explaining why the *implementation* is
  shaped as it is. `_keysInRenderOrder` built a `FileTree` unconditionally on a comment
  claiming 「both list and tree mode render through `FileTree.fromPaths`」, and list mode does
  not — so Shift-ranging in the default mode spanned tree order over rows painted in entry
  order, and the test that should have caught it pumped the default mode while asserting
  tree order, repeating the same wrong premise in its own comment (C18).
- **Do**: **when a comment states what two code paths have in common, pump both and look**,
  rather than trusting the sentence.
- **Do**: **a mutation that fails to land where the comment predicted means the comment is
  wrong**, not the mutation. Keying `attachLineCounts()` on `oldPath` was supposed to break
  deletes and broke only renames — `oldPath` is empty for every kind but rename/copy — so
  both the comment and the test's rationale were corrected.

## [CULT-remeasure-when-upstream-moves] A comment claiming measured bounds must be re-measured when anything upstream moves

- **Rule**: a page recomposition is upstream of every width in the row.
- **Rule**: the same holds for a comment claiming a *performance* property — `ChangedFile`'s
  「Cheap: no content is read, so clicking through commits stays instant」 stopped being true
  the round a second git invocation was added, and that round owned rewriting it.

## [CULT-stage-by-file] Stage by file when two changes are live in one directory

- **Rule**: `git add -A <dir>` once swept an unrelated in-progress change into a `refactor:`
  commit.
- **Consequence**: the opposite error is filing a file by where its *assertions* belong
  rather than where its *compilation* does. A commit that adds a `required` field to a model
  must carry every fixture that constructs **or feeds** it — a raw-JSON fixture is invisible
  to a grep for the constructor name, and a missing key is `null as int` at runtime.
- **Do**: only a per-commit checkout sees this; every run at the branch tip is green.
- **Evidence**: line-counts round

## [CULT-log-both-sides-of-a-handover] A diagnostic channel only the far side of a handover writes is no channel at all

- **Rule**: if the UI names a log file to the user, everything that can fail *before* the far
  side starts must already be in it.
- **Consequence**: `gbm-update.log` had exactly one writer, the generated updater script, while
  the dialog promised 「if it does not come back, `<temp>\gbm-update.log` says why」. Every
  app-side failure — a corrupt archive, a shell that would not start, a session close that never
  returned, `install()`'s own guard `return` — produced a `.ps1` on disk with **no log beside
  it**. That is the entire user-visible evidence of the reported bug.
- **Do**: give the near side ownership of **truncation** and leave the far side append-only.
  The original reason for truncating (a transcript accumulating every run buries the one being
  asked about) is preserved by moving it to the start of the attempt, not by deleting the near
  side's half every time.
- **Do**: a bare `return` on a guard, and a `catch` that collapses an exception to a `bool`, are
  both this rule's failure in miniature — «The system cannot find the file specified» and
  «Access is denied» send the user somewhere different, and a `bool` sends them to neither.
- **Evidence**: [ledger: Install and restart 卡在 Installing…](../ledger/2026-09-01-claude-windows-app-update-install-irloo0.md)
