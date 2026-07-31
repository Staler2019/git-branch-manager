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

/// One commit that touched a file, from `git log --follow`.
struct FileHistoryEntry {
    ObjectId oid;
    Signature author;
    std::string subject;
    /// Raw `--name-status` code: A, M, D, or R### / C### for a rename/copy.
    std::string status;
    /// The path this file had before the commit, set only when `status` starts
    /// with R or C -- `git log --follow` keeps walking under the old name.
    std::string renamedFrom;
};

/// One commit's hunk from `git log -L`, covering a specific line range rather
/// than the whole file.
struct LineHistoryChunk {
    ObjectId oid;
    Signature author;
    std::string subject;
    /// The diff/hunk text git prints for this commit's change to the range, as
    /// it comes from git -- headers, `@@` markers and all.
    std::string diffText;
};

/// File- and line-level history: `git log --follow` and `git log -L`. Read-only,
/// like RefStore.
class FileHistoryStore {
public:
    FileHistoryStore(IProcessRunner& runner, RepoPaths paths);

    /// Commits that touched `path`, newest first, following renames across
    /// history the way `git log --follow` does. `startRevision` empty means
    /// HEAD.
    GitResult<std::vector<FileHistoryEntry>> fileHistory(const std::string& path,
                                                         const std::string& startRevision,
                                                         CancellationToken token);

    /// Commits that touched lines `startLine..endLine` (1-based, inclusive) of
    /// `path`, newest first.
    GitResult<std::vector<LineHistoryChunk>> lineHistory(const std::string& path,
                                                         int startLine,
                                                         int endLine,
                                                         const std::string& startRevision,
                                                         CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
