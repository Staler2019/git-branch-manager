# Orphan wiring: the twelve instances, and the two uncalled functions that are not orphans

- **Kind**: history · **Pins**: `CULT-orphan-wiring` (stays in L0, condensed) · **Code**: see each instance

## Situation
A route, provider, preference or capi field with no caller under `lib/` shipped at least five times: `deleteRemoteBranchDialog`, `readVisibility()`, `readOrder()`/`readWidths()`, `RefreshCoalescer`, the `autoFetch*` settings (**#102**).

## Task
Record every instance so the rule's 「grep both directions」 and 「wire versus delete」 halves keep their evidence after the rule was condensed (2026-10-04).

## Action
- **6th** — `ProcessStarter`'s `workingDirectory` parameter existed and no caller passed it; passing it was the whole fix for the Windows self-install ([CI-windows-cwd-lock]).
- **7th, 8th** — checkbox-era leftovers deleted in C18: nine methods across `WorkingCopySelectionState` and `file_tree.dart`, unit-tested and uncalled, one standing in as a conformance cell's evidence ([SPEC-cell-names-capability]).
- **9th** — a *field* across a language boundary: `ParsedDiff.truncated` was serialized by `JsonCodec`, decoded by `ParsedDiff.fromJson`, taken by `DiffPage`, read by nothing, so a size-refused diff drew 「No changes」. Wired; see `diff_truncation.dart`.
- **10th, 11th** — parameters a feature was waiting on: `FileSavePicker.pickDirectory()` had three callers while two folder fields stayed plain text boxes; `createBranch(setUpstream:)` / `lockWorktree(reason:)` had zero call sites passing one, so P17's checkbox was absent and the 「鎖定原因」 row permanently empty. All wired.
- **12th** — an orphaned *producer*, closed by **deletion**: `RemoveWorktreeOperation` pushed two `OperationChoice`s nothing read (worktree removal rides `workingCopyOperationFinished`, whose handler reads only `succeeded`/`error`; `PendingOperationKind` has no worktree arm). `Remove anyway` is a `--force`, which cannot get past a lock while the capi cannot send a second one ([record](2026-10-04-remove-locked-worktree-has-no-force.md)) — wiring it would have built a lying control. Kept deleted by `RealRepoTest.ListsAddsLocksAndRemovesWorktrees`' `EXPECT_TRUE(blocked.choices.empty())`.
- **Not orphans** — `sameLogicalFile` was moved into its test file as the oracle `logicalFileKey` is checked against (keeping it in `lib/` was the defect); `pairHunkForSideBySide` in `src/core/git/SideBySideDiff.cpp` is the reference implementation the Dart port mirrors line for line, like `GraphAsciiRenderer.cpp` (`SideBySideDiff.h` and `GraphSnapshot.h` say so).

## Result
Eight of the twelve were consumers with no producer; the ninth and twelfth were producers with no reader, invisible to 「who calls this」. An orphan's disposition is a fact about its two ends: eleven were wired because a consumer was waiting, one deleted because the producer's offer could not be honoured.
