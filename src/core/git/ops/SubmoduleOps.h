#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

struct SubmoduleInfo {
    std::string name;  ///< The `.gitmodules` section name; usually equal to `path`.
    std::string path;
    std::string url;
    std::string branch;  ///< `submodule.<name>.branch`, if configured; empty otherwise.
    std::string headOid;  ///< The commit currently recorded, from `git submodule status`.

    enum class State {
        /// Listed in `.gitmodules` but never `git submodule init`-ed / cloned.
        NotInitialized,
        /// Checked-out commit matches what the superproject's index records.
        UpToDate,
        /// Checked-out commit differs from the index (`+` in `git submodule status`).
        Modified,
        /// Merge conflict in the submodule's recorded commit (`U`).
        Conflicted,
    };
    State state = State::UpToDate;
};

/// Reads `.gitmodules` plus `git submodule status`, read-only like RefStore.
class SubmoduleStore {
public:
    SubmoduleStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<std::vector<SubmoduleInfo>> list(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct AddSubmoduleRequest {
    std::string url;
    std::string path;  ///< Empty lets git derive it from the URL, same as the CLI.
    std::string branch;
    std::filesystem::path askpassDir;
};

/// One or more submodule paths; empty means "every submodule", matching the
/// bare `git submodule <verb>` with no pathspec.
struct SubmodulePathsRequest {
    std::vector<std::string> paths;
    bool recursive = false;
};

struct UpdateSubmodulesRequest {
    std::vector<std::string> paths;
    bool recursive = false;
    bool init = false;  ///< `--init`: also initialise submodules never checked out.
    /// `--remote`: update to the remote-tracking branch tip instead of the
    /// commit recorded in the superproject's index.
    bool remote = false;
    std::filesystem::path askpassDir;
};

struct DeinitSubmodulesRequest {
    std::vector<std::string> paths;
    /// `--force`: discards local modifications inside the submodule's work tree.
    /// Only ever set after the user has already been told what that means,
    /// same contract as every other `force` in this codebase.
    bool force = false;
};

/// `git submodule add [-b <branch>] <url> [<path>]`.
std::unique_ptr<Operation> makeAddSubmoduleOperation(AddSubmoduleRequest request);

/// `git submodule init [--] <paths...>`. Copies the recorded URL into local
/// config; does not clone anything by itself.
std::unique_ptr<Operation> makeInitSubmodulesOperation(SubmodulePathsRequest request);

/// `git submodule update [--init] [--recursive] [--remote] [--] <paths...>`.
std::unique_ptr<Operation> makeUpdateSubmodulesOperation(UpdateSubmodulesRequest request);

/// `git submodule sync [--recursive] [--] <paths...>`: re-copies the URL from
/// `.gitmodules` into local config, for when it changed upstream.
std::unique_ptr<Operation> makeSyncSubmodulesOperation(SubmodulePathsRequest request);

/// `git submodule deinit [-f] [--] <paths...>`: empties the submodule's work
/// tree and removes its local config, leaving `.gitmodules` untouched.
std::unique_ptr<Operation> makeDeinitSubmodulesOperation(DeinitSubmodulesRequest request);

}  // namespace gbm
