import '../data/repositories/repo_session_repository.dart';
import 'gbm_action_id.dart';

/// Single source of truth for whether a [GbmActionId] is currently
/// available, given the session's state. This owns only *state-dependent*
/// gates -- ids that always resolve to `null` because their feature isn't
/// implemented yet (e.g. [GbmActionId.fileNewRepository]) are a separate
/// concern, decided by the caller building the handler map, not by this
/// function (see [GbmActionId] docs and `workspace_screen.dart`'s
/// `_buildActionHandlers()`).
///
/// Twelve of these ids come straight from the design spec's page 07 STATES
/// table ("切分支：停用，需先 Continue 或 Abort", "Commit：停用..."): every
/// action that would move HEAD, start a second sequencer operation, or
/// commit is disabled while [RepoSessionState.conflictActive] is true. The
/// banner's Abort/Skip/Continue/Resolve… stay the only way forward.
///
/// [GbmActionId.branchRenameCurrentBranch] and
/// [GbmActionId.repositoryStageAll] are NOT from spec page 07 -- they're
/// pre-existing, independently justified gates (a detached HEAD has no
/// branch to rename; there is nothing to stage with an empty unstaged
/// list) folded into this single function anyway, so every state-dependent
/// action availability decision in the app lives in exactly one place.
/// `repositoryStageAll`'s gate is intentionally independent of
/// `conflictActive` -- staging files is unrelated to the conflict/clean
/// distinction spec page 07 draws.
///
/// Every id not covered by the switch below returns `true`: this function
/// says "the state machine does not forbid this", not "this is
/// implemented" or "this is meaningful right now".
bool isActionEnabled(GbmActionId id, RepoSessionState session) {
  switch (id) {
    case GbmActionId.repositoryFetch:
    case GbmActionId.repositoryPull:
    case GbmActionId.repositoryPush:
    case GbmActionId.remoteFetchAllRemotes:
    case GbmActionId.repositoryCommit:
    case GbmActionId.repositoryAmendLastCommit:
    case GbmActionId.branchNewBranch:
    case GbmActionId.branchCheckout:
    case GbmActionId.branchMergeIntoCurrent:
    case GbmActionId.branchRebaseOnto:
    case GbmActionId.branchStashChanges:
    case GbmActionId.branchDeleteBranch:
      return !session.conflictActive;
    case GbmActionId.branchRenameCurrentBranch:
      return !session.conflictActive && session.refs.head.branchName.isNotEmpty;
    case GbmActionId.repositoryStageAll:
      return session.workingCopyStatus.unstaged.isNotEmpty;
    default:
      return true;
  }
}
