#include "capi/CloneJob.h"

#include "capi/JsonCodec.h"
#include "capi/JsonWriter.h"
#include "capi/Session.h"
#include "capi/StagingBuffer.h"
#include "core/git/AskpassHelper.h"
#include "core/git/IProcessRunner.h"
#include "core/git/ops/InitCloneOps.h"

#include <atomic>
#include <cstdlib>
#include <mutex>
#include <system_error>
#include <unordered_map>
#include <utility>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {

// The job the calling thread runs a clone for, or 0: set for the life of a
// job's own thread by CloneJobScope, read by CloneJob::dispatchLogRecord().
// Like currentQueuedOperationId(), work handed to another thread sees 0 --
// and every git invocation of a clone runs on the job's thread.
thread_local std::uint64_t tCurrentCloneJob = 0;

class CloneJobScope {
public:
    explicit CloneJobScope(std::uint64_t id) { tCurrentCloneJob = id; }

    ~CloneJobScope() { tCurrentCloneJob = 0; }

    CloneJobScope(const CloneJobScope&) = delete;
    CloneJobScope& operator=(const CloneJobScope&) = delete;
    CloneJobScope(CloneJobScope&&) = delete;
    CloneJobScope& operator=(CloneJobScope&&) = delete;
};

std::atomic<std::uint64_t> gNextCloneJobId{1};

// Live jobs by id. A job leaves it only after its thread has been joined, so
// a lookup from that thread always finds it; the mutex is for the other jobs'
// threads registering and leaving at the same time.
std::mutex& registryMutex() {
    static std::mutex mutex;
    return mutex;
}

std::unordered_map<std::uint64_t, CloneJob*>& registry() {
    static std::unordered_map<std::uint64_t, CloneJob*> jobs;
    return jobs;
}

std::optional<std::filesystem::path> homeDirectory() {
#ifdef _WIN32
    const char* home = std::getenv("USERPROFILE");
#else
    const char* home = std::getenv("HOME");
#endif
    if (home == nullptr || *home == '\0') {
        return std::nullopt;
    }
    return fsutil::pathFromUtf8(home);
}

/// `/a/b/` and `/a/b` name the same directory; lexically_normal() keeps the
/// trailing separator as an empty last component, so drop it.
std::filesystem::path normalised(const std::filesystem::path& path) {
    std::filesystem::path out = path.lexically_normal();
    if (!out.has_filename() && out != out.root_path()) {
        out = out.parent_path();
    }
    return out;
}

GitResult<std::filesystem::path> validDestination(const std::filesystem::path& dest) {
    if (dest.empty()) {
        return fail(GitError::Code::InvalidArgument, "A destination path is required");
    }
    if (!dest.is_absolute()) {
        return fail(GitError::Code::InvalidArgument, "The destination must be an absolute path");
    }
    for (const std::filesystem::path& part : dest) {
        if (part == "..") {
            return fail(GitError::Code::InvalidArgument, "The destination cannot contain '..'");
        }
    }
    std::filesystem::path out = normalised(dest);
    if (out == out.root_path()) {
        return fail(GitError::Code::InvalidArgument, "The destination cannot be a root directory");
    }
    if (const std::optional<std::filesystem::path> home = homeDirectory();
        home && normalised(*home) == out) {
        return fail(GitError::Code::InvalidArgument,
                    "The destination cannot be the home directory");
    }
    return out;
}

const char* phaseName(TransferProgress::Phase phase) {
    switch (phase) {
        case TransferProgress::Phase::ReceivingObjects:
            return "receiving";
        case TransferProgress::Phase::ResolvingDeltas:
            return "resolving";
    }
    return "receiving";
}

void appendOptionalString(std::string& out, const std::optional<std::string>& value) {
    if (value) {
        jsonAppendEscaped(out, *value);
    } else {
        out += "null";
    }
}

}  // namespace

namespace gbm::capi {

std::unique_ptr<CloneJob> CloneJob::start(CloneJobRequest request,
                                          GbmEventCallback callback,
                                          void* userData,
                                          GitError* outError) {
    auto refuse = [outError](GitError error) -> std::unique_ptr<CloneJob> {
        if (outError != nullptr) {
            *outError = std::move(error);
        }
        return nullptr;
    };
    if (callback == nullptr) {
        return refuse(GitError(GitError::Code::InvalidArgument, "A callback is required"));
    }
    if (request.url.empty()) {
        return refuse(GitError(GitError::Code::InvalidArgument, "A repository URL is required"));
    }
    if (request.url.front() == '-') {
        return refuse(
            GitError(GitError::Code::InvalidArgument, "A repository URL cannot start with '-'"));
    }
    if (request.depth < 0) {
        return refuse(
            GitError(GitError::Code::InvalidArgument, "A clone depth cannot be negative"));
    }
    GitResult<std::filesystem::path> dest = validDestination(request.destPath);
    if (!dest) {
        return refuse(dest.error());
    }
    request.destPath = dest.value();

    const GitResult<GitInstallation> installation = sharedGitInstallation();
    if (!installation) {
        return refuse(installation.error());
    }
    ensureOperationLogSinkInstalled();

    const std::uint64_t id = gNextCloneJobId.fetch_add(1);
    std::unique_ptr<CloneJob> job(
        new CloneJob(id, std::move(request), installation.value(), callback, userData));

    job->destination_ = CloneDestination::claim(job->request_.destPath);

    {
        std::lock_guard<std::mutex> lock(registryMutex());
        registry().emplace(id, job.get());
    }
    CloneJob* raw = job.get();
    job->thread_ = std::thread([raw] { raw->run(); });
    return job;
}

CloneJob::CloneJob(std::uint64_t id,
                   CloneJobRequest request,
                   GitInstallation installation,
                   GbmEventCallback callback,
                   void* userData)
    : id_(id), request_(std::move(request)), installation_(std::move(installation)) {
    callbacks_.set(static_cast<GbmSessionHandle>(this), callback, userData);
}

CloneJob::~CloneJob() {
    cancel_.cancel();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard<std::mutex> lock(registryMutex());
    registry().erase(id_);
}

void CloneJob::cancel() {
    cancel_.cancel();
}

void CloneJob::provideCredential(const std::string& secret) {
    askpass_.answer(secret);
}

void CloneJob::cancelCredential() {
    askpass_.cancelPrompt();
}

bool CloneJob::dispatchLogRecord(const OperationRecord& record) {
    const std::uint64_t id = tCurrentCloneJob;
    if (id == 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(registryMutex());
    const auto it = registry().find(id);
    if (it != registry().end()) {
        it->second->callbacks_.emit(GBM_EVENT_OPERATION_LOG_RECORD, toJson(record));
    }
    return true;
}

void CloneJob::run() {
    const CloneJobScope scope(id_);
    const std::unique_ptr<IProcessRunner> runner = makeProcessRunner(installation_.executable);

    const std::filesystem::path askpassDir = askpass::makeRequestDir();
    askpass_.start(askpassDir, [this](std::string prompt) {
        std::string payload = "{\"prompt\":";
        jsonAppendEscaped(payload, prompt);
        payload += '}';
        callbacks_.emit(GBM_EVENT_CREDENTIAL_REQUESTED, payload);
    });

    CloneRepoRequest request;
    request.url = request_.url;
    request.destPath = request_.destPath;
    request.askpassDir = askpassDir;
    request.recurseSubmodules = request_.recurseSubmodules;
    request.depth = request_.depth;
    request.onProgress = [this](const TransferProgress& progress) {
        std::string payload = "{\"phase\":\"";
        payload += phaseName(progress.phase);
        payload += "\",\"current\":";
        jsonAppendInt(payload, static_cast<std::int64_t>(progress.current));
        payload += ",\"total\":";
        jsonAppendInt(payload, static_cast<std::int64_t>(progress.total));
        payload += '}';
        callbacks_.emit(GBM_EVENT_CLONE_PROGRESS, payload);
    };

    const GitResult<void> result = runCloneRepo(*runner, request, cancel_.token());
    askpass_.stop();
    emitFinished(result);
}

void CloneJob::emitFinished(const GitResult<void>& result) {
    CloneDestination::Removal cleanup;
    // Only a cancel removes anything: the child has been reaped by now, so
    // nothing is still writing there. A failure is left to git's own cleanup.
    if (!result && result.error().code == GitError::Code::Cancelled) {
        cleanup = destination_.removeUnfinished();
    }
    std::string payload = "{\"ok\":";
    jsonAppendBool(payload, static_cast<bool>(result));
    payload += ",\"error\":";
    payload += result ? std::string("null") : toJson(result.error());
    payload += ",\"removedPath\":";
    appendOptionalString(
        payload,
        cleanup.removedPath ? std::optional<std::string>(fsutil::utf8FromPath(*cleanup.removedPath))
                            : std::nullopt);
    payload += ",\"removalError\":";
    appendOptionalString(payload, cleanup.error);
    payload += '}';
    callbacks_.emit(GBM_EVENT_CLONE_FINISHED, payload);
}

CloneDestination CloneDestination::claim(std::filesystem::path path) {
    CloneDestination out;
    std::error_code ec;
    const std::filesystem::file_status status = std::filesystem::symlink_status(path, ec);
    if (!std::filesystem::exists(status)) {
        out.owned_ = true;
    } else if (std::filesystem::is_directory(status) && std::filesystem::is_empty(path, ec) &&
               !ec) {
        out.owned_ = true;
        out.preexisted_ = true;
        out.dirId_ = fsutil::fileIdOf(path);
    }
    out.parentId_ = fsutil::resolvedDirId(path.parent_path());
    out.path_ = std::move(path);
    return out;
}

CloneDestination::Removal CloneDestination::removeUnfinished() const {
    if (!owned_) {
        return {};
    }
    const std::string shown = fsutil::utf8FromPath(path_);
    std::error_code ec;
    const std::filesystem::file_status status = std::filesystem::symlink_status(path_, ec);
    if (!std::filesystem::exists(status)) {
        return {path_, std::nullopt};
    }
    // Every check below refuses rather than guesses: what is there now must
    // still be the directory claim() decided was ours.
    if (!std::filesystem::is_directory(status)) {
        return {std::nullopt, shown + " is no longer a directory; it was left as it is"};
    }
    if (parentId_ != fsutil::resolvedDirId(path_.parent_path())) {
        return {std::nullopt, "The folder holding " + shown + " changed; it was left as it is"};
    }
    if (preexisted_ && fsutil::fileIdOf(path_) != dirId_) {
        return {std::nullopt, shown + " was replaced; it was left as it is"};
    }

    // remove_all() removes a symlink or junction itself, never what it
    // points at.
    std::error_code removeError;
    if (preexisted_) {
        std::vector<std::filesystem::path> entries;
        for (std::filesystem::directory_iterator it(path_, ec), end; !ec && it != end;
             it.increment(ec)) {
            entries.push_back(it->path());
        }
        for (const std::filesystem::path& entry : entries) {
            std::error_code one;
            std::filesystem::remove_all(entry, one);
            if (one && !removeError) {
                removeError = one;
            }
        }
        if (ec && !removeError) {
            removeError = ec;
        }
    } else {
        std::filesystem::remove_all(path_, removeError);
    }

    std::error_code checkError;
    const bool clean =
        preexisted_ ? std::filesystem::is_empty(path_, checkError) && !checkError
                    : !std::filesystem::exists(std::filesystem::symlink_status(path_, checkError));
    if (clean) {
        return {path_, std::nullopt};
    }
    std::string message = "Could not remove everything in " + shown;
    if (removeError) {
        message += ": " + removeError.message();
    }
    return {std::nullopt, message};
}

}  // namespace gbm::capi

GBM_API GbmCloneHandle gbm_clone_start(const char* url,
                                       const char* destPath,
                                       int32_t recurseSubmodules,
                                       int32_t depth,
                                       GbmEventCallback callback,
                                       void* userData) {
    CloneJobRequest request;
    request.url = url != nullptr ? url : "";
    request.destPath = fsutil::pathFromUtf8(destPath != nullptr ? destPath : "");
    request.recurseSubmodules = recurseSubmodules != 0;
    request.depth = depth;
    GitError error;
    std::unique_ptr<CloneJob> job = CloneJob::start(std::move(request), callback, userData, &error);
    if (!job) {
        setStagingBuffer(toJson(error));
        return nullptr;
    }
    return static_cast<GbmCloneHandle>(job.release());
}

GBM_API void gbm_clone_cancel(GbmCloneHandle job) {
    if (job != nullptr) {
        static_cast<CloneJob*>(job)->cancel();
    }
}

GBM_API void gbm_clone_provide_credential(GbmCloneHandle job, const char* secret) {
    if (job != nullptr) {
        static_cast<CloneJob*>(job)->provideCredential(secret != nullptr ? secret : "");
    }
}

GBM_API void gbm_clone_cancel_credential(GbmCloneHandle job) {
    if (job != nullptr) {
        static_cast<CloneJob*>(job)->cancelCredential();
    }
}

GBM_API void gbm_clone_close(GbmCloneHandle job) {
    delete static_cast<CloneJob*>(job);
}
