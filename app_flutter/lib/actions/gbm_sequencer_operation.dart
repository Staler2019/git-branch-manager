import '../data/models/repo_state.dart';

/// Which kind of git sequencer-shaped operation is currently in progress,
/// and what Abort/Skip/Continue mean for it.
///
/// Single source of truth for a judgment call this codebase used to make
/// independently in six different places (`ConflictBanner`,
/// `_backgroundTasks`, and their dispatchers in workspace_screen.dart;
/// `SequencerBanner` and the two derivations in
/// conflict_resolve_window.dart; the status-bar chip in status_bar.dart) --
/// each hand-rolling the same "which flag is set, which controls are valid"
/// logic, with subtly inconsistent priority order between copies. Mirrors
/// the pattern `isActionEnabled()` (gbm_action_availability.dart) already
/// established for action gating: one function, every call site reads
/// through it.
///
/// IMPORTANT: this deliberately does **not** mean the same thing as
/// `RepoState.isSequencerOperation` (mirrored from
/// `gbm::RepoState::isSequencerOperation()`, src/core/git/RepoState.h). The
/// core's version excludes merge on purpose -- a plain `git commit`
/// finishes a merge, there is no sequencer todo-file involved -- while a
/// merge conflict is exactly the kind of state this app's UI needs an
/// Abort control for. [activeSequencerOperation] therefore *includes*
/// merge. Do not use the two interchangeably.
enum SequencerOperationKind {
  rebase,
  cherryPick,
  revert,
  merge;

  /// Display label matching the strings already shown in
  /// `ConflictBanner`/`SequencerBanner` ("Merge", "Cherry-pick", "Revert",
  /// "Rebase").
  String get label => switch (this) {
    SequencerOperationKind.rebase => 'Rebase',
    SequencerOperationKind.cherryPick => 'Cherry-pick',
    SequencerOperationKind.revert => 'Revert',
    SequencerOperationKind.merge => 'Merge',
  };

  /// Present-participle form for status-line/background-task text
  /// ("Rebasing", "Cherry-picking", ...).
  String get gerund => switch (this) {
    SequencerOperationKind.rebase => 'Rebasing',
    SequencerOperationKind.cherryPick => 'Cherry-picking',
    SequencerOperationKind.revert => 'Reverting',
    SequencerOperationKind.merge => 'Merging',
  };

  /// Whether an Abort control is meaningful for this kind. Merge included
  /// (`git merge --abort`); revert excluded -- see [canContinue].
  bool get canAbort => this != SequencerOperationKind.revert;

  /// Whether a Skip control is meaningful. Only cherry-pick and rebase have
  /// a real `--skip`; merge has no notion of skipping one file's conflict
  /// and moving to the next commit, and revert has neither skip nor
  /// continue (see RevertOps.h).
  bool get canSkip =>
      this == SequencerOperationKind.cherryPick ||
      this == SequencerOperationKind.rebase;

  /// Whether a Continue control is meaningful. Same two kinds as
  /// [canSkip]: merge has no backend continue (a plain commit finishes a
  /// merge -- there is no `gbm_merge_continue()`), and revert has no
  /// continue/skip/abort entry point at all yet.
  bool get canContinue => canSkip;
}

/// Derives the active [SequencerOperationKind] from [state]'s flags, or
/// null if none is set (including when [state] itself is null -- no
/// GBM_EVENT_REFS_UPDATED-backed RepoState has arrived yet, or the working
/// copy is clean).
///
/// Priority when more than one flag is set -- rebase > cherry-pick > revert
/// > merge -- is not arbitrary: a conflicted `git rebase` using the merge
/// backend can leave `CHERRY_PICK_HEAD` on disk mid-step, so
/// [RepoState.isRebasing] and [RepoState.isCherryPicking] can both be true
/// at once, and "Rebase" is the correct label and control set in that case,
/// not "Cherry-pick". `SequencerBanner`'s and status_bar.dart's old
/// independent label ladders got this wrong (merge-first order): this is a
/// deliberate behavior correction, not just a dedup.
SequencerOperationKind? activeSequencerOperation(RepoState? state) {
  if (state == null) return null;
  if (state.isRebasing) return SequencerOperationKind.rebase;
  if (state.isCherryPicking) return SequencerOperationKind.cherryPick;
  if (state.isReverting) return SequencerOperationKind.revert;
  if (state.isMerging) return SequencerOperationKind.merge;
  return null;
}
