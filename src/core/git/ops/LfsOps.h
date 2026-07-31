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

/// Whether the `git-lfs` extension is on `PATH` at all. Most repositories do
/// not use LFS, so this is not itself an error condition -- callers branch on
/// `available` rather than treating a missing extension as a failure, the
/// same way GitExecutable::isUsable() is checked rather than assumed.
struct LfsInstallation {
    bool available = false;
    std::string version;  ///< Raw `git lfs version` output, e.g. "git-lfs/3.4.1 ...".
};

/// Runs `git lfs version`. A nonzero exit (git-lfs not installed, or `git`
/// itself not recognising `lfs` as a subcommand) is reported as
/// `available = false` rather than a GitResult failure -- this is a capability
/// probe, not an operation that can meaningfully fail.
GitResult<LfsInstallation> detectLfs(IProcessRunner& runner,
                                     const RepoPaths& paths,
                                     CancellationToken token);

struct LfsFileInfo {
    std::string path;
    std::string oid;                 ///< Full sha256 pointer oid.
    bool downloadedLocally = false;  ///< `*` vs `-` in `git lfs ls-files`.
};

/// Reads tracked patterns and file status; read-only, like RefStore.
class LfsStore {
public:
    LfsStore(IProcessRunner& runner, RepoPaths paths);

    /// `git lfs track` with no arguments: the patterns currently recorded in
    /// `.gitattributes` (and any nested one), one per `filter=lfs` entry.
    GitResult<std::vector<std::string>> trackedPatterns(CancellationToken token);

    /// `git lfs ls-files --long`: every path LFS is tracking in the current
    /// checkout, with its pointer oid and whether the real content has been
    /// downloaded into local LFS storage.
    GitResult<std::vector<LfsFileInfo>> listFiles(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct LfsTrackRequest {
    std::string pattern;  ///< A gitattributes pattern, e.g. "*.psd".
};

struct LfsUntrackRequest {
    std::string pattern;
};

struct LfsTransferRequest {
    std::string remoteName;  ///< Empty uses the default remote.
    std::filesystem::path askpassDir;
};

struct LfsPruneRequest {
    bool dryRun = false;
};

/// `git lfs install --local`: wires the repository's smudge/clean filters and
/// hooks. Scoped to this repository only -- never `--global` -- so it never
/// touches a user's other repositories or machine-wide config.
std::unique_ptr<Operation> makeLfsInstallOperation();

/// `git lfs track "<pattern>"`. Editing `.gitattributes` is left to the
/// caller (stage and commit it like any other working-copy change); this
/// only records the pattern.
std::unique_ptr<Operation> makeLfsTrackOperation(LfsTrackRequest request);

/// `git lfs untrack "<pattern>"`.
std::unique_ptr<Operation> makeLfsUntrackOperation(LfsUntrackRequest request);

/// `git lfs pull [<remote>]`: fetches and checks out the LFS objects the
/// current checkout's pointers reference.
std::unique_ptr<Operation> makeLfsPullOperation(LfsTransferRequest request);

/// `git lfs fetch [<remote>]`: downloads objects without touching the work tree.
std::unique_ptr<Operation> makeLfsFetchOperation(LfsTransferRequest request);

/// `git lfs prune [--dry-run]`: deletes old LFS objects from local storage
/// that are no longer needed by any local ref.
std::unique_ptr<Operation> makeLfsPruneOperation(LfsPruneRequest request);

}  // namespace gbm
