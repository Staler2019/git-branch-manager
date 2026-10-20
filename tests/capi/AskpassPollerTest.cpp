// White-box tests for AskpassPoller against the real askpass client
// (askpass::runClientForDir), simulating the blocked `git` subprocess a real
// fetch/pull/push would spawn -- see core/git/AskpassHelper.h's protocol
// doc comment and Session::beginAskpass()/endAskpass().
#include "capi/AskpassPoller.h"

#include "core/git/AskpassHelper.h"

#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <gtest/gtest.h>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace gbm::capi {
namespace {

struct PromptCapture {
    std::mutex mutex;
    std::condition_variable cv;
    std::vector<std::string> prompts;

    void add(std::string prompt) {
        std::lock_guard<std::mutex> lock(mutex);
        prompts.push_back(std::move(prompt));
        cv.notify_all();
    }

    bool waitForCount(std::size_t count, std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return prompts.size() >= count; });
    }
};

/// Runs the real askpass client on its own thread and guarantees it is
/// joined before returning, even if the caller's expectation about the
/// prompt arriving turns out false -- an unjoined std::thread whose
/// destructor runs while still joinable is std::terminate, and
/// runClientForDir() blocks for up to kResponseTimeout (10 minutes) if
/// nothing ever answers it, so every test here must resolve the prompt
/// (answer or cancel) unconditionally before the thread can be joined.
class ScopedClient {
public:
    ScopedClient(std::filesystem::path dir, std::string prompt)
        : thread_([this, dir = std::move(dir), prompt = std::move(prompt)] {
              exitCode_ = askpass::runClientForDir(dir, prompt);
          }) {}

    ~ScopedClient() {
        if (thread_.joinable()) {
            thread_.join();
        }
    }

    ScopedClient(const ScopedClient&) = delete;
    ScopedClient& operator=(const ScopedClient&) = delete;

    void join() { thread_.join(); }
    int exitCode() const { return exitCode_; }

private:
    // Declared (and thus constructed) before thread_: member init order
    // follows declaration order regardless of the constructor's init-list
    // order, and thread_'s member-initializer starts the background thread
    // immediately -- if exitCode_ were declared after thread_, its `= -1`
    // default-member-initializer would race the already-running thread's
    // `exitCode_ = ...` write (TSan-confirmed).
    int exitCode_ = -1;
    std::thread thread_;
};

TEST(AskpassPollerTest, AnswerLetsTheClientSucceedWithTheSecret) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    PromptCapture capture;
    AskpassPoller poller;
    poller.start(dir, [&capture](std::string prompt) { capture.add(std::move(prompt)); });

    ScopedClient client(dir, "Password for 'https://example.invalid': ");
    const bool sawPrompt = capture.waitForCount(1);
    if (sawPrompt) {
        poller.answer("hunter2");
    } else {
        poller.cancelPrompt();
    }
    client.join();

    ASSERT_TRUE(sawPrompt);
    EXPECT_EQ(capture.prompts[0], "Password for 'https://example.invalid': ");
    EXPECT_EQ(client.exitCode(), 0);

    poller.stop();
    EXPECT_FALSE(std::filesystem::exists(dir));
}

TEST(AskpassPollerTest, CancelPromptLetsTheClientFailPromptly) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    PromptCapture capture;
    AskpassPoller poller;
    poller.start(dir, [&capture](std::string prompt) { capture.add(std::move(prompt)); });

    ScopedClient client(dir, "Username: ");
    const bool sawPrompt = capture.waitForCount(1);
    poller.cancelPrompt();
    client.join();

    ASSERT_TRUE(sawPrompt);
    EXPECT_EQ(client.exitCode(), 1);
    poller.stop();
}

TEST(AskpassPollerTest, StopBeforeStartIsANoop) {
    AskpassPoller poller;
    poller.stop();  // no crash
}

TEST(AskpassPollerTest, StartWithEmptyDirectoryIsANoop) {
    PromptCapture capture;
    AskpassPoller poller;
    poller.start({}, [&capture](std::string prompt) { capture.add(std::move(prompt)); });

    EXPECT_FALSE(capture.waitForCount(1, std::chrono::milliseconds(300)));
    poller.stop();
}

TEST(AskpassPollerTest, SecondPromptInTheSameDirectoryIsDetectedAfterTheFirstIsAnswered) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    PromptCapture capture;
    AskpassPoller poller;
    poller.start(dir, [&capture](std::string prompt) { capture.add(std::move(prompt)); });

    {
        ScopedClient firstClient(dir, "Username for 'https://example.invalid': ");
        const bool sawFirstPrompt = capture.waitForCount(1);
        if (sawFirstPrompt) {
            poller.answer("alice");
        } else {
            poller.cancelPrompt();
        }
        firstClient.join();
        ASSERT_TRUE(sawFirstPrompt);
        EXPECT_EQ(firstClient.exitCode(), 0);
    }

    // A gap longer than one poll: the poller sees the first request gone
    // before the second appears. The no-gap case, which is what git
    // actually does, is the next test.
    std::this_thread::sleep_for(std::chrono::milliseconds(500));

    ScopedClient secondClient(dir, "Password for 'https://alice@example.invalid': ");
    const bool sawSecondPrompt = capture.waitForCount(2);
    if (sawSecondPrompt) {
        poller.answer("hunter2");
    } else {
        poller.cancelPrompt();
    }
    secondClient.join();

    ASSERT_TRUE(sawSecondPrompt);
    EXPECT_EQ(capture.prompts[1], "Password for 'https://alice@example.invalid': ");
    EXPECT_EQ(secondClient.exitCode(), 0);

    poller.stop();
}

#ifndef _WIN32
TEST(AskpassPollerTest, AFollowUpPromptThatArrivesAtOnceIsStillDetected) {
    // git starts the Password client within milliseconds of the Username
    // client exiting -- well inside one 150ms poll, so the request file is
    // never seen missing. Measured end to end against a real Basic-auth
    // server before this was fixed: the second prompt was never raised.
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    PromptCapture capture;
    AskpassPoller poller;
    poller.start(dir, [&capture](std::string prompt) { capture.add(std::move(prompt)); });

    {
        ScopedClient firstClient(dir, "Username for 'https://example.invalid': ");
        const bool sawFirstPrompt = capture.waitForCount(1);
        if (sawFirstPrompt) {
            poller.answer("alice");
        } else {
            poller.cancelPrompt();
        }
        firstClient.join();
        ASSERT_TRUE(sawFirstPrompt);
        EXPECT_EQ(firstClient.exitCode(), 0);
    }

    ScopedClient secondClient(dir, "Password for 'https://alice@example.invalid': ");
    const bool sawSecondPrompt = capture.waitForCount(2);
    // Left unanswered for a few polls: the one outstanding prompt is raised
    // once, not again on every poll.
    const bool sawAThirdPrompt = capture.waitForCount(3, std::chrono::milliseconds(450));
    if (sawSecondPrompt) {
        poller.answer("hunter2");
    } else {
        poller.cancelPrompt();
    }
    secondClient.join();

    ASSERT_TRUE(sawSecondPrompt);
    EXPECT_FALSE(sawAThirdPrompt);
    // Exactly the second prompt, not the first one raised twice.
    EXPECT_EQ(capture.prompts[1], "Password for 'https://alice@example.invalid': ");
    EXPECT_EQ(secondClient.exitCode(), 0);

    poller.stop();
}

TEST(AskpassPollerTest, TheAnswerIsWrittenOwnerOnly) {
    // No client consumes it here, so the file is still there to inspect.
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());
    AskpassPoller poller;
    poller.start(dir, [](std::string) {});

    poller.answer("hunter2");

    const auto file = dir / std::string(askpass::kResponseFile);
    ASSERT_TRUE(std::filesystem::exists(file));
    const auto perms = std::filesystem::status(file).permissions();
    EXPECT_EQ(perms & std::filesystem::perms::all,
              std::filesystem::perms::owner_read | std::filesystem::perms::owner_write);
    poller.stop();
}
#endif

TEST(AskpassPollerTest, StopReleasesAClientStillWaitingForAnAnswer) {
    // A cancelled fetch ends with endAskpass() -> stop() while the askpass
    // child is still waiting; it must not be left polling for ten minutes.
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());
    PromptCapture capture;
    AskpassPoller poller;
    poller.start(dir, [&capture](std::string prompt) { capture.add(std::move(prompt)); });
    ScopedClient client(dir, "Password: ");
    ASSERT_TRUE(capture.waitForCount(1)) << "prompt never seen; client would block";

    const auto stoppedAt = std::chrono::steady_clock::now();
    poller.stop();
    client.join();

    EXPECT_EQ(client.exitCode(), 1);
    EXPECT_LT(std::chrono::steady_clock::now() - stoppedAt, std::chrono::seconds(2));
}

}  // namespace
}  // namespace gbm::capi
