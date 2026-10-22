#pragma once

#include "core/git/OperationRunner.h"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

struct CreateBranchRequest {
    std::string name;
    std::string startPoint;  ///< Empty means HEAD.
    bool checkoutAfter = false;
    bool setUpstream = false;
    std::string upstream;
};

struct RenameBranchRequest {
    std::string from;
    std::string to;
    bool force = false;
    /// Carries the rename through to `remoteName` after the local rename
    /// succeeds: pushes the branch under its new name (with `-u`, so the
    /// renamed branch tracks it), then deletes the old branch on the remote.
    /// git has no atomic remote rename, so this really is push-then-delete,
    /// and everyone else's remote-tracking ref for the old name goes `gone`.
    /// Push comes first deliberately -- reversing the two would leave the
    /// branch unpublished if the second step failed.
    ///
    /// When this is false and the branch had an upstream, the upstream is
    /// unset instead: `git branch -m` *keeps* the tracking config, which
    /// would otherwise leave the renamed branch still tracking the old
    /// remote branch. That is not configurable -- it is what "rename
    /// locally only" means.
    bool renameRemote = false;
    std::string remoteName;
    /// Set by the app layer to a directory made with askpass::makeRequestDir();
    /// only the `renameRemote` steps need it, since they are the only ones
    /// that talk to a remote.
    std::filesystem::path askpassDir;
};

/// One branch of a DeleteBranchRequest.
struct DeleteBranchEntry {
    std::string name;
    /// `-D`: deletes even when the branch is not merged. Requires an explicit
    /// user decision, because `-D` also drops the branch's own reflog.
    bool force = false;
    /// For `force` only: the tip the user was warned about
    /// (BranchDeletionProbe::tipOid). The delete refuses when the branch no
    /// longer points there (StaleBranchTip), or when this is empty
    /// (MissingBranchTip) -- a `-D` is never sent unchecked.
    std::string expectedTipOid;

    static DeleteBranchEntry plain(std::string name) { return {std::move(name), false, {}}; }

    static DeleteBranchEntry forced(std::string name, std::string expectedTipOid) {
        return {std::move(name), true, std::move(expectedTipOid)};
    }
};

struct DeleteBranchRequest {
    /// Still one operation however many entries (gbm_capi.h's one-operation
    /// rule): the unforced ones go to git in one `branch -d`, the forced ones
    /// in one `branch -D`, or all of them in one `push --delete` when
    /// `isRemote`, where `force` and the tip mean nothing.
    std::vector<DeleteBranchEntry> entries;
    bool isRemote = false;
    std::string remoteName;
};

/// What deleting one local branch would lose, read *before* the user confirms
/// (spec page 06: 「複述分支名與未合併的 commit 數」).
///
/// The base is the branch's own upstream and nothing else (使用者裁示
/// 2026-10-21): with one set, `rev-list --count <tip> ^<upstream>`, which is
/// also the base `git branch -d` uses -- so a zero count is safe to send as
/// `-d`. With none, or a gone one, there is no count at all (`NoReference`);
/// git's `-d` would fall back to HEAD there, so the dialog sends `-D` after a
/// notice instead.
///
/// `tipOid` is the commit the count was taken against. The dialog sends it
/// back with a `-D`, and the delete refuses if the branch has moved since, so
/// the number the user read and the commits removed are the same set.
struct BranchDeletionProbe {
    enum class State { NotFound, NoReference, Counted };

    std::string name;
    State state = State::NotFound;
    std::string tipOid;    ///< Empty only for NotFound.
    std::string upstream;  ///< Full ref; set for Counted only.
    int unsyncedCount = 0;

    static BranchDeletionProbe notFound(std::string name);
    static BranchDeletionProbe noReference(std::string name, std::string tipOid);
    static BranchDeletionProbe counted(std::string name,
                                       std::string tipOid,
                                       std::string upstream,
                                       int unsyncedCount);
};

/// Read-only branch queries, like RemoteStore.
class BranchStore {
public:
    BranchStore(IProcessRunner& runner, RepoPaths paths);

    /// One answer per requested name, in request order. A failed read fails
    /// the whole probe: it is neither "nothing to warn about" nor "no
    /// upstream", and the dialog must not guess between them.
    GitResult<std::vector<BranchDeletionProbe>> probeDeletion(std::vector<std::string> names,
                                                              CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

std::unique_ptr<Operation> makeCreateBranchOperation(CreateBranchRequest request);
std::unique_ptr<Operation> makeRenameBranchOperation(RenameBranchRequest request);
std::unique_ptr<Operation> makeDeleteBranchOperation(DeleteBranchRequest request);

}  // namespace gbm
