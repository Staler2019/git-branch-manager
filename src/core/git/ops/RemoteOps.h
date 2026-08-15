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

/// One remote-tracking ref a real prune would remove. `ref` is the short
/// name (e.g. "origin/feature/old-branch") -- what `git branch -d -r`
/// accepts, and what PruneRemoteRequest::refs below expects back.
struct RemotePrunePreviewEntry {
    std::string ref;
};

/// Reads `git remote -v`. Read-only, like RefStore.
class RemoteStore {
public:
    RemoteStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<std::vector<RemoteInfo>> list(CancellationToken token);

    /// `git remote prune <remote> --dry-run`: what a real prune would
    /// remove, without removing anything. The Prune dialog shows this list
    /// and lets the user deselect entries before the real prune runs -- see
    /// makePruneRemoteOperation() below for why that means the write side
    /// takes an explicit ref list rather than "prune everything stale".
    GitResult<std::vector<RemotePrunePreviewEntry>> prunePreview(std::string remoteName,
                                                                  CancellationToken token);

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

struct PruneRemoteRequest {
    std::string remoteName;         ///< Used only for describe(); refs already carry it.
    std::vector<std::string> refs;  ///< Exact set to delete -- see RemotePrunePreviewEntry.
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

/// Deletes exactly the remote-tracking refs in `request.refs` (typically a
/// user-edited subset of a prior RemoteStore::prunePreview()) via
/// `git branch --delete --remotes`, not `git remote prune`: the plain
/// command has no "delete only these" mode, so a dialog that lets the user
/// deselect entries first can't be built on top of it.
std::unique_ptr<Operation> makePruneRemoteOperation(PruneRemoteRequest request);

}  // namespace gbm
