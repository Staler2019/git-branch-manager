#pragma once

#include "core/git/OperationRunner.h"

#include <memory>
#include <string>
#include <vector>

namespace gbm {

enum class ResetMode { Soft, Mixed, Hard };

struct ResetRequest {
    std::string target;  ///< Ref or oid to reset to. Empty means HEAD.
    ResetMode mode = ResetMode::Mixed;
};

/// `git reset --soft|--mixed|--hard <target>`. Hard also overwrites the work
/// tree, discarding uncommitted changes exactly like ForceDiscard elsewhere --
/// the caller must already have the user's consent before setting Hard, the
/// same contract DeleteBranchRequest::force uses.
std::unique_ptr<Operation> makeResetOperation(ResetRequest request);

struct RestoreRequest {
    std::vector<std::string> paths;  ///< Must not be empty.
    /// True: `--staged`, resetting the index from `source` (default HEAD)
    /// without touching the work tree -- "unstage". False: the work tree is
    /// overwritten from `source` (default the index) -- "discard changes",
    /// and is destructive exactly like a hard reset of just these paths.
    bool staged = false;
    std::string source;  ///< Optional `--source=<tree-ish>`; empty means the default above.
};

/// `git restore`.
std::unique_ptr<Operation> makeRestoreOperation(RestoreRequest request);

struct CleanEntry {
    std::string path;
    bool isDirectory = false;
};

/// Read-only `git clean -n`, so the UI can show exactly what would be removed
/// before the user commits to it -- a destructive clean never runs unseen.
class CleanPreviewer {
public:
    CleanPreviewer(IProcessRunner& runner, RepoPaths paths);

    GitResult<std::vector<CleanEntry>> preview(bool includeIgnored, CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct CleanRequest {
    /// Empty means the whole work tree; otherwise exactly these paths (what the
    /// user left checked after reviewing CleanPreviewer::preview).
    std::vector<std::string> paths;
    bool includeIgnored = false;  ///< `-x`: also remove files normally ignored.
};

/// `git clean -fd`.
std::unique_ptr<Operation> makeCleanOperation(CleanRequest request);

}  // namespace gbm
