// Integration tests for the clone job (gbm_clone_*): a clone with no open
// session, run on its own thread, reporting through its own callback.
//
// A clone that stays in flight long enough to cancel, or that asks for a
// credential, is made by pointing GIT_SSH_COMMAND at a shell script and
// cloning an ssh:// url: git creates the destination, then waits on the
// "ssh" child for as long as the script runs. GIT_SSH_VARIANT=ssh stops git
// probing the command with `-G` first, which would run the script twice.
// The process environment is safe to change here: ctest runs every test in
// its own process (gtest_discover_tests).
#include "capi/CloneJob.h"
#include "capi/JsonWriter.h"
#include "capi/gbm_capi.h"
#include "core/base/FsUtil.h"
#include "support/DirLink.h"
#include "support/GitCli.h"

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <gtest/gtest.h>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;
using Events = std::vector<std::pair<int32_t, std::string>>;

std::string lastResultJson() {
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()),
                              static_cast<int32_t>(json.size()));
    return json;
}

void setEnv(const char* name, const std::string& value) {
#ifdef _WIN32
    _putenv_s(name, value.c_str());
#else
    setenv(name, value.c_str(), 1);
#endif
}

void unsetEnv(const char* name) {
#ifdef _WIN32
    _putenv_s(name, "");
#else
    unsetenv(name);
#endif
}

struct EventLog {
    std::mutex mutex;
    std::condition_variable cv;
    Events events;

    void add(int32_t eventType, std::string payload) {
        std::lock_guard<std::mutex> lock(mutex);
        events.emplace_back(eventType, std::move(payload));
        cv.notify_all();
    }

    bool waitFor(const std::function<bool(const Events&)>& pred,
                 std::chrono::milliseconds timeout = std::chrono::seconds(30)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return pred(events); });
    }

    Events snapshot() {
        std::lock_guard<std::mutex> lock(mutex);
        return events;
    }

    std::vector<std::string> payloadsOf(int32_t type) {
        std::vector<std::string> out;
        for (const auto& [eventType, payload] : snapshot()) {
            if (eventType == type) out.push_back(payload);
        }
        return out;
    }

    bool waitForFinished() {
        return waitFor([](const Events& seen) {
            for (const auto& [type, payload] : seen) {
                if (type == GBM_EVENT_CLONE_FINISHED) return true;
            }
            return false;
        });
    }

    std::string finished() {
        const std::vector<std::string> all = payloadsOf(GBM_EVENT_CLONE_FINISHED);
        return all.empty() ? std::string() : all.back();
    }
};

void logCallback(GbmSessionHandle,
                 int32_t eventType,
                 const uint8_t* payload,
                 int32_t payloadLen,
                 void* userData) {
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    static_cast<EventLog*>(userData)->add(eventType, std::move(body));
}

std::string jsonString(const std::string& value) {
    std::string out;
    jsonAppendEscaped(out, value);
    return out;
}

bool contains(const std::string& haystack, const std::string& needle) {
    return haystack.find(needle) != std::string::npos;
}

/// Closes a job on every way out of a test, an ASSERT's early return
/// included: a job left running would emit into an EventLog already gone.
class JobGuard {
public:
    explicit JobGuard(GbmCloneHandle job) : job_(job) {}

    ~JobGuard() { close(); }

    JobGuard(const JobGuard&) = delete;
    JobGuard& operator=(const JobGuard&) = delete;

    GbmCloneHandle get() const { return job_; }

    void close() {
        gbm_clone_close(job_);
        job_ = nullptr;
    }

private:
    GbmCloneHandle job_;
};

class CloneJobApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        base_ = std::filesystem::weakly_canonical(std::filesystem::temp_directory_path()) /
                ("gbm-capi-clonejob-" + std::string(info->name()));
        std::filesystem::remove_all(base_);
        std::filesystem::create_directories(base_);
    }

    void TearDown() override {
        unsetEnv("GIT_SSH_COMMAND");
        unsetEnv("GIT_SSH_VARIANT");
        std::error_code ec;
        std::filesystem::remove_all(base_, ec);
    }

    /// A bare repo with one commit on main, reached through file:// so git
    /// runs a real transport (and prints its transfer meter) rather than the
    /// local hard-link shortcut a plain path takes.
    std::string makeBareOriginUrl() {
        const std::filesystem::path origin = base_ / "origin.git";
        const std::filesystem::path scratch = base_ / "origin-scratch";
        std::filesystem::create_directories(scratch);
        auto run = [](const std::filesystem::path& dir, std::vector<std::string> args) {
            ASSERT_EQ(GitCli::run(dir, std::move(args)), 0);
        };
        run(base_, {"init", "--quiet", "--bare", "--initial-branch=main", origin.string()});
        run(scratch, {"init", "--quiet", "--initial-branch=main"});
        run(scratch, {"config", "user.email", "test@example.com"});
        run(scratch, {"config", "user.name", "Test"});
        {
            std::ofstream file(scratch / "README.md");
            file << "hello\n";
        }
        run(scratch, {"add", "README.md"});
        run(scratch, {"commit", "--quiet", "-m", "initial"});
        run(scratch, {"push", "--quiet", origin.string(), "main"});
        return "file://" + origin.generic_string();
    }

    /// Makes every ssh:// clone from here on run `script` as its ssh child.
    void useSshScript(const std::string& body) {
        const std::filesystem::path script = base_ / "fake-ssh.sh";
        {
            std::ofstream file(script, std::ios::binary);
            file << body;
        }
        setEnv("GIT_SSH_COMMAND", "sh '" + script.generic_string() + "'");
        setEnv("GIT_SSH_VARIANT", "ssh");
    }

    /// An ssh child that never answers: the clone stays in flight. It waits
    /// for this test's directory to go (TearDown), at most 60 s, rather than
    /// for git: killing git does not kill it on POSIX (ProcessRunner signals
    /// the child it spawned, not that child's own children), and `$PPID` is
    /// not git's pid under Git for Windows' sh, so `kill -0 $PPID` cannot
    /// stand in for "git is alive" there.
    std::string waitWhileTestRuns() const {
        return "i=0\nwhile [ -d '" + base_.generic_string() +
               "' ] && [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done\n";
    }

    void useHangingSsh() { useSshScript(waitWhileTestRuns()); }

    GbmCloneHandle start(const std::string& url,
                         const std::filesystem::path& dest,
                         EventLog& log,
                         int32_t recurse = 0,
                         int32_t depth = 0) {
        return gbm_clone_start(
            url.c_str(), fsutil::utf8FromPath(dest).c_str(), recurse, depth, &logCallback, &log);
    }

    static bool waitUntil(const std::function<bool()>& pred,
                          std::chrono::milliseconds timeout = std::chrono::seconds(30)) {
        const auto deadline = std::chrono::steady_clock::now() + timeout;
        while (std::chrono::steady_clock::now() < deadline) {
            if (pred()) return true;
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
        return pred();
    }

    std::filesystem::path base_;
};

TEST_F(CloneJobApiTest, ClonesARepositoryAndFinishesOk) {
    const std::string url = makeBareOriginUrl();
    const std::filesystem::path dest = base_ / "cloned";
    EventLog log;

    GbmCloneHandle job = start(url, dest, log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    EXPECT_TRUE(contains(log.finished(), "\"ok\":true")) << log.finished();
    EXPECT_TRUE(std::filesystem::exists(dest / "README.md"));
    EXPECT_EQ(log.payloadsOf(GBM_EVENT_CLONE_FINISHED).size(), 1u);
}

// Verifier A2: Dart opened the destination as typed, while git cloned into
// the normalised path -- `<base>/cloned/` opened a different identity from
// `<base>/cloned`. The finished event names the path git actually used.
TEST_F(CloneJobApiTest, TheFinishedEventNamesTheNormalisedDestination) {
    const std::string url = makeBareOriginUrl();
    const std::filesystem::path dest = base_ / "cloned";
    const std::string spelled = fsutil::utf8FromPath(base_) + "/./cloned/";
    EventLog log;

    GbmCloneHandle job = gbm_clone_start(url.c_str(), spelled.c_str(), 0, 0, &logCallback, &log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    EXPECT_TRUE(contains(log.finished(), "\"ok\":true")) << log.finished();
    EXPECT_TRUE(contains(log.finished(), "\"destPath\":" + jsonString(fsutil::utf8FromPath(dest))))
        << log.finished();
}

// R10 opens the clone straight away, so what the job leaves behind must be
// a repository an ordinary session opens. Moved here from InitCloneApiTest
// when gbm_repo_clone was deleted.
TEST_F(CloneJobApiTest, ANewlyClonedRepositoryOpensANormalSession) {
    const std::filesystem::path dest = base_ / "cloned";
    EventLog log;

    GbmCloneHandle job = start(makeBareOriginUrl(), dest, log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    GbmSessionHandle session =
        gbm_session_open(dest.string().c_str(), (dest / ".git").string().c_str(), nullptr);
    ASSERT_NE(session, nullptr);
    gbm_session_close(session);
}

TEST_F(CloneJobApiTest, ItsGitInvocationIsLoggedToTheJob) {
    // Running and outcome, the pair every invocation is recorded as.
    const std::string url = makeBareOriginUrl();
    EventLog log;

    GbmCloneHandle job = start(url, base_ / "cloned", log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    int running = 0;
    int ended = 0;
    for (const std::string& record : log.payloadsOf(GBM_EVENT_OPERATION_LOG_RECORD)) {
        if (!contains(record, "\"clone\"")) continue;
        (contains(record, "\"running\":true") ? running : ended)++;
    }
    EXPECT_EQ(running, 1);
    EXPECT_EQ(ended, 1);
}

TEST_F(CloneJobApiTest, ReportsTheTransferMeter) {
    // git prints no meter for a transfer this small (measured: none for a
    // 150-file repository), so the ssh child writes one: its stderr is git's.
    // The parse of git's own lines is TransferProgressTest's subject.
    useSshScript(std::string("printf 'Receiving objects:  50%% (8840/17333)\\r' >&2\n") +
                 waitWhileTestRuns());
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", base_ / "cloned", log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitFor([](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_CLONE_PROGRESS) return true;
        }
        return false;
    }));
    jobGuard.close();

    EXPECT_EQ(log.payloadsOf(GBM_EVENT_CLONE_PROGRESS).front(),
              "{\"phase\":\"receiving\",\"current\":8840,\"total\":17333}");
}

TEST_F(CloneJobApiTest, PassesDepthAndSubmoduleOptionsToGit) {
    const std::string url = makeBareOriginUrl();
    EventLog log;

    GbmCloneHandle job = start(url, base_ / "cloned", log, /*recurse=*/1, /*depth=*/1);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    bool sawOptions = false;
    for (const std::string& record : log.payloadsOf(GBM_EVENT_OPERATION_LOG_RECORD)) {
        if (contains(record, "\"--recurse-submodules\",\"--depth\",\"1\",\"--\"")) {
            sawOptions = true;
        }
    }
    EXPECT_TRUE(sawOptions);
    EXPECT_TRUE(contains(log.finished(), "\"ok\":true")) << log.finished();
}

TEST_F(CloneJobApiTest, ASourceThatDoesNotExistFinishesWithAnError) {
    EventLog log;
    const std::string url = "file://" + (base_ / "missing.git").generic_string();

    GbmCloneHandle job = start(url, base_ / "cloned", log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    const std::string finished = log.finished();
    EXPECT_TRUE(contains(finished, "\"ok\":false")) << finished;
    EXPECT_FALSE(contains(finished, "\"error\":null")) << finished;
    EXPECT_TRUE(contains(finished, "\"removedPath\":null")) << finished;
}

TEST_F(CloneJobApiTest, RefusesBeforeGitRuns) {
    EventLog log;
    const std::string url = "file:///nowhere.git";

    struct Case {
        const char* name;
        std::string url;
        std::string dest;
        int32_t depth;
    };

    const std::string ok = fsutil::utf8FromPath(base_ / "cloned");
    const std::vector<Case> cases = {
        {"empty url", "", ok, 0},
        {"url read as an option", "--upload-pack=touch x", ok, 0},
        {"negative depth", url, ok, -1},
        {"empty destination", url, "", 0},
        {"relative destination", url, "relative/dir", 0},
        {"destination with ..", url, fsutil::utf8FromPath(base_) + "/a/../cloned", 0},
        {"root destination", url, fsutil::utf8FromPath(base_.root_path()), 0},
    };
    for (const Case& c : cases) {
        GbmCloneHandle job =
            gbm_clone_start(c.url.c_str(), c.dest.c_str(), 0, c.depth, &logCallback, &log);
        EXPECT_EQ(job, nullptr) << c.name;
        EXPECT_TRUE(contains(lastResultJson(), "\"codeName\":\"InvalidArgument\""))
            << c.name << ": " << lastResultJson();
        gbm_clone_close(job);
    }
    GbmCloneHandle noCallback = gbm_clone_start(url.c_str(), ok.c_str(), 0, 0, nullptr, nullptr);
    EXPECT_EQ(noCallback, nullptr);
    gbm_clone_close(noCallback);
    EXPECT_TRUE(log.snapshot().empty());
}

TEST_F(CloneJobApiTest, RefusesTheHomeDirectory) {
    const char* home = std::getenv(
#ifdef _WIN32
        "USERPROFILE"
#else
        "HOME"
#endif
    );
    ASSERT_NE(home, nullptr);
    EventLog log;
    GbmCloneHandle job = gbm_clone_start("file:///nowhere.git", home, 0, 0, &logCallback, &log);
    JobGuard jobGuard(job);
    EXPECT_EQ(job, nullptr);
    jobGuard.close();
}

TEST_F(CloneJobApiTest, CancelLeavesNothingOfANewDestination) {
    useHangingSsh();
    const std::filesystem::path dest = base_ / "new";
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", dest, log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(waitUntil([&] { return std::filesystem::exists(dest / ".git"); }));
    gbm_clone_cancel(job);
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    const std::string finished = log.finished();
    EXPECT_TRUE(contains(finished, "\"codeName\":\"Cancelled\"")) << finished;
    EXPECT_TRUE(contains(finished, "\"removedPath\":" + jsonString(fsutil::utf8FromPath(dest))))
        << finished;
    EXPECT_FALSE(std::filesystem::exists(dest));
}

TEST_F(CloneJobApiTest, GitAndTheCleanupUseTheSameNormalisedPath) {
    // `<base>/./new/` is `<base>/new`; the path git is given, and the one the
    // cleanup reports, is the second.
    useHangingSsh();
    const std::filesystem::path dest = base_ / "new";
    const std::string spelled = fsutil::utf8FromPath(base_) + "/./new/";
    EventLog log;

    GbmCloneHandle job =
        gbm_clone_start("ssh://example.invalid/r.git", spelled.c_str(), 0, 0, &logCallback, &log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(waitUntil([&] { return std::filesystem::exists(dest / ".git"); }));
    gbm_clone_cancel(job);
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    EXPECT_TRUE(
        contains(log.finished(), "\"removedPath\":" + jsonString(fsutil::utf8FromPath(dest))))
        << log.finished();
    bool gitSawIt = false;
    for (const std::string& record : log.payloadsOf(GBM_EVENT_OPERATION_LOG_RECORD)) {
        if (contains(record, jsonString(fsutil::utf8FromPath(dest)) + "]")) gitSawIt = true;
    }
    EXPECT_TRUE(gitSawIt);
}

TEST_F(CloneJobApiTest, CancelEmptiesButKeepsAnExistingEmptyDirectory) {
    // On POSIX git's own SIGTERM cleanup empties the directory first, by path
    // (measured, git 2.56.0); on Windows git is terminated without one and the
    // job's removal does it. CloneDestinationTest covers that removal itself.
    useHangingSsh();
    const std::filesystem::path dest = base_ / "empty";
    std::filesystem::create_directories(dest);
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", dest, log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(waitUntil([&] { return std::filesystem::exists(dest / ".git"); }));
    { std::ofstream(dest / "partial.txt") << "x"; }
    gbm_clone_cancel(job);
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    const std::string finished = log.finished();
    EXPECT_TRUE(contains(finished, "\"removedPath\":" + jsonString(fsutil::utf8FromPath(dest))))
        << finished;
    ASSERT_TRUE(std::filesystem::is_directory(dest));
    EXPECT_TRUE(std::filesystem::is_empty(dest));
}

TEST_F(CloneJobApiTest, CancelNeverFollowsALinkOutOfTheDestination) {
    useHangingSsh();
    const std::filesystem::path outside = base_ / "outside";
    std::filesystem::create_directories(outside);
    { std::ofstream(outside / "sentinel.txt") << "keep"; }
    const std::filesystem::path dest = base_ / "empty";
    std::filesystem::create_directories(dest);
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", dest, log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(waitUntil([&] { return std::filesystem::exists(dest / ".git"); }));
    std::error_code linkError;
    ASSERT_TRUE(gbm::testing::makeDirectoryLink(outside, dest / "link", linkError))
        << linkError.message();
    gbm_clone_cancel(job);
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    EXPECT_TRUE(std::filesystem::exists(outside / "sentinel.txt"));
    EXPECT_FALSE(std::filesystem::exists(std::filesystem::symlink_status(dest / "link")));
}

TEST_F(CloneJobApiTest, CancelNeverTouchesADirectoryThatWasNotEmpty) {
    const std::filesystem::path dest = base_ / "full";
    std::filesystem::create_directories(dest);
    { std::ofstream(dest / "mine.txt") << "keep"; }
    useHangingSsh();
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", dest, log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    gbm_clone_cancel(job);
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    EXPECT_TRUE(contains(log.finished(), "\"removedPath\":null")) << log.finished();
    EXPECT_TRUE(std::filesystem::exists(dest / "mine.txt"));
}

TEST_F(CloneJobApiTest, ACredentialPromptIsRaisedAndAnswered) {
    // The script plays git's askpass client against the job's request
    // directory, which git passes down to its ssh child in GBM_ASKPASS_DIR.
    const std::filesystem::path answer = base_ / "answer.txt";
    useSshScript(
        "printf 'Password for x: ' > \"$GBM_ASKPASS_DIR/request\"\n"
        "while [ ! -f \"$GBM_ASKPASS_DIR/response\" ] && [ -d \"$GBM_ASKPASS_DIR\" ]; do\n"
        "  sleep 0.05\n"
        "done\n"
        "cat \"$GBM_ASKPASS_DIR/response\" > '" +
        answer.generic_string() +
        "'\n"
        "exit 1\n");
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", base_ / "cloned", log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitFor([](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_CREDENTIAL_REQUESTED) return true;
        }
        return false;
    }));
    EXPECT_EQ(log.payloadsOf(GBM_EVENT_CREDENTIAL_REQUESTED).front(),
              "{\"prompt\":\"Password for x: \"}");
    gbm_clone_provide_credential(job, "s3cret");
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    std::ifstream file(answer);
    const std::string written((std::istreambuf_iterator<char>(file)),
                              std::istreambuf_iterator<char>());
    EXPECT_EQ(written, "s3cret");
}

TEST_F(CloneJobApiTest, ACancelledPromptLetsTheCloneFail) {
    const std::filesystem::path marker = base_ / "cancelled.txt";
    useSshScript(
        "printf 'Password for x: ' > \"$GBM_ASKPASS_DIR/request\"\n"
        "while [ ! -f \"$GBM_ASKPASS_DIR/cancel\" ] && [ -d \"$GBM_ASKPASS_DIR\" ]; do\n"
        "  sleep 0.05\n"
        "done\n"
        "echo x > '" +
        marker.generic_string() +
        "'\n"
        "exit 1\n");
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", base_ / "cloned", log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(log.waitFor([](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_CREDENTIAL_REQUESTED) return true;
        }
        return false;
    }));
    gbm_clone_cancel_credential(job);
    ASSERT_TRUE(log.waitForFinished());
    jobGuard.close();

    EXPECT_TRUE(std::filesystem::exists(marker));
    EXPECT_TRUE(contains(log.finished(), "\"ok\":false")) << log.finished();
}

TEST_F(CloneJobApiTest, EachJobReceivesOnlyItsOwnRecords) {
    useHangingSsh();
    const std::filesystem::path destA = base_ / "a";
    const std::filesystem::path destB = base_ / "b";
    EventLog logA;
    EventLog logB;

    GbmCloneHandle jobA = start("ssh://example.invalid/a.git", destA, logA);
    JobGuard jobAGuard(jobA);
    GbmCloneHandle jobB = start("ssh://example.invalid/b.git", destB, logB);
    JobGuard jobBGuard(jobB);
    ASSERT_NE(jobA, nullptr);
    ASSERT_NE(jobB, nullptr);
    ASSERT_TRUE(waitUntil([&] {
        return std::filesystem::exists(destA / ".git") && std::filesystem::exists(destB / ".git");
    }));
    gbm_clone_cancel(jobA);
    gbm_clone_cancel(jobB);
    ASSERT_TRUE(logA.waitForFinished());
    ASSERT_TRUE(logB.waitForFinished());
    jobAGuard.close();
    jobBGuard.close();

    const std::vector<std::string> recordsA = logA.payloadsOf(GBM_EVENT_OPERATION_LOG_RECORD);
    const std::vector<std::string> recordsB = logB.payloadsOf(GBM_EVENT_OPERATION_LOG_RECORD);
    ASSERT_FALSE(recordsA.empty());
    ASSERT_FALSE(recordsB.empty());
    for (const std::string& record : recordsA) {
        EXPECT_TRUE(contains(record, "a.git")) << record;
        EXPECT_FALSE(contains(record, "b.git")) << record;
    }
    for (const std::string& record : recordsB) {
        EXPECT_TRUE(contains(record, "b.git")) << record;
        EXPECT_FALSE(contains(record, "a.git")) << record;
    }
}

TEST_F(CloneJobApiTest, CloseStopsARunningCloneAndEmitsNothingAfter) {
    useHangingSsh();
    const std::filesystem::path dest = base_ / "new";
    EventLog log;

    GbmCloneHandle job = start("ssh://example.invalid/r.git", dest, log);
    JobGuard jobGuard(job);
    ASSERT_NE(job, nullptr) << lastResultJson();
    ASSERT_TRUE(waitUntil([&] { return std::filesystem::exists(dest / ".git"); }));
    jobGuard.close();
    const std::size_t atClose = log.snapshot().size();
    std::this_thread::sleep_for(std::chrono::milliseconds(300));

    EXPECT_EQ(log.snapshot().size(), atClose);
    EXPECT_EQ(log.payloadsOf(GBM_EVENT_CLONE_FINISHED).size(), 1u);
}

// --- CloneDestination: the removal itself, without git -------------------

class CloneDestinationTest : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        base_ = std::filesystem::weakly_canonical(std::filesystem::temp_directory_path()) /
                ("gbm-capi-clonedest-" + std::string(info->name()));
        std::filesystem::remove_all(base_);
        std::filesystem::create_directories(base_);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(base_, ec);
    }

    static void write(const std::filesystem::path& file, const std::string& text = "x") {
        std::filesystem::create_directories(file.parent_path());
        std::ofstream(file) << text;
    }

    static void link(const std::filesystem::path& target, const std::filesystem::path& at) {
        std::error_code ec;
        ASSERT_TRUE(gbm::testing::makeDirectoryLink(target, at, ec)) << ec.message();
    }

    std::filesystem::path base_;
};

TEST_F(CloneDestinationTest, AnAbsentDestinationIsOursAndIsRemovedWhole) {
    const std::filesystem::path dest = base_ / "new";
    const CloneDestination claim = CloneDestination::claim(dest);
    ASSERT_TRUE(claim.owned());
    write(dest / ".git" / "HEAD");
    write(dest / "README.md");

    const CloneDestination::Removal removal = claim.removeUnfinished();

    EXPECT_EQ(removal.removedPath, dest);
    EXPECT_EQ(removal.error, std::nullopt);
    EXPECT_FALSE(std::filesystem::exists(dest));
}

TEST_F(CloneDestinationTest, AnExistingEmptyDirectoryIsEmptiedAndKept) {
    const std::filesystem::path dest = base_ / "empty";
    std::filesystem::create_directories(dest);
    const CloneDestination claim = CloneDestination::claim(dest);
    ASSERT_TRUE(claim.owned());
    write(dest / ".git" / "HEAD");
    write(dest / "partial.txt");

    const CloneDestination::Removal removal = claim.removeUnfinished();

    EXPECT_EQ(removal.removedPath, dest);
    ASSERT_TRUE(std::filesystem::is_directory(dest));
    EXPECT_TRUE(std::filesystem::is_empty(dest));
}

TEST_F(CloneDestinationTest, ANonEmptyDirectoryIsNeverOurs) {
    const std::filesystem::path dest = base_ / "full";
    write(dest / "mine.txt");
    const CloneDestination claim = CloneDestination::claim(dest);
    EXPECT_FALSE(claim.owned());

    const CloneDestination::Removal removal = claim.removeUnfinished();

    EXPECT_EQ(removal.removedPath, std::nullopt);
    EXPECT_TRUE(std::filesystem::exists(dest / "mine.txt"));
}

TEST_F(CloneDestinationTest, ALinkToAnEmptyDirectoryIsNeverOurs) {
    const std::filesystem::path target = base_ / "target";
    std::filesystem::create_directories(target);
    const std::filesystem::path dest = base_ / "link";
    link(target, dest);

    EXPECT_FALSE(CloneDestination::claim(dest).owned());
}

TEST_F(CloneDestinationTest, ALinkInsideIsRemovedWithoutFollowingIt) {
    const std::filesystem::path outside = base_ / "outside";
    write(outside / "sentinel.txt", "keep");
    const std::filesystem::path dest = base_ / "empty";
    std::filesystem::create_directories(dest);
    const CloneDestination claim = CloneDestination::claim(dest);
    link(outside, dest / "link");

    const CloneDestination::Removal removal = claim.removeUnfinished();

    EXPECT_EQ(removal.removedPath, dest);
    EXPECT_TRUE(std::filesystem::exists(outside / "sentinel.txt"));
    EXPECT_FALSE(std::filesystem::exists(std::filesystem::symlink_status(dest / "link")));
}

TEST_F(CloneDestinationTest, ALinkInsideANewDestinationIsNotFollowedEither) {
    const std::filesystem::path outside = base_ / "outside";
    write(outside / "sentinel.txt", "keep");
    const std::filesystem::path dest = base_ / "new";
    const CloneDestination claim = CloneDestination::claim(dest);
    std::filesystem::create_directories(dest);
    link(outside, dest / "link");

    EXPECT_EQ(claim.removeUnfinished().removedPath, dest);
    EXPECT_TRUE(std::filesystem::exists(outside / "sentinel.txt"));
}

TEST_F(CloneDestinationTest, AnEmptyDirectorySwappedForAnotherIsLeftAlone) {
    const std::filesystem::path dest = base_ / "empty";
    std::filesystem::create_directories(dest);
    const CloneDestination claim = CloneDestination::claim(dest);
    std::filesystem::rename(dest, base_ / "moved");
    write(dest / "theirs.txt", "keep");

    const CloneDestination::Removal removal = claim.removeUnfinished();

    EXPECT_EQ(removal.removedPath, std::nullopt);
    EXPECT_NE(removal.error, std::nullopt);
    EXPECT_TRUE(std::filesystem::exists(dest / "theirs.txt"));
}

TEST_F(CloneDestinationTest, ADestinationReplacedByALinkIsLeftAlone) {
    const std::filesystem::path outside = base_ / "outside";
    write(outside / "sentinel.txt", "keep");
    const std::filesystem::path dest = base_ / "new";
    const CloneDestination claim = CloneDestination::claim(dest);
    link(outside, dest);

    const CloneDestination::Removal removal = claim.removeUnfinished();

    EXPECT_EQ(removal.removedPath, std::nullopt);
    EXPECT_NE(removal.error, std::nullopt);
    EXPECT_TRUE(std::filesystem::exists(outside / "sentinel.txt"));
}

TEST_F(CloneDestinationTest, ADestinationWhoseParentWasSwappedIsLeftAlone) {
    const std::filesystem::path parent = base_ / "parent";
    std::filesystem::create_directories(parent);
    const std::filesystem::path dest = parent / "new";
    const CloneDestination claim = CloneDestination::claim(dest);
    std::filesystem::rename(parent, base_ / "parent-moved");
    write(dest / "theirs.txt", "keep");

    const CloneDestination::Removal removal = claim.removeUnfinished();

    EXPECT_EQ(removal.removedPath, std::nullopt);
    EXPECT_NE(removal.error, std::nullopt);
    EXPECT_TRUE(std::filesystem::exists(dest / "theirs.txt"));
}

TEST_F(CloneDestinationTest, NothingLeftAtAnOwnedDestinationCountsAsRemoved) {
    // git's own SIGTERM cleanup removed it first.
    const std::filesystem::path dest = base_ / "new";
    const CloneDestination claim = CloneDestination::claim(dest);

    EXPECT_EQ(claim.removeUnfinished().removedPath, dest);
}

}  // namespace
}  // namespace gbm::capi
