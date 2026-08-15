#pragma once

#include "core/git/RepoPaths.h"

#include <string>

namespace gbm {

/// Reads the original/proposed commit message for an in-progress rebase or
/// cherry-pick conflict, so the conflict resolution window's Continue step
/// (M6 commit 9) can show it as an editable pre-fill instead of relying on
/// git's own silent preserve-on-`--continue` behavior.
///
/// Verified empirically against real git (a throwaway repo driven into each
/// conflict state, `.git` inspected directly -- not assumed from docs):
/// during a conflicted merge, cherry-pick, or revert, git writes the full
/// proposed message -- subject, body, and a trailing "# Conflicts:" listing
/// -- into MERGE_MSG. CHERRY_PICK_HEAD and REVERT_HEAD hold only the
/// 40-char OID of the commit being picked/reverted, never message text, so
/// they are not read here. During a conflicted rebase, git additionally
/// mirrors the same content into rebase-merge/message; that file is checked
/// first since it's the more specific source, with MERGE_MSG as fallback.
///
/// `#`-prefixed comment lines are preserved verbatim -- stripping them is a
/// UI rendering concern (the conflict window renders them in a distinct
/// color), not a read concern. Returns an empty string when no operation is
/// in progress or git prepared no message at all, mirroring
/// readPreparedCommitMessage's not-an-error convention for the same case.
std::string readOriginalOperationMessage(const RepoPaths& paths);

/// Overwrites the message file git reads when `cherry-pick --continue` next
/// runs, so the caller's edited text -- not git's own proposal -- becomes
/// the resulting commit's message. The write side of
/// readOriginalOperationMessage() above, backing M6 commit 9's editable
/// Continue step. Verified empirically: a conflicted cherry-pick (and
/// revert) reads MERGE_MSG specifically at continue time.
void writeCherryPickContinueMessage(const RepoPaths& paths, const std::string& message);

/// Same idea, but for a conflicted rebase: verified empirically that
/// `rebase --continue` reads rebase-merge/message, not MERGE_MSG -- writing
/// only the latter does not change the resulting commit's message. Pair
/// this with GIT_EDITOR=true on the continue command itself (already set by
/// RebaseControlOperation) so git accepts the seeded file without prompting
/// for an edit.
void writeRebaseContinueMessage(const RepoPaths& paths, const std::string& message);

}  // namespace gbm
