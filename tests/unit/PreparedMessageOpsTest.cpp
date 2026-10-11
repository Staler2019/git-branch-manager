// PreparedMessageStore against FakeProcessRunner: the command it runs and
// what it feeds it. Whether `git stripspace` really strips what git's own
// commit would is GitIntegrationTest's job (RealRepoTest.PreparedMessage...),
// because only a real git can disagree with it.
#include "core/git/ops/PreparedMessageOps.h"
#include "support/FakeProcessRunner.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

class PreparedMessageStoreTest : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-test-" + std::string(info->test_suite_name()) + "-" + std::string(info->name()));
        std::filesystem::remove_all(root_);
        std::filesystem::create_directories(root_);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    void writeFile(const std::string& name, const std::string& contents) {
        std::ofstream out(root_ / name, std::ios::binary | std::ios::trunc);
        out << contents;
    }

    RepoPaths paths() const { return RepoPaths(root_, root_, root_); }

    std::filesystem::path root_;
};

FakeProcessRunner::Response ok(std::string out) {
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    response.out = std::move(out);
    return response;
}

TEST_F(PreparedMessageStoreTest, StripsThePreparedTextThroughGitStripspaceOnStdin) {
    writeFile("MERGE_MSG", "Merge branch 'topic'\n\n# Conflicts:\n#\tf\n");
    FakeProcessRunner runner;
    runner.whenArgsContain({"stripspace"}, ok("Merge branch 'topic'\n"));

    PreparedMessageStore store(runner, paths());
    auto message = store.read(CancellationToken{});

    ASSERT_TRUE(message) << message.error().message;
    EXPECT_EQ(*message, "Merge branch 'topic'\n");
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0), (std::vector<std::string>{"stripspace", "--strip-comments"}));
    // On stdin, not argv: a message has no length limit an argv entry has.
    EXPECT_EQ(runner.invocations()[0].stdinData, "Merge branch 'topic'\n\n# Conflicts:\n#\tf\n");
}

TEST_F(PreparedMessageStoreTest, RunsNothingWhenGitPreparedNoMessage) {
    FakeProcessRunner runner;

    PreparedMessageStore store(runner, paths());
    auto message = store.read(CancellationToken{});

    ASSERT_TRUE(message) << message.error().message;
    EXPECT_EQ(*message, "");
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST_F(PreparedMessageStoreTest, ReportsAFailedStripspaceAsAnError) {
    writeFile("MERGE_MSG", "Merge branch 'topic'\n");
    FakeProcessRunner runner;
    FakeProcessRunner::Response failed;
    failed.exitCode = 128;
    failed.err = "error: core.commentchar must have at least one character\n";
    runner.whenArgsContain({"stripspace"}, failed);

    PreparedMessageStore store(runner, paths());
    auto message = store.read(CancellationToken{});

    EXPECT_FALSE(message);
}

}  // namespace
}  // namespace gbm
