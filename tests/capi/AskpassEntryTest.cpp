// gbm_askpass_main is how the three desktop runners answer git's credential
// prompt: GIT_ASKPASS points at the app's own executable, so the runner must
// recognise GBM_ASKPASS_MODE at the very top of start-up, answer through
// stdout and exit before any GUI exists. Nothing in the Flutter runners did
// that until security review P1-A found it, so every askpass prompt started a
// second app window and left git waiting.
//
// The subprocess tests drive fixtures/askpass_launcher.cpp, which intercepts
// exactly as the runners do -- the runners themselves have no test harness.
#include "capi/AskpassPoller.h"
#include "capi/gbm_capi.h"
#include "core/base/CancellationToken.h"
#include "core/base/FsUtil.h"
#include "core/git/AskpassHelper.h"
#include "core/git/IProcessRunner.h"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <gtest/gtest.h>
#include <string>
#include <thread>

namespace gbm::capi {
namespace {

constexpr const char* kGuiSentinel = "GBM-LAUNCHER-GUI-STARTED";

void setEnv(const char* key, const char* value) {
#ifdef _WIN32
    _putenv_s(key, value);
#else
    setenv(key, value, 1);
#endif
}

void unsetEnv(const char* key) {
#ifdef _WIN32
    _putenv_s(key, "");
#else
    unsetenv(key);
#endif
}

GitCommand launcherCommand() {
    GitCommand command({}, {"Password for 'https://example.invalid': "});
    command.timeout = std::chrono::seconds(20);
    return command;
}

TEST(AskpassEntryTest, OutsideAskpassModeItLetsTheAppStart) {
    unsetEnv("GBM_ASKPASS_MODE");
    const char* const argv[] = {"app", "Password: "};
    EXPECT_EQ(gbm_askpass_main(2, argv), -1);
}

TEST(AskpassEntryTest, AskpassModeWithoutARequestDirectoryFailsTheCredential) {
    setEnv("GBM_ASKPASS_MODE", "1");
    unsetEnv("GBM_ASKPASS_DIR");
    const char* const argv[] = {"app", "Password: "};
    const int code = gbm_askpass_main(2, argv);
    unsetEnv("GBM_ASKPASS_MODE");
    EXPECT_EQ(code, 1);
}

TEST(AskpassEntryTest, TheLauncherAnswersThroughStdoutAndNeverStartsItsGui) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());
    AskpassPoller poller;
    poller.start(dir, [&poller](std::string) { poller.answer("s3cret"); });

    GitCommand command = launcherCommand();
    command.envOverrides.emplace_back("GBM_ASKPASS_MODE", "1");
    command.envOverrides.emplace_back("GBM_ASKPASS_DIR", fsutil::utf8FromPath(dir));
    command.envOverrides.emplace_back("GBM_CAPI_LIBRARY_PATH", GBM_CAPI_LIBRARY_FILE);
    auto runner = makeProcessRunner(std::filesystem::path(GBM_ASKPASS_LAUNCHER_EXE));

    auto result = runner->run(command, CancellationToken{});
    poller.stop();

    ASSERT_TRUE(result) << result.error().message;
    EXPECT_NE(result->out.find("s3cret"), std::string::npos)
        << "git reads the secret from the askpass program's stdout: " << result->out;
    EXPECT_EQ(result->out.find(kGuiSentinel), std::string::npos) << "the GUI started";
}

TEST(AskpassEntryTest, WithoutAskpassModeTheLauncherStartsItsGui) {
    auto runner = makeProcessRunner(std::filesystem::path(GBM_ASKPASS_LAUNCHER_EXE));

    auto result = runner->run(launcherCommand(), CancellationToken{});

    ASSERT_TRUE(result) << result.error().message;
    EXPECT_NE(result->out.find(kGuiSentinel), std::string::npos) << result->out;
}

TEST(AskpassEntryTest, AMissingLibraryFailsTheCredentialWithoutStartingTheGui) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());
    GitCommand command = launcherCommand();
    command.envOverrides.emplace_back("GBM_ASKPASS_MODE", "1");
    command.envOverrides.emplace_back("GBM_ASKPASS_DIR", fsutil::utf8FromPath(dir));
    command.envOverrides.emplace_back("GBM_CAPI_LIBRARY_PATH",
                                      fsutil::utf8FromPath(dir / "no-such-library"));
    auto runner = makeProcessRunner(std::filesystem::path(GBM_ASKPASS_LAUNCHER_EXE));

    auto result = runner->run(command, CancellationToken{});
    std::filesystem::remove_all(dir);

    // The GUI branch exits 0; only the askpass branch can fail.
    EXPECT_FALSE(result)
        << "a launcher that cannot answer must fail git's prompt, not open a window";
}

}  // namespace
}  // namespace gbm::capi
