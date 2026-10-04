# Removing a locked worktree offers no force path — an implementer's judgement, not a user ruling

- **Kind**: ruling (delegated, **not user-ratified**) · **Pins**: was `GIT-remove-locked-needs-two-forces` · **Code**: `remove_worktree_dialog.dart`, `gbm_worktree_remove()` (`gbm_capi.h`), `RemoveWorktreeRequest::force` (`WorktreeOps.h`)

## Situation
Measured: on a *locked* worktree, `git worktree remove` and `remove --force` fail identically (exit 128, `cannot remove a locked working tree; use 'remove -f -f' to override or unlock first`); only `remove --force --force` succeeds. git checks the lock before uncommitted changes, so one `--force` never reaches the dirty case. `gbm_worktree_remove()`'s `force` is an `int32_t` coerced to `bool`, and `RemoveWorktreeRequest::force` is a `bool` — there is no way to send two.

## Task
The design offered two UI options for removing a locked worktree; the measurement showed neither could be built honestly.

## Action
- No force path at all when locked: the dialog states the lock and points at `Unlock`, git's other named escape and a one-click action in the panel. A checkbox offering to force through a lock would promise what the command cannot do (the deleted `autoFetchPrune` switch is the same shape).
- A prunable worktree (path gone from disk) answers `remove` with exit 0, so disabling `Remove` for it is a UI routing choice (send them to Prune), not something git refuses.
- `RemoveWorktreeOperation`'s two orphaned `OperationChoice`s were deleted rather than wired, because `Remove anyway` was unofferable.

## Result
Pinned by `remove_worktree_dialog_test.dart` (locked: checkbox hidden, button disabled, never dispatches), `worktrees_panel_test.dart` (prunable gate) and `RealRepoTest.ListsAddsLocksAndRemovesWorktrees` (`blocked.choices.empty()`). **Status**: this is the implementer's judgement under delegated authority. A capi change to a force *level* would reopen both UI options — ask the user before assuming either way. Evidence: [ledger: Worktree 面板的五個回報](../ledger/2026-09-03-feat-p19-panel-template-conformance-review.md).
