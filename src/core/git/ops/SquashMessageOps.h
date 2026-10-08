#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"

#include <string>

namespace gbm {

/// What `git merge --squash <source>` would write to .git/SQUASH_MSG, read
/// before the squash runs so the Merge dialog can show it as the message
/// (merge-rebase-dialogs-spec.html 02-C, ruling ⑨).
///
/// The two oids are the exact commits the message was built from. The
/// message is a permanent commit message once used, and it is only right
/// while HEAD and the source still point where they did -- a caller adopts
/// it only while both still match (see the capi event's doc).
struct SquashMessagePreview {
    ObjectId headOid;
    ObjectId sourceOid;
    /// Empty when the source adds nothing to HEAD: git itself would say
    /// "Already up to date" and write no SQUASH_MSG.
    std::string message;
};

/// Read-only, like CompareStore: no Operation, because nothing mutates.
class SquashMessageStore {
public:
    SquashMessageStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<SquashMessagePreview> preview(const std::string& source, CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
