#pragma once

#include "core/git/RepoPaths.h"

#include <string>

namespace gbm {

/// Design C3: git already writes a commit message for the user before they
/// ever open a commit dialog -- "Merge branch 'x'" plus a "# Conflicts:"
/// listing once conflicts are involved (MERGE_MSG), or the squash summary
/// (SQUASH_MSG) for `git merge --squash`. Reading it here is what lets the
/// working copy view pre-fill the commit message box instead of making the
/// user retype what git already prepared.
///
/// MERGE_MSG takes priority when both exist (a squash merge never writes
/// MERGE_HEAD, so mergeMsgFile() alone can't tell the two operations apart,
/// but a plain merge never writes SQUASH_MSG either -- the two are mutually
/// exclusive in practice). Returns an empty string when neither file exists,
/// e.g. conflicts produced by `git apply --3way`, which prepares no message
/// at all -- that is a normal case, not an error, so there is nothing to
/// report back beyond the empty result.
std::string readPreparedCommitMessage(const RepoPaths& paths);

/// Design C3's overwrite guard for the working copy view's commit message
/// box (must_not_do: "不得覆蓋使用者已經打好的 commit message"): true when
/// the box should be filled with a freshly prepared message right now --
/// either it's currently empty, or it still holds exactly what was
/// auto-filled last time. False the moment the user has typed anything of
/// their own, and stays false until the box is cleared again (e.g. after a
/// successful commit) or a later auto-fill updates `lastAutofilledMessage`.
/// A pure function over plain strings (rather than a WorkingCopyView method)
/// so it's directly unit-testable with no Qt widget or RepositorySession
/// involved -- same reasoning as ConflictBatch/TextTraits living in core.
bool shouldApplyPreparedCommitMessage(const std::string& currentMessageBoxText,
                                       const std::string& lastAutofilledMessage);

}  // namespace gbm
