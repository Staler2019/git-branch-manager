#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"

#include <filesystem>
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

/// `git clone <url> <destPath>`. Zero timeout, like every network operation
/// in this app (see RemoteOps.h's FetchOperation): a slow clone is not a
/// hang, and cancellation is how the user actually stops it. Per-object
/// transfer progress is not parsed from stderr -- same scope cut this app
/// already makes for fetch/pull/push -- so this reports only success or
/// failure, not a running byte/object count.
GitResult<void> runCloneRepo(IProcessRunner& runner,
                             const CloneRepoRequest& request,
                             CancellationToken token);

}  // namespace gbm
