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

}  // namespace gbm
