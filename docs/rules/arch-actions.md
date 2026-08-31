# Intent / Action layer and availability

Pin prefix `ACT-`. Format: [README.md](README.md).

One `GbmActionId` is dispatched by three independent paths; they must all read the same
handler map, and one function decides what a state-dependent gate disables.

## [ACT-intent-layer] Intent / Action layer

`lib/actions/` holds three pure-data files with no Riverpod/FFI dependency:
`gbm_action_id.dart` (the `GbmActionId` enum, 65 values), `gbm_menu_model.dart`
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
2. **macOS system menu bar** — `PlatformMenuBarHost` builds a real
   `PlatformMenuBar` from the same map; `PlatformMenuItem(onSelected:
   handlers[item.id])` — a `null` value is what makes macOS grey the item
   out natively.
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

Twelve ids are gated straight off spec page 07's STATES table — disabled
whenever `RepoSessionState.conflictActive` is true, because each would move
HEAD, start a second sequencer operation, or commit while one is already in
progress: `repositoryFetch`, `repositoryPull`, `repositoryPush`,
`remoteFetchAllRemotes`, `repositoryCommit`, `repositoryAmendLastCommit`,
`branchNewBranch`, `branchCheckout`, `branchMergeIntoCurrent`,
`branchRebaseOnto`, `branchStashChanges`, `branchDeleteBranch`. The banner's
Abort/Skip/Continue/Resolve… stay the only way forward until then.

Two more gates are folded into the same function despite **not** being from
spec page 07 — kept there anyway so every state-dependent availability
decision in the app lives in exactly one place, not because they share the
conflict/clean distinction the twelve above do:

- `branchRenameCurrentBranch` — additionally requires
  `refs.head.branchName.isNotEmpty` (a detached HEAD has no branch to rename).
- `repositoryStageAll` — `workingCopyStatus.unstaged.isNotEmpty` only,
  independent of `conflictActive` entirely (nothing to stage with an empty
  unstaged list, regardless of conflict state).

Every id the switch doesn't cover returns `true` — read that as "the state
machine does not forbid this," not "this is implemented" (see
`_buildActionHandlers()`'s own null entries for ids with no backing feature).
