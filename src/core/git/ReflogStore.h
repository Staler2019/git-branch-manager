#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/CommitMeta.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <string>
#include <vector>

namespace gbm {

/// One entry from `git reflog`, e.g. what `HEAD@{N}` refers to.
struct ReflogEntry {
    int index = 0;  ///< N in `<ref>@{N}`; 0 is the most recent.
    ObjectId oid;
    std::string message;  ///< The raw reflog subject, e.g. "commit: fix typo".
    Signature who;
};

/// Reads `git reflog`. Read-only, like RefStore.
class ReflogStore {
public:
    ReflogStore(IProcessRunner& runner, RepoPaths paths);

    /// `ref` empty means HEAD.
    GitResult<std::vector<ReflogEntry>> list(const std::string& ref, CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
