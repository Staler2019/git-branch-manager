#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/TransferProgress.h"

#include <filesystem>
#include <functional>
#include <string>

namespace gbm {

struct InitRepoRequest {
    std::filesystem::path path;
};

struct CloneRepoRequest {
    std::string url;
    std::filesystem::path destPath;
    /// Set by the app layer to a directory made with askpass::makeRequestDir();
    /// empty means "no credential prompt is possible", and an auth failure is
    /// reported immediately instead. Same convention as FetchRequest.
    std::filesystem::path askpassDir;
    /// DLGS' 「一併 clone submodule」: `--recurse-submodules`.
    bool recurseSubmodules = false;
    /// DLGS' 「淺層 clone（--depth 1）」: `--depth <n>` when positive; 0 is the
    /// full history. Negative is refused.
    int depth = 0;
    /// Called with each stderr chunk's latest transfer state, on the thread
    /// reading stderr -- see parseTransferProgress(). Chunks with none are
    /// not reported. May be empty.
    std::function<void(const TransferProgress&)> onProgress;
};

/// `git init <path>`. These run before any RepoPaths/Session exists -- see
/// RemoteOps.h's Operation subclasses for the ordinary case, which all
/// require an already-open repository -- so this is a plain function taking
/// IProcessRunner directly rather than an Operation. `path` is created if it
/// doesn't already exist (git init does this itself, including missing
/// parents); reinitializing an existing repository is not treated as an
/// error, matching git's own behavior.
GitResult<void> runInitRepo(IProcessRunner& runner,
                            const InitRepoRequest& request,
                            CancellationToken token);

/// `git clone [options] -- <url> <destPath>`. A network command, so it runs
/// under the idle deadline only (effectiveDeadlines()): a slow clone is not a
/// hang, and cancellation is how the user actually stops it. A url starting
/// with '-' is refused before git runs, `--` notwithstanding.
GitResult<void> runCloneRepo(IProcessRunner& runner,
                             const CloneRepoRequest& request,
                             CancellationToken token);

}  // namespace gbm
