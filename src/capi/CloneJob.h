#pragma once

// A `git clone` that needs no open repository: the welcome screen has no
// Session, and P15/DLGS still ask for a clone that shows progress, can be
// cancelled and logs like any other git operation. One CloneJob is one clone,
// run on its own thread, with its own askpass poller and its own callback --
// the session-less counterpart of what Session does for fetch/pull/push.
//
// Its operation-log records reach it through Session's process-wide sink:
// the job's thread is marked with the job's id (CloneJobScope, like
// QueuedOperationScope), and dispatchCloneJobLogRecord() routes every record
// taken on that thread to this job alone.

#include "capi/AskpassPoller.h"
#include "capi/CallbackRegistry.h"
#include "capi/gbm_capi.h"
#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/FsUtil.h"
#include "core/base/Logging.h"
#include "core/git/GitExecutable.h"

#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <thread>

namespace gbm::capi {

struct CloneJobRequest {
    std::string url;
    std::filesystem::path destPath;
    bool recurseSubmodules = false;
    int depth = 0;
};

/// The clone's claim on its destination, decided before git runs, and the
/// removal it allows after a cancel. A value of its own so the removal can be
/// tested directly: on POSIX git's SIGTERM handler empties or removes the
/// destination itself, by path, before the job's cleanup ever looks.
class CloneDestination {
public:
    struct Removal {
        /// Set when nothing of the clone is left at the destination.
        std::optional<std::filesystem::path> removedPath;
        /// Set when the removal refused or stopped short, saying why.
        std::optional<std::string> error;
    };

    /// Ours when `path` (already validated and normalised) does not exist,
    /// or is a real -- not linked -- empty directory, right now.
    static CloneDestination claim(std::filesystem::path path);

    bool owned() const { return owned_; }

    const std::filesystem::path& path() const { return path_; }

    /// Removes what the clone left: the whole destination, or -- when it was
    /// an existing empty directory -- everything inside it. Refuses, leaving
    /// everything as it is, unless what is there is still the directory
    /// claim() looked at under the same parent -- a parent that did not exist
    /// at claim() counts as changed. Never follows a link.
    Removal removeUnfinished() const;

private:
    std::filesystem::path path_;
    bool owned_ = false;
    bool preexisted_ = false;
    std::optional<fsutil::FileId> dirId_;
    std::optional<fsutil::FileId> parentId_;
};

class CloneJob {
public:
    /// Validates `request`, decides whether the destination is ours to delete
    /// on cancel, and starts the clone. Returns null with `outError` set when
    /// it refuses before git runs: no usable git, an empty or '-'-led url, a
    /// negative depth, a null callback, or a destination that is not an
    /// absolute path, contains `..`, or is a root or the home directory.
    ///
    /// The destination is ours only when it did not exist, or was an empty
    /// directory, right now. git is handed the same normalised path the
    /// cleanup checks.
    static std::unique_ptr<CloneJob> start(CloneJobRequest request,
                                           GbmEventCallback callback,
                                           void* userData,
                                           GitError* outError);

    /// Cancels, joins the job's thread, then unregisters: once this returns,
    /// nothing emits through the callback again.
    ~CloneJob();

    CloneJob(const CloneJob&) = delete;
    CloneJob& operator=(const CloneJob&) = delete;
    CloneJob(CloneJob&&) = delete;
    CloneJob& operator=(CloneJob&&) = delete;

    /// Stops the clone. GBM_EVENT_CLONE_FINISHED still fires, with a
    /// Cancelled error and, when the destination was ours, the cleanup result.
    void cancel();

    void provideCredential(const std::string& secret);
    void cancelCredential();

    /// Routes `record` to the clone job running on the calling thread, if
    /// any. True means the record belonged to a clone job -- delivered, or
    /// dropped because that job is already gone -- and must not also reach a
    /// Session: the routing is exclusive.
    static bool dispatchLogRecord(const OperationRecord& record);

private:
    CloneJob(std::uint64_t id,
             CloneJobRequest request,
             GitInstallation installation,
             GbmEventCallback callback,
             void* userData);

    void run();
    void emitFinished(const GitResult<void>& result);

    const std::uint64_t id_;
    const CloneJobRequest request_;
    const GitInstallation installation_;
    CloneDestination destination_;  // Claimed in start(), before git runs.

    CallbackRegistry callbacks_;
    CancellationSource cancel_;
    AskpassPoller askpass_;
    std::thread thread_;
};

}  // namespace gbm::capi
