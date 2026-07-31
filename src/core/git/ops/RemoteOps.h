#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

struct RemoteInfo {
    std::string name;
    std::string fetchUrl;
    std::string pushUrl;
};

/// Reads `git remote -v`. Read-only, like RefStore.
class RemoteStore {
public:
    RemoteStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<std::vector<RemoteInfo>> list(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct FetchRequest {
    std::string remoteName;  ///< Empty fetches every remote (`--all`).
    bool prune = false;
    bool tags = false;
    /// Set by the app layer to a directory made with askpass::makeRequestDir();
    /// empty means "no credential prompt is possible", and an auth failure is
    /// reported immediately instead.
    std::filesystem::path askpassDir;
};

struct PullRequest {
    std::string remoteName;  ///< Empty uses the branch's configured upstream.
    std::string branch;
    bool rebase = false;
    /// Same idea as CheckoutRequest::stashFirst: stash local changes before
    /// pulling, offered after a DirtyWorkTree failure.
    bool stashFirst = false;
    std::filesystem::path askpassDir;
};

enum class PushForceMode : std::uint8_t {
    None,
    /// `--force-with-lease`: refuses when the remote tip is not what we last
    /// saw there, so a teammate's push in between is never silently clobbered.
    /// The only force mode this app exposes -- see README "Design decisions".
    ForceWithLease,
};

struct PushRequest {
    std::string remoteName;
    std::string branch;  ///< Empty pushes the current branch.
    bool setUpstream = false;
    bool pushTags = false;
    PushForceMode force = PushForceMode::None;
    std::filesystem::path askpassDir;
};

/// `git fetch`. Zero timeout, like every network operation here: a slow link
/// is not a hang, and cancellation is how the user actually stops it.
std::unique_ptr<Operation> makeFetchOperation(FetchRequest request);

/// `git pull` (merge or `--rebase`). A conflict leaves the same index state a
/// conflicting merge or rebase would, so it is picked up by the existing
/// ConflictOps/WorkingCopyStatus machinery rather than anything bespoke.
std::unique_ptr<Operation> makePullOperation(PullRequest request);

/// `git push`, with `--force-with-lease` when `force` asks for it. There is no
/// plain `--force` in this app: see PushForceMode.
std::unique_ptr<Operation> makePushOperation(PushRequest request);

}  // namespace gbm
