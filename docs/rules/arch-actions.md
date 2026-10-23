# Intent / Action layer and availability

Pin prefix `ACT-`. Format: [README.md](README.md).

One `GbmActionId` is dispatched by three independent paths; they must all read the same
handler map, and one function decides what a state-dependent gate disables.

## [ACT-intent-layer] Intent / Action layer

`lib/actions/` holds three pure-data files with no Riverpod/FFI dependency:
`gbm_action_id.dart` (the `GbmActionId` enum), `gbm_menu_model.dart`
(the menu-bar/label/shortcut-string model `MenuBarRow` and the keyboard
shortcuts dialog both read), and `gbm_shortcuts.dart`
(`GbmActionId -> GbmKeyboardShortcut`, platform-aware Cmd/Ctrl binding).

A `GbmActionId` is dispatched by three independent paths, which **must all
read the same `Map<GbmActionId, VoidCallback?> actionHandlers`** — the one
`WorkspaceScreen._buildActionHandlers()` builds once per build and hands to
all three:

1. **Keyboard** — `WorkspaceActionShortcuts` (`workspace_action_shortcuts.dart`)
   wraps the shell in `Shortcuts` + `Actions`; a bound key press dispatches a
   `GbmActionIntent(id)`, whose `CallbackAction` calls `handlers[id]?.call()`.
2. **macOS system menu bar** — `PlatformMenuBarHost` ~~builds a real
   `PlatformMenuBar` from the same map~~ sends the same map to
   `platformMenuDelegate` (two `PlatformMenuBar`s collide on a page swap);
   `PlatformMenuItem(onSelected: handlers[item.id])` — a `null` value is what
   makes macOS grey the item out natively.
3. **In-window menu** — `MenuBarRow` (rendered instead of (2) on non-macOS,
   spec page 01) resolves most ids via `Actions.maybeInvoke(context,
   GbmActionIntent(id))`, which reaches the same `Actions` block as (1). Five
   ids (`repositoryFetch`/`Pull`/`Push`, `viewToggleSidebar`, `fileExit`) are
   special-cased to named constructor params instead, because their
   real implementation predates the shared-map refactor and still lives
   there — see `MenuBarRow._resolveHandler`'s doc comment.

## [ACT-one-handler-map] All three dispatch paths must read the same handler map

**A real, previously-shipped bug came directly from breaking this
invariant**: `_buildActionHandlers()` once hardcoded `repositoryFetch`/
`Pull`/`Push`/`viewToggleSidebar` to `null` in the map "because MenuBarRow
handles them via its own params" — which made the in-window menu click work
(path 3 bypasses the map for those ids) while the keyboard shortcut and the
macOS menu item (paths 1–2, which both read the map directly) silently
no-op'd. `test/integration/workspace_intent_dispatch_parity_test.dart`
exists specifically to catch a regression of this shape. **Rule**: when
wiring or changing what a `GbmActionId` does, change
`_buildActionHandlers()` (or the policy function below it calls) — never
add a fix that only touches `MenuBarRow`'s named params.

## [ACT-action-reads-mode] An action whose meaning depends on a mode must read the mode

**An action whose meaning depends on a mode must read the mode, not assume
it.** Amend is a mode (`WorkingCopyDraft.amending`), so `repositoryCommit`
passes `amend: amending` rather than a hardcoded `false` — otherwise
`Ctrl/Cmd+Enter` writes a second commit while the button in front of the user
says `Amend`. The mirror case matters more: `repositoryAmendLastCommit`
*enters* the mode when it is off, instead of rewriting HEAD sight-unseen.
Both live in `workspace_screen.dart`; `beginAmendMode()` and `submitCommit()`
in `working_copy_repository.dart` are the single sources the box's buttons
call too.

## [ACT-availability] Action availability state machine

`lib/actions/gbm_action_availability.dart`'s `isActionEnabled(GbmActionId,
RepoSessionState)` is the single source of truth for which actions a
state-dependent gate disables — every other call site (`workspace_screen.dart`'s
`_buildActionHandlers()`, `sidebar_panel.dart`'s `BranchTreeItem.conflictActive`,
`working_copy_view.dart`'s commit-box `canCommit`, `MenuBarRow`'s
`GbmMenuItem.enabled` grey-out, and `ActionToolbar`'s five buttons, which take
their `null`-means-disabled straight out of the handler map) reads through this
function rather than re-deriving `session.conflictActive` locally.

Which ids a gate disables, and why (spec page 07's STATES table, ruling ④,
the rename and stage-all gates), is the switch and doc comment of
`isActionEnabled`, pinned by `gbm_action_availability_test.dart`. An id the switch
doesn't cover returns `true`: "the state machine does not forbid this", not
"this is implemented".

## [ACT-recovery-choice-wire] `OperationChoice`'s wire carries `kind`+`destructive` only; every string is composed on read

- **Rule**: `OperationChoice` (`OperationRunner.h`) has exactly two fields,
  `Kind kind` and `bool destructive`. `JsonCodec.cpp`'s `operationChoiceJson()`
  sends only those two keys. Neither a button label nor its explanation ever
  reaches the wire — `recovery_choice_copy.dart`'s
  `recoveryChoiceLabel(OperationChoiceKind)` /
  `recoveryChoiceExplanation(OperationChoiceKind, {required forDeleteBranch})`
  compose both, in Dart, from `kind` alone.
- **Consequence**: composed once in C++ and painted verbatim, the English there
  drifted from the spec's quoted button text (`DLGS`'s 「Checkout blocked」); the design was
  retired rather than patched.
- **Rule**: **a `kind` with no Dart reader gets no `OperationChoice` at all** —
  not a stripped-down one. `_handleOperationOutcome`'s switch
  (`repo_session_repository.dart`) has case arms for
  `PendingOperationKind.checkout`/`.deleteBranch` only; every other kind's
  `choices` were never read by anything under `lib/`
  ([CULT-orphan-wiring]). `MergeOps.cpp`, `RebaseOps.cpp`,
  `CherryPickOps.cpp`, `RevertOps.cpp` and `RemoteOps.cpp`'s pull path all
  push zero choices on a `DirtyWorkTree` refusal now — `outcome.summary`/
  `outcome.error` still carry the failure through the ordinary `lastError`
  path, so nothing the user could see is lost. `RemoteOps.cpp`'s deletion
  leaves `DLGS`'s "Pull blocked" entry with no backing dialog at all; see
  [DRIFT-no-pull-dialog] for that gap.
- **Rule**: `OperationRunner::preflight()`'s sequencer-busy `Abort` choice is the one
  kept: as the sole choice it makes `choices` non-empty, which `WorkspaceScreen`
  reads to auto-push the recovery dialog (`OperationRunner.cpp`). `CheckoutOp.cpp`
  and `BranchOps.cpp` carry no `Abort`: both dialogs filter it out (site comments).
- **Do**: when adding a new recovery-dialog-visible `OperationChoiceKind`,
  wire it in exactly two places — the C++ side that decides *whether* to
  offer it, and `recovery_choice_copy.dart`'s two functions that decide
  *what it says*. Never add a third place that composes a string and sends
  it across the FFI boundary; that is the design this pin retired.
- **Evidence**: [ledger: OperationChoice wire 精簡](../ledger/2026-09-04-fix-prune-stale-comment-and-recovery-choice-copy.md)
